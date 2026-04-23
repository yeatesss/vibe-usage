package parser

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestClaudeParse_Sample(t *testing.T) {
	p := NewClaudeParser()
	path := "testdata/claude/sample.jsonl"
	fi, err := os.Stat(path)
	require.NoError(t, err)

	events, next, err := p.Parse(path, FileState{Path: path, Tool: "claude"})
	require.NoError(t, err)
	require.Len(t, events, 2)

	assert.Equal(t, int64(100), events[0].InputTokens)
	assert.Equal(t, int64(50), events[0].OutputTokens)
	assert.Equal(t, int64(10), events[0].CacheReadTokens)
	assert.Equal(t, int64(5), events[0].CacheWriteTokens)
	assert.Equal(t, "claude-sonnet-4-6", events[0].Model) // normalized
	assert.Equal(t, int64(0), events[0].SourceOffset)    // first line starts at 0
	assert.Equal(t, path, events[0].SourceFile)
	assert.Equal(t, "claude", events[0].Tool)

	line1, _ := os.ReadFile(path)
	firstLineLen := int64(0)
	for i, b := range line1 {
		if b == '\n' {
			firstLineLen = int64(i + 1)
			break
		}
	}
	assert.Equal(t, firstLineLen, events[1].SourceOffset)

	assert.Equal(t, fi.Size(), next.SizeBytes)
	assert.Equal(t, fi.ModTime().Unix(), next.MtimeUnix)
}

func TestClaudeParse_Resume(t *testing.T) {
	p := NewClaudeParser()
	path := "testdata/claude/sample.jsonl"

	evA, stateA, err := p.Parse(path, FileState{Path: path, Tool: "claude"})
	require.NoError(t, err)
	require.Len(t, evA, 2)

	evB, stateB, err := p.Parse(path, stateA)
	require.NoError(t, err)
	assert.Empty(t, evB)
	assert.Equal(t, stateA.SizeBytes, stateB.SizeBytes)
}

func TestClaudeParse_IncompleteTail(t *testing.T) {
	p := NewClaudeParser()
	path := "testdata/claude/incomplete-tail.jsonl"

	events, next, err := p.Parse(path, FileState{Path: path, Tool: "claude"})
	require.NoError(t, err)
	require.Len(t, events, 2)

	raw, _ := os.ReadFile(path)
	seenNewlines := 0
	var cutoff int64
	for i, b := range raw {
		if b == '\n' {
			seenNewlines++
			if seenNewlines == 2 {
				cutoff = int64(i + 1)
				break
			}
		}
	}
	assert.Equal(t, cutoff, next.SizeBytes, "must stop at last complete \\n")
}

func TestClaudeParse_TailCompletesOnAppend(t *testing.T) {
	p := NewClaudeParser()

	src, err := os.ReadFile("testdata/claude/incomplete-tail.jsonl")
	require.NoError(t, err)
	path := filepath.Join(t.TempDir(), "tail.jsonl")
	require.NoError(t, os.WriteFile(path, src, 0o644))

	evA, stateA, err := p.Parse(path, FileState{Path: path, Tool: "claude"})
	require.NoError(t, err)
	require.Len(t, evA, 2)

	completion := `-20251201","usage":{"input_tokens":33,"output_tokens":11,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}` + "\n" +
		`{"timestamp":"2026-04-22T10:03:00Z","type":"assistant","message":{"model":"claude-sonnet-4-6-20251201","usage":{"input_tokens":44,"output_tokens":22,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}` + "\n"
	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0o644)
	require.NoError(t, err)
	_, err = f.WriteString(completion)
	require.NoError(t, err)
	require.NoError(t, f.Close())

	evB, _, err := p.Parse(path, stateA)
	require.NoError(t, err)
	require.Len(t, evB, 2)
	assert.Equal(t, int64(33), evB[0].InputTokens, "formerly-truncated line must be parsed now")
	assert.Equal(t, int64(44), evB[1].InputTokens)
	assert.Equal(t, stateA.SizeBytes, evB[0].SourceOffset)
}

func TestClaudeWalk(t *testing.T) {
	root := t.TempDir()
	p1 := filepath.Join(root, "proj1")
	p2 := filepath.Join(root, "proj2")
	require.NoError(t, os.MkdirAll(p1, 0o755))
	require.NoError(t, os.MkdirAll(p2, 0o755))
	for _, f := range []string{
		filepath.Join(p1, "a.jsonl"),
		filepath.Join(p1, "b.jsonl"),
		filepath.Join(p2, "c.jsonl"),
		filepath.Join(p2, "notes.md"),
	} {
		require.NoError(t, os.WriteFile(f, []byte{}, 0o644))
	}

	p := NewClaudeParser()
	paths, err := p.Walk(Config{ClaudeProjectsDir: root})
	require.NoError(t, err)
	assert.Len(t, paths, 3)
}
