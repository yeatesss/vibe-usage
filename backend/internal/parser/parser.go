// Package parser parses CLI usage logs into Event records.
// ToolParser is the extension point; add new tools by adding an implementation.
package parser

import "time"

// Event is one usage record extracted from a log line.
type Event struct {
	TsUTC                 time.Time
	Tool                  string
	Model                 string
	InputTokens           int64
	OutputTokens          int64
	CacheReadTokens       int64
	CacheWriteTokens      int64
	ReasoningOutputTokens int64
	SourceFile            string
	SourceOffset          int64 // byte offset of line start in SourceFile
}

// FileState is the parser's durable per-file state (serialized via log_files row).
// SizeBytes = one past the last consumed '\n' byte (may be < stat.Size()).
type FileState struct {
	Path          string
	Tool          string
	SizeBytes     int64
	MtimeUnix     int64
	LastTotalJSON string // Codex only; empty for Claude
	LastModel     string // Codex only
}

// ToolParser: see spec §5.1 for contract. Implementers MUST:
//   - Start reading at state.SizeBytes (which may be 0 when ingest has reset).
//   - Consume only lines ending in '\n'; never advance cur past an incomplete tail.
//   - Set next.SizeBytes to the byte offset immediately after the last consumed '\n'.
type ToolParser interface {
	Name() string
	Walk(cfg Config) ([]string, error)
	Parse(path string, state FileState) (events []Event, next FileState, err error)
}

type Config struct {
	ClaudeProjectsDir string
	CodexSessionsDir  string
}
