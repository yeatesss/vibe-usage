package parser

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type CodexParser struct{}

func NewCodexParser() *CodexParser { return &CodexParser{} }

func (*CodexParser) Name() string { return "codex" }

func (*CodexParser) Walk(cfg Config) ([]string, error) {
	var out []string
	err := filepath.WalkDir(cfg.CodexSessionsDir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			if os.IsNotExist(err) {
				return nil
			}
			return err
		}
		if d.IsDir() {
			return nil
		}
		name := d.Name()
		if strings.HasPrefix(name, "rollout-") && strings.HasSuffix(name, ".jsonl") {
			out = append(out, p)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// codexUsage captures the four token fields used by both last_token_usage and total_token_usage.
type codexUsage struct {
	InputTokens           int64 `json:"input_tokens"`
	CachedInputTokens     int64 `json:"cached_input_tokens"`
	OutputTokens          int64 `json:"output_tokens"`
	ReasoningOutputTokens int64 `json:"reasoning_output_tokens"`
}

func (u codexUsage) isZero() bool {
	return u.InputTokens == 0 && u.CachedInputTokens == 0 &&
		u.OutputTokens == 0 && u.ReasoningOutputTokens == 0
}

func (u codexUsage) equals(v codexUsage) bool { return u == v }

func (u codexUsage) anyLessThan(v codexUsage) bool {
	return u.InputTokens < v.InputTokens ||
		u.CachedInputTokens < v.CachedInputTokens ||
		u.OutputTokens < v.OutputTokens ||
		u.ReasoningOutputTokens < v.ReasoningOutputTokens
}

func (u codexUsage) sub(v codexUsage) codexUsage {
	return codexUsage{
		InputTokens:           u.InputTokens - v.InputTokens,
		CachedInputTokens:     u.CachedInputTokens - v.CachedInputTokens,
		OutputTokens:          u.OutputTokens - v.OutputTokens,
		ReasoningOutputTokens: u.ReasoningOutputTokens - v.ReasoningOutputTokens,
	}
}

func pickDelta(total, prev codexUsage, hasPrev bool) (codexUsage, bool) {
	if hasPrev && total.equals(prev) {
		return codexUsage{}, false
	}
	if !hasPrev {
		return total, true
	}
	if total.anyLessThan(prev) {
		return total, true
	}
	return total.sub(prev), true
}

type codexEnvelope struct {
	Type      string          `json:"type"`
	Timestamp string          `json:"timestamp"`
	Payload   json.RawMessage `json:"payload"`
}

type codexMetaPayload struct {
	Model string `json:"model"`
}

// codexTokenCountInfo holds the per-turn / cumulative token usage.
// Two carrier shapes exist in the wild:
//   - legacy: payload.token_count.{last,total}_token_usage
//   - current: payload.type=="token_count" with payload.info.{last,total}_token_usage
type codexTokenCountInfo struct {
	LastTokenUsage  *codexUsage     `json:"last_token_usage"`
	TotalTokenUsage json.RawMessage `json:"total_token_usage"`
}

type codexTokenCountPayload struct {
	Type       string               `json:"type"`
	TokenCount *codexTokenCountInfo `json:"token_count"`
	Info       *codexTokenCountInfo `json:"info"`
}

var (
	tokenCountMarker = []byte(`"token_count"`)
	turnCtxMarker    = []byte(`"turn_context"`)
	sessionMetaMark  = []byte(`"session_meta"`)
	modelMarker      = []byte(`"model"`)
)

func (*CodexParser) Parse(path string, state FileState) ([]Event, FileState, error) {
	next := state
	next.Path = path
	next.Tool = "codex"

	f, err := os.Open(path)
	if err != nil {
		return nil, next, err
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil {
		return nil, next, err
	}
	next.MtimeUnix = stat.ModTime().Unix()

	if _, err := f.Seek(state.SizeBytes, io.SeekStart); err != nil {
		return nil, next, err
	}

	rd := bufio.NewReaderSize(f, 1<<20)
	cur := state.SizeBytes

	currentModel := state.LastModel
	var prevTotal codexUsage
	var hasPrev bool
	if state.LastTotalJSON != "" {
		if err := json.Unmarshal([]byte(state.LastTotalJSON), &prevTotal); err == nil {
			hasPrev = true
		}
	}

	var events []Event
	for {
		line, err := rd.ReadBytes('\n')
		if len(line) > 0 && !bytes.HasSuffix(line, []byte{'\n'}) {
			break
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return events, next, err
		}
		lineStart := cur
		cur += int64(len(line))

		hasTC := bytes.Contains(line, tokenCountMarker)
		hasMeta := (bytes.Contains(line, turnCtxMarker) || bytes.Contains(line, sessionMetaMark)) && bytes.Contains(line, modelMarker)
		if !hasTC && !hasMeta {
			continue
		}

		var env codexEnvelope
		if err := json.Unmarshal(line, &env); err != nil {
			continue
		}

		if env.Type == "turn_context" || env.Type == "session_meta" {
			var mp codexMetaPayload
			if err := json.Unmarshal(env.Payload, &mp); err == nil && mp.Model != "" {
				currentModel = NormalizeModel(mp.Model)
			}
			continue
		}

		if !hasTC {
			continue
		}

		var tcp codexTokenCountPayload
		if err := json.Unmarshal(env.Payload, &tcp); err != nil {
			continue
		}

		// Pick whichever carrier this line uses; current Codex CLI emits
		// payload.info, older logs emit payload.token_count.
		var info *codexTokenCountInfo
		if tcp.Info != nil {
			info = tcp.Info
		} else if tcp.TokenCount != nil {
			info = tcp.TokenCount
		}
		if info == nil {
			continue
		}

		var delta codexUsage
		var ok bool
		if info.LastTokenUsage != nil {
			delta = *info.LastTokenUsage
			ok = !delta.isZero()
		} else if len(info.TotalTokenUsage) > 0 {
			var total codexUsage
			if err := json.Unmarshal(info.TotalTokenUsage, &total); err != nil {
				continue
			}
			delta, ok = pickDelta(total, prevTotal, hasPrev)
		}

		if len(info.TotalTokenUsage) > 0 {
			var total codexUsage
			if err := json.Unmarshal(info.TotalTokenUsage, &total); err == nil {
				prevTotal = total
				hasPrev = true
			}
		}

		if !ok || delta.isZero() {
			continue
		}

		if env.Timestamp == "" {
			continue
		}
		ts, err := time.Parse(time.RFC3339Nano, env.Timestamp)
		if err != nil {
			continue
		}

		if currentModel == "" {
			slog.Warn("codex.parse.token_count_without_model",
				"path", path, "offset", lineStart)
			continue
		}

		events = append(events, Event{
			TsUTC:                 ts.UTC(),
			Tool:                  "codex",
			Model:                 currentModel,
			InputTokens:           delta.InputTokens,
			OutputTokens:          delta.OutputTokens,
			CacheReadTokens:       delta.CachedInputTokens,
			CacheWriteTokens:      0,
			ReasoningOutputTokens: delta.ReasoningOutputTokens,
			SourceFile:            path,
			SourceOffset:          lineStart,
		})
	}

	next.SizeBytes = cur
	next.LastModel = currentModel
	if hasPrev {
		b, _ := json.Marshal(prevTotal)
		next.LastTotalJSON = string(b)
	}
	return events, next, nil
}
