package store

import (
	"database/sql"
	"errors"
	"fmt"

	"github.com/yeatesss/vibe-usage/backend/internal/parser"
)

func (s *Store) GetFileState(path string) (parser.FileState, bool, error) {
	const q = `SELECT path, tool, size_bytes, mtime_unix,
	                  COALESCE(last_total_json, ''), COALESCE(last_model, '')
	           FROM log_files WHERE path = ?`
	var fs parser.FileState
	err := s.db.QueryRow(q, path).Scan(&fs.Path, &fs.Tool, &fs.SizeBytes, &fs.MtimeUnix, &fs.LastTotalJSON, &fs.LastModel)
	if errors.Is(err, sql.ErrNoRows) {
		return parser.FileState{}, false, nil
	}
	if err != nil {
		return parser.FileState{}, false, fmt.Errorf("query log_files: %w", err)
	}
	return fs, true, nil
}
