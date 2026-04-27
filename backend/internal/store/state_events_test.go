package store

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/yeatesss/vibe-usage/backend/internal/parser"
)

func newTestStore(t *testing.T) *Store {
	t.Helper()
	st, err := Open(filepath.Join(t.TempDir(), "data.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })
	return st
}

func TestGetFileState_Missing(t *testing.T) {
	st := newTestStore(t)
	_, ok, err := st.GetFileState("/nowhere")
	require.NoError(t, err)
	assert.False(t, ok)
}

func TestCommitFileParse_InsertsEventsAndUpsertsState(t *testing.T) {
	st := newTestStore(t)
	events := []parser.Event{
		{
			TsUTC: time.Date(2026, 4, 22, 1, 0, 0, 0, time.UTC),
			Tool:  "claude", Model: "claude-sonnet-4-6",
			InputTokens:  100,
			OutputTokens: 50,
			SourceFile:   "/logs/a.jsonl", SourceOffset: 0,
		},
	}
	newState := parser.FileState{
		Path: "/logs/a.jsonl", Tool: "claude",
		SizeBytes: 500, MtimeUnix: 12345,
	}
	require.NoError(t, st.CommitFileParse(newState, events))

	fs, ok, err := st.GetFileState("/logs/a.jsonl")
	require.NoError(t, err)
	require.True(t, ok)
	assert.Equal(t, int64(500), fs.SizeBytes)
	assert.Equal(t, int64(12345), fs.MtimeUnix)

	var count int
	require.NoError(t, st.DB().QueryRow("SELECT COUNT(*) FROM usage_events").Scan(&count))
	assert.Equal(t, 1, count)
}

func TestCommitFileParse_IdempotentOnReinsert(t *testing.T) {
	st := newTestStore(t)
	ev := parser.Event{
		TsUTC: time.Date(2026, 4, 22, 1, 0, 0, 0, time.UTC),
		Tool:  "claude", Model: "m",
		InputTokens: 10,
		SourceFile:  "/logs/a.jsonl", SourceOffset: 42,
	}
	state := parser.FileState{Path: "/logs/a.jsonl", Tool: "claude", SizeBytes: 100, MtimeUnix: 1}
	require.NoError(t, st.CommitFileParse(state, []parser.Event{ev}))
	require.NoError(t, st.CommitFileParse(state, []parser.Event{ev}))

	var count int
	require.NoError(t, st.DB().QueryRow("SELECT COUNT(*) FROM usage_events").Scan(&count))
	assert.Equal(t, 1, count, "INSERT OR IGNORE must prevent duplicate")
}

func TestMetadata_FirstPassDone(t *testing.T) {
	st := newTestStore(t)
	done, err := st.IsFirstPassDone()
	require.NoError(t, err)
	assert.False(t, done)

	require.NoError(t, st.MarkFirstPassDone())
	done, err = st.IsFirstPassDone()
	require.NoError(t, err)
	assert.True(t, done)
}

func TestCommitFileParse_CodexStateFields(t *testing.T) {
	st := newTestStore(t)
	state := parser.FileState{
		Path: "/logs/rollout.jsonl", Tool: "codex",
		SizeBytes: 200, MtimeUnix: 1,
		LastTotalJSON: `{"input_tokens":100,"cached_input_tokens":10,"output_tokens":50,"reasoning_output_tokens":5}`,
		LastModel:     "gpt-5.2-codex",
	}
	require.NoError(t, st.CommitFileParse(state, nil))

	got, ok, err := st.GetFileState("/logs/rollout.jsonl")
	require.NoError(t, err)
	require.True(t, ok)
	assert.Equal(t, state.LastTotalJSON, got.LastTotalJSON)
	assert.Equal(t, "gpt-5.2-codex", got.LastModel)
}

func TestCommitFileParse_UpsertsSessionRow(t *testing.T) {
	st := newTestStore(t)

	ts1 := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	ts2 := time.Date(2026, 4, 22, 10, 5, 0, 0, time.UTC)
	events := []parser.Event{
		{TsUTC: ts1, Tool: "claude", Model: "m",
			InputTokens: 100, SourceFile: "/logs/a.jsonl", SourceOffset: 0},
		{TsUTC: ts2, Tool: "claude", Model: "m",
			InputTokens: 200, SourceFile: "/logs/a.jsonl", SourceOffset: 100},
	}
	state := parser.FileState{
		Path: "/logs/a.jsonl", Tool: "claude",
		SizeBytes: 500, MtimeUnix: 1,
		Cwd: "/Users/me/proj-a", GitBranch: "main",
	}
	require.NoError(t, st.CommitFileParse(state, events))

	var cwd, branch string
	var first, last int64
	require.NoError(t, st.DB().QueryRow(
		"SELECT cwd, git_branch, first_ts_utc, last_ts_utc FROM sessions WHERE source_file=?",
		"/logs/a.jsonl",
	).Scan(&cwd, &branch, &first, &last))
	assert.Equal(t, "/Users/me/proj-a", cwd)
	assert.Equal(t, "main", branch)
	assert.Equal(t, ts1.Unix(), first)
	assert.Equal(t, ts2.Unix(), last)
}

func TestCommitFileParse_SessionPreservesCwdWhenLaterScanIsEmpty(t *testing.T) {
	st := newTestStore(t)

	ts1 := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	first := parser.FileState{
		Path: "/logs/a.jsonl", Tool: "claude",
		SizeBytes: 100, MtimeUnix: 1,
		Cwd: "/Users/me/proj-a", GitBranch: "main",
	}
	require.NoError(t, st.CommitFileParse(first, []parser.Event{
		{TsUTC: ts1, Tool: "claude", Model: "m", InputTokens: 1,
			SourceFile: "/logs/a.jsonl", SourceOffset: 0},
	}))

	// A subsequent partial scan that didn't observe any meta line — empty
	// strings must NOT wipe what the previous scan recorded.
	require.NoError(t, st.CommitFileParse(parser.FileState{
		Path: "/logs/a.jsonl", Tool: "claude",
		SizeBytes: 200, MtimeUnix: 2,
	}, nil))

	var cwd, branch string
	require.NoError(t, st.DB().QueryRow(
		"SELECT cwd, git_branch FROM sessions WHERE source_file=?", "/logs/a.jsonl",
	).Scan(&cwd, &branch))
	assert.Equal(t, "/Users/me/proj-a", cwd)
	assert.Equal(t, "main", branch)
}

func TestCommitFileParse_SessionWidensTimeRange(t *testing.T) {
	st := newTestStore(t)

	mid := time.Date(2026, 4, 22, 10, 30, 0, 0, time.UTC)
	require.NoError(t, st.CommitFileParse(
		parser.FileState{Path: "/logs/a.jsonl", Tool: "claude",
			SizeBytes: 100, MtimeUnix: 1, Cwd: "/p"},
		[]parser.Event{{TsUTC: mid, Tool: "claude", Model: "m",
			InputTokens: 1, SourceFile: "/logs/a.jsonl", SourceOffset: 0}},
	))

	earlier := mid.Add(-time.Hour)
	later := mid.Add(time.Hour)
	require.NoError(t, st.CommitFileParse(
		parser.FileState{Path: "/logs/a.jsonl", Tool: "claude",
			SizeBytes: 200, MtimeUnix: 2, Cwd: "/p"},
		[]parser.Event{
			{TsUTC: earlier, Tool: "claude", Model: "m", InputTokens: 1,
				SourceFile: "/logs/a.jsonl", SourceOffset: 100},
			{TsUTC: later, Tool: "claude", Model: "m", InputTokens: 1,
				SourceFile: "/logs/a.jsonl", SourceOffset: 200},
		},
	))

	var first, last int64
	require.NoError(t, st.DB().QueryRow(
		"SELECT first_ts_utc, last_ts_utc FROM sessions WHERE source_file=?",
		"/logs/a.jsonl",
	).Scan(&first, &last))
	assert.Equal(t, earlier.Unix(), first)
	assert.Equal(t, later.Unix(), last)
}

func TestSumByModel_AndSessions(t *testing.T) {
	st := newTestStore(t)
	ts := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC).Unix()

	events := []parser.Event{
		{TsUTC: time.Unix(ts, 0).UTC(), Tool: "claude", Model: "m1",
			InputTokens: 100, OutputTokens: 50,
			SourceFile: "/f1", SourceOffset: 0},
		{TsUTC: time.Unix(ts+60, 0).UTC(), Tool: "claude", Model: "m1",
			InputTokens: 200, OutputTokens: 80,
			SourceFile: "/f2", SourceOffset: 0},
		{TsUTC: time.Unix(ts+120, 0).UTC(), Tool: "claude", Model: "m2",
			InputTokens: 300, OutputTokens: 100,
			SourceFile: "/f2", SourceOffset: 100},
	}
	require.NoError(t, st.CommitFileParse(parser.FileState{Path: "/f1", Tool: "claude", SizeBytes: 1, MtimeUnix: 1}, events[:1]))
	require.NoError(t, st.CommitFileParse(parser.FileState{Path: "/f2", Tool: "claude", SizeBytes: 1, MtimeUnix: 1}, events[1:]))

	sums, err := st.SumByModel("claude", ts-1, ts+200)
	require.NoError(t, err)
	require.Len(t, sums, 2)
	byModel := map[string]parser.Event{}
	_ = byModel

	sessions, err := st.DistinctSessions("claude", ts-1, ts+200)
	require.NoError(t, err)
	assert.Equal(t, 2, sessions)

	total, err := st.TotalInRange("claude", ts-1, ts+200)
	require.NoError(t, err)
	assert.Equal(t, int64(100+50+200+80+300+100), total)
}
