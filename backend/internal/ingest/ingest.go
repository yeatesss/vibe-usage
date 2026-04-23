// Package ingest schedules parser runs and persists events via store.
package ingest

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"sync/atomic"
	"time"

	"github.com/yeatesss/vibe-usage/backend/internal/parser"
)

// Store is the narrow sink interface this package depends on (DIP).
type Store interface {
	GetFileState(path string) (parser.FileState, bool, error)
	CommitFileParse(state parser.FileState, events []parser.Event) error
	MarkFirstPassDone() error
	IsFirstPassDone() (bool, error)
}

type ScanStats struct {
	FilesScanned, FilesChanged, EventsInserted int
	DurationMs                                 int64
	FinishedAt                                 time.Time
}

type Service struct {
	store     Store
	parsers   []parser.ToolParser
	cfg       parser.Config
	tick      time.Duration
	log       *slog.Logger
	lastStats atomic.Pointer[ScanStats]
	done      chan struct{}
}

func New(s Store, parsers []parser.ToolParser, cfg parser.Config, tick time.Duration, log *slog.Logger) *Service {
	return &Service{
		store: s, parsers: parsers, cfg: cfg, tick: tick, log: log,
		done: make(chan struct{}),
	}
}

func (s *Service) Done() <-chan struct{} { return s.done }
func (s *Service) LastStats() *ScanStats { return s.lastStats.Load() }

// Run blocks until ctx is cancelled. Closes Done() on return.
func (s *Service) Run(ctx context.Context) error {
	defer close(s.done)

	s.scanOnce(ctx)
	if err := s.store.MarkFirstPassDone(); err != nil {
		s.log.Error("ingest.first_pass_mark_failed", "err", err)
	}

	t := time.NewTicker(s.tick)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-t.C:
			s.scanOnce(ctx)
		}
	}
}

func (s *Service) scanOnce(ctx context.Context) {
	start := time.Now()
	stats := ScanStats{}
	for _, p := range s.parsers {
		if ctx.Err() != nil {
			break
		}
		paths, err := p.Walk(s.cfg)
		if err != nil {
			s.log.Warn("ingest.walk.failed", "tool", p.Name(), "err", err)
			continue
		}
		for _, path := range paths {
			if ctx.Err() != nil {
				break
			}
			stats.FilesScanned++
			changed, inserted := s.processFile(p, path)
			if changed {
				stats.FilesChanged++
				stats.EventsInserted += inserted
			}
		}
	}
	stats.DurationMs = time.Since(start).Milliseconds()
	stats.FinishedAt = time.Now()
	s.lastStats.Store(&stats)
	s.log.Info("ingest.scan.done",
		"files_scanned", stats.FilesScanned,
		"files_changed", stats.FilesChanged,
		"events_inserted", stats.EventsInserted,
		"duration_ms", stats.DurationMs)
}

// processFile returns (changed, eventsInserted).
func (s *Service) processFile(p parser.ToolParser, path string) (bool, int) {
	st, err := os.Stat(path)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			s.log.Warn("ingest.stat.failed", "path", path, "err", err)
		}
		return false, 0
	}
	curSize := st.Size()
	curMtime := st.ModTime().Unix()

	saved, hasSaved, err := s.store.GetFileState(path)
	if err != nil {
		s.log.Error("ingest.get_state.failed", "path", path, "err", err)
		return false, 0
	}
	if hasSaved && curSize == saved.SizeBytes && curMtime == saved.MtimeUnix {
		return false, 0
	}

	start := saved
	if !hasSaved || curSize < saved.SizeBytes {
		start = parser.FileState{Path: path, Tool: p.Name()}
	}

	events, next, err := p.Parse(path, start)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			s.log.Warn("ingest.parse.failed", "path", path, "err", err)
		}
		return false, 0
	}

	if err := s.store.CommitFileParse(next, events); err != nil {
		s.log.Error("ingest.commit.failed", "path", path, "err", err)
		return false, 0
	}
	return true, len(events)
}
