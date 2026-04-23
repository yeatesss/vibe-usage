package parser

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type ClaudeParser struct{}

func NewClaudeParser() *ClaudeParser { return &ClaudeParser{} }

func (*ClaudeParser) Name() string { return "claude" }

func (*ClaudeParser) Walk(cfg Config) ([]string, error) {
	var out []string
	err := filepath.WalkDir(cfg.ClaudeProjectsDir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			if os.IsNotExist(err) {
				return nil
			}
			return err
		}
		if d.IsDir() {
			return nil
		}
		if strings.HasSuffix(d.Name(), ".jsonl") {
			out = append(out, p)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

type claudeLine struct {
	Timestamp string `json:"timestamp"`
	Message   struct {
		Model string `json:"model"`
		Usage *struct {
			InputTokens              int64 `json:"input_tokens"`
			OutputTokens             int64 `json:"output_tokens"`
			CacheReadInputTokens     int64 `json:"cache_read_input_tokens"`
			CacheCreationInputTokens int64 `json:"cache_creation_input_tokens"`
		} `json:"usage"`
	} `json:"message"`
}

var usageMarker = []byte(`"usage"`)

func (*ClaudeParser) Parse(path string, state FileState) ([]Event, FileState, error) {
	next := state
	next.Path = path
	next.Tool = "claude"

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

		if !bytes.Contains(line, usageMarker) {
			continue
		}
		var obj claudeLine
		if err := json.Unmarshal(line, &obj); err != nil {
			continue
		}
		if obj.Message.Usage == nil || obj.Timestamp == "" {
			continue
		}
		ts, err := time.Parse(time.RFC3339Nano, obj.Timestamp)
		if err != nil {
			continue
		}
		u := obj.Message.Usage
		if u.InputTokens == 0 && u.OutputTokens == 0 && u.CacheReadInputTokens == 0 && u.CacheCreationInputTokens == 0 {
			continue
		}
		events = append(events, Event{
			TsUTC:                 ts.UTC(),
			Tool:                  "claude",
			Model:                 NormalizeModel(obj.Message.Model),
			InputTokens:           u.InputTokens,
			OutputTokens:          u.OutputTokens,
			CacheReadTokens:       u.CacheReadInputTokens,
			CacheWriteTokens:      u.CacheCreationInputTokens,
			ReasoningOutputTokens: 0,
			SourceFile:            path,
			SourceOffset:          lineStart,
		})
	}

	next.SizeBytes = cur
	return events, next, nil
}
