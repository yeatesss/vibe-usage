package parser

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCodexParse_Sample(t *testing.T) {
	p := NewCodexParser()
	path := "testdata/codex/rollout.jsonl"
	events, _, err := p.Parse(path, FileState{Path: path, Tool: "codex"})
	require.NoError(t, err)
	require.Len(t, events, 4)

	assert.Equal(t, int64(100), events[0].InputTokens)
	assert.Equal(t, int64(10), events[0].CacheReadTokens)
	assert.Equal(t, int64(50), events[0].OutputTokens)
	assert.Equal(t, int64(5), events[0].ReasoningOutputTokens)
	assert.Equal(t, int64(0), events[0].CacheWriteTokens)
	assert.Equal(t, "gpt-5.2-codex", events[0].Model)
	assert.Equal(t, "codex", events[0].Tool)

	assert.Equal(t, int64(100), events[1].InputTokens)

	assert.Equal(t, int64(200), events[2].InputTokens)
	assert.Equal(t, int64(20), events[2].CacheReadTokens)
	assert.Equal(t, int64(100), events[2].OutputTokens)

	assert.Equal(t, "gpt-5.4-codex", events[3].Model)
	assert.Equal(t, int64(50), events[3].InputTokens)
}

func TestCodexParse_NoModelPrefix(t *testing.T) {
	p := NewCodexParser()
	path := "testdata/codex/rollout-no-model-prefix.jsonl"
	events, _, err := p.Parse(path, FileState{Path: path, Tool: "codex"})
	require.NoError(t, err)
	require.Len(t, events, 1)
	assert.Equal(t, "gpt-5.2-codex", events[0].Model)
}

func TestCodexParse_Truncated(t *testing.T) {
	p := NewCodexParser()
	path := "testdata/codex/rollout-truncated.jsonl"
	events, next, err := p.Parse(path, FileState{Path: path, Tool: "codex"})
	require.NoError(t, err)
	require.Len(t, events, 1)

	raw, _ := os.ReadFile(path)
	var cutoff int64
	seen := 0
	for i, b := range raw {
		if b == '\n' {
			seen++
			if seen == 2 {
				cutoff = int64(i + 1)
				break
			}
		}
	}
	assert.Equal(t, cutoff, next.SizeBytes)
	assert.NotEmpty(t, next.LastModel, "last_model must be persisted")
}

func TestCodexParse_InfoShape(t *testing.T) {
	p := NewCodexParser()
	path := "testdata/codex/rollout-info-shape.jsonl"
	events, _, err := p.Parse(path, FileState{Path: path, Tool: "codex"})
	require.NoError(t, err)
	require.Len(t, events, 2)

	assert.Equal(t, int64(100), events[0].InputTokens)
	assert.Equal(t, int64(10), events[0].CacheReadTokens)
	assert.Equal(t, int64(50), events[0].OutputTokens)
	assert.Equal(t, int64(5), events[0].ReasoningOutputTokens)
	assert.Equal(t, "gpt-5.4-codex", events[0].Model)

	assert.Equal(t, int64(200), events[1].InputTokens)
	assert.Equal(t, int64(30), events[1].CacheReadTokens)
	assert.Equal(t, int64(100), events[1].OutputTokens)
	assert.Equal(t, int64(10), events[1].ReasoningOutputTokens)
}

func TestCodexParse_Resume(t *testing.T) {
	p := NewCodexParser()
	path := "testdata/codex/rollout.jsonl"
	evA, stateA, err := p.Parse(path, FileState{Path: path, Tool: "codex"})
	require.NoError(t, err)
	require.Len(t, evA, 4)

	evB, _, err := p.Parse(path, stateA)
	require.NoError(t, err)
	assert.Empty(t, evB)
}
