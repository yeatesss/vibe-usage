package test

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/yeatesss/vibe-usage/backend/internal/httpapi"
	"github.com/yeatesss/vibe-usage/backend/internal/ingest"
	"github.com/yeatesss/vibe-usage/backend/internal/parser"
	"github.com/yeatesss/vibe-usage/backend/internal/pricing"
	"github.com/yeatesss/vibe-usage/backend/internal/store"
	"github.com/yeatesss/vibe-usage/backend/internal/usage"
)

func copyFile(t *testing.T, src, dst string) {
	t.Helper()
	raw, err := os.ReadFile(src)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(dst, raw, 0o644))
}

type stubHealth struct{ store *store.Store }

func (s *stubHealth) StartedAt() time.Time            { return time.Now() }
func (s *stubHealth) IsFirstPassDone() bool           { d, _ := s.store.IsFirstPassDone(); return d }
func (s *stubHealth) LastIngestStats() map[string]any { return map[string]any{} }

func TestEndToEnd_ClaudeLogToUsageAPI(t *testing.T) {
	tmp := t.TempDir()
	claudeDir := filepath.Join(tmp, ".claude", "projects", "demo")
	codexDir := filepath.Join(tmp, ".codex", "sessions")
	require.NoError(t, os.MkdirAll(claudeDir, 0o755))
	require.NoError(t, os.MkdirAll(codexDir, 0o755))
	copyFile(t, "../internal/parser/testdata/claude/sample.jsonl", filepath.Join(claudeDir, "a.jsonl"))

	st, err := store.Open(filepath.Join(tmp, "data.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	rows, err := st.LoadPricing()
	require.NoError(t, err)
	profiles := make([]pricing.Profile, 0, len(rows))
	for _, r := range rows {
		profiles = append(profiles, pricing.Profile{
			Model: r.Model, Source: r.Source, EffectiveFrom: r.EffectiveFrom,
			Input: r.Input, CachedInput: r.CachedInput, CacheCreation: r.CacheCreation,
			Output: r.Output, ReasoningOutput: r.ReasoningOutput,
		})
	}
	calc := pricing.New(pricing.NewMapResolver(profiles))

	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	ing := ingest.New(st, parser.List(),
		parser.Config{ClaudeProjectsDir: filepath.Join(tmp, ".claude", "projects"),
			CodexSessionsDir: codexDir},
		30*time.Second, logger)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	go ing.Run(ctx)
	for i := 0; i < 100; i++ {
		if d, _ := st.IsFirstPassDone(); d {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	cancel()
	<-ing.Done()

	usgSvc := usage.NewService(st, calc, usage.NewFixedClock(time.Date(2026, 4, 22, 15, 30, 0, 0, usage.Location())))
	router := httpapi.NewRouter(usgSvc, &stubHealth{store: st}, "e2e")

	ts := httptest.NewServer(router)
	t.Cleanup(ts.Close)

	resp, err := http.Get(ts.URL + "/usage?tool=claude&range=today")
	require.NoError(t, err)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode)

	var res usage.QueryResult
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&res))

	assert.Equal(t, "claude", res.Tool)
	assert.Equal(t, "today", res.Range)
	assert.Equal(t, int64(300), res.Metrics.InputTokens)
	assert.Equal(t, int64(130), res.Metrics.OutputTokens)
	assert.Equal(t, 1, res.Sessions)
	assert.NotEmpty(t, res.Metrics.CostUSD)
	assert.Len(t, res.Series.Values, 24)
	assert.Len(t, res.Series.Labels, 24)
}
