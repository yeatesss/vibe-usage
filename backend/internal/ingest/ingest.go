// Package ingest schedules parser runs and persists events via store.
package ingest

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"sync/atomic"
	"time"

	"github.com/yeatesss/vibe-usage/backend/internal/parser"
)

// MinTick / MaxTick bound the scan interval. Same range the CLI flag enforces.
const (
	MinTick = 10 * time.Second
	MaxTick = 10 * time.Minute
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
	tickNs    atomic.Int64  // current tick duration in nanoseconds; safe to read/write across goroutines.
	tickReset chan struct{} // signal Run() to rebuild its ticker with the new value.
	log       *slog.Logger
	lastStats atomic.Pointer[ScanStats]
	done      chan struct{}
}

func New(s Store, parsers []parser.ToolParser, cfg parser.Config, tick time.Duration, log *slog.Logger) *Service {
	svc := &Service{
		store:     s,
		parsers:   parsers,
		cfg:       cfg,
		log:       log,
		done:      make(chan struct{}),
		tickReset: make(chan struct{}, 1),
	}
	svc.tickNs.Store(int64(tick))
	return svc
}

func (s *Service) Done() <-chan struct{} { return s.done }
func (s *Service) LastStats() *ScanStats { return s.lastStats.Load() }

// Tick returns the current scan interval.
func (s *Service) Tick() time.Duration {
	return time.Duration(s.tickNs.Load())
}

// SetTick updates the scan interval. The change takes effect on the next
// ticker rebuild, which is signalled non-blockingly via tickReset. Returns
// an error for out-of-range values.
func (s *Service) SetTick(d time.Duration) error {
	if d < MinTick || d > MaxTick {
		return fmt.Errorf("tick must be between %s and %s; got %s", MinTick, MaxTick, d)
	}
	old := time.Duration(s.tickNs.Swap(int64(d)))
	if old == d {
		return nil
	}
	// Non-blocking signal — buffered cap 1 means we coalesce rapid changes.
	select {
	case s.tickReset <- struct{}{}:
	default:
	}
	s.log.Info("ingest.tick.updated", "old", old.String(), "new", d.String())
	return nil
}

// Run blocks until ctx is cancelled. Closes Done() on return.
func (s *Service) Run(ctx context.Context) error {
	defer close(s.done)

	s.scanOnce(ctx)
	if err := s.store.MarkFirstPassDone(); err != nil {
		s.log.Error("ingest.first_pass_mark_failed", "err", err)
	}

	for ctx.Err() == nil {
		d := time.Duration(s.tickNs.Load())
		t := time.NewTicker(d)

	loop:
		for {
			select {
			case <-ctx.Done():
				t.Stop()
				return ctx.Err()
			case <-s.tickReset:
				t.Stop()
				break loop // rebuild ticker with the new tick value
			case <-t.C:
				s.scanOnce(ctx)
			}
		}
	}
	return ctx.Err()
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
