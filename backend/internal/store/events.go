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
	if _, err = tx.Exec(upsertLogFileSQL,
		state.Path, state.Tool, state.SizeBytes, state.MtimeUnix,
		lastTotal, lastModel, time.Now().Unix(),
	); err != nil {
		return fmt.Errorf("upsert log_files: %w", err)
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

// DistinctSessions counts distinct source_file within the range.
func (s *Store) DistinctSessions(tool string, startUTC, endUTC int64) (int, error) {
	const q = `SELECT COUNT(DISTINCT source_file) FROM usage_events
	           WHERE tool = ? AND ts_utc >= ? AND ts_utc < ?`
	var n int
	err := s.db.QueryRow(q, tool, startUTC, endUTC).Scan(&n)
	return n, err
}
