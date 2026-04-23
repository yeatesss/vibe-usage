package ingest

import (
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/yeatesss/vibe-usage/backend/internal/parser"
	"github.com/yeatesss/vibe-usage/backend/internal/store"
)

func copyFile(t *testing.T, src, dst string) {
	t.Helper()
	raw, err := os.ReadFile(src)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(dst, raw, 0o644))
}

func TestService_ScanOnce_IngestClaude(t *testing.T) {
	tmp := t.TempDir()
	claudeDir := filepath.Join(tmp, ".claude", "projects", "demo")
	require.NoError(t, os.MkdirAll(claudeDir, 0o755))
	copyFile(t, "../../internal/parser/testdata/claude/sample.jsonl", filepath.Join(claudeDir, "a.jsonl"))

	st, err := store.Open(filepath.Join(tmp, "data.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	svc := New(st, parser.List(),
		parser.Config{ClaudeProjectsDir: filepath.Join(tmp, ".claude", "projects"),
			CodexSessionsDir: filepath.Join(tmp, ".codex", "sessions")},
		30*time.Second, logger)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	go svc.Run(ctx)
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		done, err := st.IsFirstPassDone()
		require.NoError(t, err)
		if done {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	cancel()
	<-svc.Done()

	var n int
	require.NoError(t, st.DB().QueryRow("SELECT COUNT(*) FROM usage_events WHERE tool='claude'").Scan(&n))
	assert.Equal(t, 2, n)

	stats := svc.LastStats()
	require.NotNil(t, stats)
	assert.GreaterOrEqual(t, stats.FilesScanned, 1)
}

func TestService_StatFastPath(t *testing.T) {
	tmp := t.TempDir()
	claudeDir := filepath.Join(tmp, ".claude", "projects", "demo")
	require.NoError(t, os.MkdirAll(claudeDir, 0o755))
	copyFile(t, "../../internal/parser/testdata/claude/sample.jsonl", filepath.Join(claudeDir, "a.jsonl"))

	st, err := store.Open(filepath.Join(tmp, "data.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	svc := New(st, parser.List(),
		parser.Config{ClaudeProjectsDir: filepath.Join(tmp, ".claude", "projects"),
			CodexSessionsDir: filepath.Join(tmp, ".codex", "sessions")},
		30*time.Second, logger)

	svc.scanOnce(context.Background())
	statsAfter1 := svc.LastStats()
	require.NotNil(t, statsAfter1)
	assert.Equal(t, 1, statsAfter1.FilesChanged, "first scan must mark file as changed")

	svc.scanOnce(context.Background())
	statsAfter2 := svc.LastStats()
	require.NotNil(t, statsAfter2)
	assert.Equal(t, 0, statsAfter2.FilesChanged, "second scan must use stat fast-path (FilesChanged=0)")
	assert.Equal(t, 1, statsAfter2.FilesScanned, "but file is still scanned (stat counts as scan)")

	var n int
	require.NoError(t, st.DB().QueryRow("SELECT COUNT(*) FROM usage_events").Scan(&n))
	assert.Equal(t, 2, n, "duplicate scan must not re-insert")
}
