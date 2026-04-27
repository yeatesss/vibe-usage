package store

import (
	"database/sql"
	"fmt"
	"time"

	"github.com/yeatesss/vibe-usage/backend/internal/parser"
)

const insertEventSQL = `
INSERT OR IGNORE INTO usage_events
  (ts_utc, tool, model, input_tokens, output_tokens, cache_read_tokens,
   cache_write_tokens, reasoning_output_tokens, source_file, source_offset)
VALUES (?,?,?,?,?,?,?,?,?,?)
`

const upsertLogFileSQL = `
INSERT INTO log_files (path, tool, size_bytes, mtime_unix, last_total_json, last_model, updated_at)
VALUES (?,?,?,?,?,?,?)
ON CONFLICT(path) DO UPDATE SET
  tool = excluded.tool,
  size_bytes = excluded.size_bytes,
  mtime_unix = excluded.mtime_unix,
  last_total_json = excluded.last_total_json,
  last_model = excluded.last_model,
  updated_at = excluded.updated_at
`

// upsertSessionSQL: project-level metadata per source-file.
//   - cwd / git_branch: keep existing value when the new one is empty
//     (parsers may scan a tail with no meta lines and we don't want to wipe)
//   - first_ts_utc: keep the earliest seen across all scans (NULL-safe)
//   - last_ts_utc:  keep the latest seen across all scans (NULL-safe)
const upsertSessionSQL = `
INSERT INTO sessions (source_file, tool, cwd, git_branch, first_ts_utc, last_ts_utc, updated_at)
VALUES (?,?,?,?,?,?,?)
ON CONFLICT(source_file) DO UPDATE SET
  tool = excluded.tool,
  cwd = CASE WHEN excluded.cwd != '' THEN excluded.cwd ELSE sessions.cwd END,
  git_branch = CASE WHEN excluded.git_branch != '' THEN excluded.git_branch ELSE sessions.git_branch END,
  first_ts_utc = CASE
    WHEN excluded.first_ts_utc IS NULL THEN sessions.first_ts_utc
    WHEN sessions.first_ts_utc IS NULL THEN excluded.first_ts_utc
    WHEN excluded.first_ts_utc < sessions.first_ts_utc THEN excluded.first_ts_utc
    ELSE sessions.first_ts_utc
  END,
  last_ts_utc = CASE
    WHEN excluded.last_ts_utc IS NULL THEN sessions.last_ts_utc
    WHEN sessions.last_ts_utc IS NULL THEN excluded.last_ts_utc
    WHEN excluded.last_ts_utc > sessions.last_ts_utc THEN excluded.last_ts_utc
    ELSE sessions.last_ts_utc
  END,
  updated_at = excluded.updated_at
`

// CommitFileParse atomically inserts events (idempotent via UNIQUE(source_file,source_offset))
// and upserts the log_files state row. Returns the number of newly inserted events.
func (s *Store) CommitFileParse(state parser.FileState, events []parser.Event) error {
	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var stmt *sql.Stmt
	if len(events) > 0 {
		stmt, err = tx.Prepare(insertEventSQL)
		if err != nil {
			return fmt.Errorf("prepare events insert: %w", err)
		}
		defer stmt.Close()
		for _, e := range events {
			if _, err = stmt.Exec(
				e.TsUTC.Unix(), e.Tool, e.Model,
				e.InputTokens, e.OutputTokens, e.CacheReadTokens,
				e.CacheWriteTokens, e.ReasoningOutputTokens,
				e.SourceFile, e.SourceOffset,
			); err != nil {
				return fmt.Errorf("insert event: %w", err)
			}
		}
	}

	var lastTotal, lastModel interface{}
	if state.LastTotalJSON != "" {
		lastTotal = state.LastTotalJSON
	}
	if state.LastModel != "" {
		lastModel = state.LastModel
	}
	now := time.Now().Unix()
	if _, err = tx.Exec(upsertLogFileSQL,
		state.Path, state.Tool, state.SizeBytes, state.MtimeUnix,
		lastTotal, lastModel, now,
	); err != nil {
		return fmt.Errorf("upsert log_files: %w", err)
	}

	// Upsert sessions row alongside log_files. Pass the min/max ts from this
	// batch so the row's first/last range can be widened over time.
	var firstTs, lastTs interface{}
	for i, e := range events {
		t := e.TsUTC.Unix()
		if i == 0 {
			firstTs = t
			lastTs = t
			continue
		}
		if tt, ok := firstTs.(int64); ok && t < tt {
			firstTs = t
		}
		if tt, ok := lastTs.(int64); ok && t > tt {
			lastTs = t
		}
	}
	if _, err = tx.Exec(upsertSessionSQL,
		state.Path, state.Tool, state.Cwd, state.GitBranch,
		firstTs, lastTs, now,
	); err != nil {
		return fmt.Errorf("upsert sessions: %w", err)
	}

	err = tx.Commit()
	if err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}

// ModelTokenSum aggregates tokens by model within a time range.
type ModelTokenSum struct {
	Model                                                     string
	Input, Output, CacheRead, CacheWrite, Reasoning, Requests int64
}

// SumByModel returns per-model token totals for the given tool in [startUTC,endUTC).
func (s *Store) SumByModel(tool string, startUTC, endUTC int64) ([]ModelTokenSum, error) {
	const q = `
SELECT model,
       COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0),
       COALESCE(SUM(cache_read_tokens),0), COALESCE(SUM(cache_write_tokens),0),
       COALESCE(SUM(reasoning_output_tokens),0), COUNT(*)
FROM usage_events
WHERE tool = ? AND ts_utc >= ? AND ts_utc < ?
GROUP BY model`
	rows, err := s.db.Query(q, tool, startUTC, endUTC)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ModelTokenSum
	for rows.Next() {
		var r ModelTokenSum
		if err := rows.Scan(&r.Model, &r.Input, &r.Output, &r.CacheRead, &r.CacheWrite, &r.Reasoning, &r.Requests); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// SumByModelForProject is like SumByModel but restricted to events whose
// source_file belongs to a sessions row with the given cwd.
func (s *Store) SumByModelForProject(tool, project string, startUTC, endUTC int64) ([]ModelTokenSum, error) {
	const q = `
SELECT e.model,
       COALESCE(SUM(e.input_tokens),0), COALESCE(SUM(e.output_tokens),0),
       COALESCE(SUM(e.cache_read_tokens),0), COALESCE(SUM(e.cache_write_tokens),0),
       COALESCE(SUM(e.reasoning_output_tokens),0), COUNT(*)
FROM usage_events e
JOIN sessions s ON s.source_file = e.source_file
WHERE e.tool = ? AND s.cwd = ? AND e.ts_utc >= ? AND e.ts_utc < ?
GROUP BY e.model`
	rows, err := s.db.Query(q, tool, project, startUTC, endUTC)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ModelTokenSum
	for rows.Next() {
		var r ModelTokenSum
		if err := rows.Scan(&r.Model, &r.Input, &r.Output, &r.CacheRead, &r.CacheWrite, &r.Reasoning, &r.Requests); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// BucketTotal is a (bucketIndex, totalTokens) pair.
type BucketTotal struct {
	Index int
	Total int64
}

// TotalInRange returns total tokens (input+output+cache_read+cache_write) in [startUTC,endUTC).
func (s *Store) TotalInRange(tool string, startUTC, endUTC int64) (int64, error) {
	const q = `SELECT COALESCE(SUM(input_tokens+output_tokens+cache_read_tokens+cache_write_tokens), 0)
	           FROM usage_events WHERE tool = ? AND ts_utc >= ? AND ts_utc < ?`
	var n int64
	err := s.db.QueryRow(q, tool, startUTC, endUTC).Scan(&n)
	return n, err
}

// TotalInRangeForProject is TotalInRange filtered to a single project (cwd).
func (s *Store) TotalInRangeForProject(tool, project string, startUTC, endUTC int64) (int64, error) {
	const q = `SELECT COALESCE(SUM(e.input_tokens+e.output_tokens+e.cache_read_tokens+e.cache_write_tokens), 0)
	           FROM usage_events e
	           JOIN sessions s ON s.source_file = e.source_file
	           WHERE e.tool = ? AND s.cwd = ? AND e.ts_utc >= ? AND e.ts_utc < ?`
	var n int64
	err := s.db.QueryRow(q, tool, project, startUTC, endUTC).Scan(&n)
	return n, err
}

// DistinctSessions counts distinct source_file within the range.
func (s *Store) DistinctSessions(tool string, startUTC, endUTC int64) (int, error) {
	const q = `SELECT COUNT(DISTINCT source_file) FROM usage_events
	           WHERE tool = ? AND ts_utc >= ? AND ts_utc < ?`
	var n int
	err := s.db.QueryRow(q, tool, startUTC, endUTC).Scan(&n)
	return n, err
}

// DistinctSessionsForProject counts distinct source_file within the range
// restricted to a single project (cwd).
func (s *Store) DistinctSessionsForProject(tool, project string, startUTC, endUTC int64) (int, error) {
	const q = `SELECT COUNT(DISTINCT e.source_file)
	           FROM usage_events e
	           JOIN sessions s ON s.source_file = e.source_file
	           WHERE e.tool = ? AND s.cwd = ? AND e.ts_utc >= ? AND e.ts_utc < ?`
	var n int
	err := s.db.QueryRow(q, tool, project, startUTC, endUTC).Scan(&n)
	return n, err
}

// ProjectAgg is the per-project aggregation row produced by ListProjects.
type ProjectAgg struct {
	Cwd            string
	GitBranches    string // comma-separated set of branches seen for this cwd
	InputTokens    int64
	OutputTokens   int64
	CacheReadTok   int64
	CacheWriteTok  int64
	ReasoningTok   int64
	Requests       int64
	Sessions       int64
	LastActiveUTC  int64
	FirstActiveUTC int64
}

// ListProjects aggregates usage_events grouped by sessions.cwd within
// [startUTC,endUTC), restricted to a single tool. Empty cwd is bucketed as ""
// and represented to clients as "(unknown)" upstream.
func (s *Store) ListProjects(tool string, startUTC, endUTC int64) ([]ProjectAgg, error) {
	const q = `
SELECT
  s.cwd,
  COALESCE(GROUP_CONCAT(DISTINCT s.git_branch), '') AS branches,
  COALESCE(SUM(e.input_tokens), 0),
  COALESCE(SUM(e.output_tokens), 0),
  COALESCE(SUM(e.cache_read_tokens), 0),
  COALESCE(SUM(e.cache_write_tokens), 0),
  COALESCE(SUM(e.reasoning_output_tokens), 0),
  COUNT(e.id),
  COUNT(DISTINCT e.source_file),
  COALESCE(MAX(e.ts_utc), 0),
  COALESCE(MIN(e.ts_utc), 0)
FROM sessions s
JOIN usage_events e ON e.source_file = s.source_file
WHERE s.tool = ? AND e.tool = ? AND e.ts_utc >= ? AND e.ts_utc < ?
GROUP BY s.cwd
ORDER BY SUM(e.input_tokens + e.output_tokens + e.cache_read_tokens + e.cache_write_tokens) DESC`
	rows, err := s.db.Query(q, tool, tool, startUTC, endUTC)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ProjectAgg
	for rows.Next() {
		var p ProjectAgg
		if err := rows.Scan(
			&p.Cwd, &p.GitBranches,
			&p.InputTokens, &p.OutputTokens, &p.CacheReadTok, &p.CacheWriteTok, &p.ReasoningTok,
			&p.Requests, &p.Sessions, &p.LastActiveUTC, &p.FirstActiveUTC,
		); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}
