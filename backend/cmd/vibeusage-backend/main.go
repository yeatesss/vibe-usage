package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"gopkg.in/natefinch/lumberjack.v2"

	"github.com/yeatesss/vibe-usage/backend/internal/config"
	"github.com/yeatesss/vibe-usage/backend/internal/httpapi"
	"github.com/yeatesss/vibe-usage/backend/internal/ingest"
	"github.com/yeatesss/vibe-usage/backend/internal/parser"
	"github.com/yeatesss/vibe-usage/backend/internal/pricing"
	"github.com/yeatesss/vibe-usage/backend/internal/store"
	"github.com/yeatesss/vibe-usage/backend/internal/usage"
)

var version = "0.1.0-dev"

func main() {
	os.Exit(run())
}

func run() int {
	for _, a := range os.Args[1:] {
		if a == "--version" || a == "-version" {
			fmt.Println(version)
			return 0
		}
	}
	cfg, err := config.Load(os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		return 1
	}

	if err := os.MkdirAll(filepath.Join(cfg.DataDir, "logs"), 0o700); err != nil {
		fmt.Fprintln(os.Stderr, "mkdir data dir:", err)
		return 2
	}

	logger := newLogger(cfg)
	slog.SetDefault(logger)
	logger.Info("vibeusage-backend.start", "version", version, "data_dir", cfg.DataDir)

	lockPath := filepath.Join(cfg.DataDir, "backend.lock")
	lock, locked, err := acquireLock(lockPath)
	if err != nil {
		logger.Error("lock.open", "err", err)
		return 1
	}
	if !locked {
		if info, ok := ReadRuntimeJSON(filepath.Join(cfg.DataDir, "runtime.json")); ok && IsProcessAlive(info.PID) {
			logger.Info("lock.single_instance.reuse", "pid", info.PID, "port", info.Port)
			return 0
		}
		logger.Warn("lock.held_but_owner_dead", "lock_path", lockPath)
		return 0
	}
	defer unlock(lock)

	st, err := store.Open(filepath.Join(cfg.DataDir, "data.db"))
	if err != nil {
		logger.Error("store.open", "err", err)
		return 2
	}
	defer st.Close()

	pricingRows, err := st.LoadPricing()
	if err != nil {
		logger.Error("pricing.load", "err", err)
		return 1
	}
	profiles := make([]pricing.Profile, 0, len(pricingRows))
	for _, r := range pricingRows {
		profiles = append(profiles, pricing.Profile{
			Model: r.Model, Source: r.Source, EffectiveFrom: r.EffectiveFrom,
			Input: r.Input, CachedInput: r.CachedInput, CacheCreation: r.CacheCreation,
			Output: r.Output, ReasoningOutput: r.ReasoningOutput,
		})
	}
	calc := pricing.New(pricing.NewMapResolver(profiles))

	ing := ingest.New(st, parser.List(),
		parser.Config{ClaudeProjectsDir: cfg.ClaudeProjectsDir, CodexSessionsDir: cfg.CodexSessionsDir},
		cfg.Tick, logger)

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	go func() {
		if err := ing.Run(ctx); err != nil && err != context.Canceled {
			logger.Error("ingest.run", "err", err)
		}
	}()

	clock := usage.NewWallClock()
	usgSvc := usage.NewService(st, calc, clock)
	heatSvc := usage.NewHeatmapService(st, calc, clock)
	startedAt := time.Now().In(usage.Location())
	hc := &healthCheck{startedAt: startedAt, store: st, ingest: ing}

	router := httpapi.NewRouter(usgSvc, heatSvc, hc, ing, version)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		logger.Error("listen", "err", err)
		return 1
	}
	port := ln.Addr().(*net.TCPAddr).Port
	logger.Info("http.listen", "port", port)

	runtimePath := filepath.Join(cfg.DataDir, "runtime.json")
	if err := WriteRuntimeJSON(runtimePath, RuntimeInfo{
		Port: port, PID: os.Getpid(),
		StartedAt: startedAt.Format("2006-01-02T15:04:05-07:00"),
		Version:   version, DataDir: cfg.DataDir,
	}); err != nil {
		logger.Error("runtime.write", "err", err)
		return 1
	}
	defer os.Remove(runtimePath)

	srv := httpapi.NewServer(router)
	go func() {
		if err := srv.Serve(ln); err != nil && err != http.ErrServerClosed {
			logger.Error("http.serve", "err", err)
		}
	}()

	<-ctx.Done()
	logger.Info("shutdown.signal_received")

	if err := httpapi.ShutdownWithTimeout(srv, 5*time.Second); err != nil {
		logger.Error("http.shutdown", "err", err)
	}

	<-ing.Done()

	logger.Info("shutdown.done")
	return 0
}

func newLogger(cfg *config.Config) *slog.Logger {
	level := slog.LevelInfo
	switch cfg.LogLevel {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	}
	lj := &lumberjack.Logger{
		Filename: filepath.Join(cfg.DataDir, "logs", "backend.log"),
		MaxSize:  10, MaxBackups: 7, MaxAge: 7, Compress: true,
	}
	return slog.New(slog.NewJSONHandler(lj, &slog.HandlerOptions{Level: level}))
}

type healthCheck struct {
	startedAt time.Time
	store     *store.Store
	ingest    *ingest.Service
}

func (h *healthCheck) StartedAt() time.Time { return h.startedAt }

func (h *healthCheck) IsFirstPassDone() bool {
	done, err := h.store.IsFirstPassDone()
	if err != nil {
		return false
	}
	return done
}

func (h *healthCheck) LastIngestStats() map[string]any {
	stats := h.ingest.LastStats()
	if stats == nil {
		return map[string]any{}
	}
	return map[string]any{
		"files_scanned":   stats.FilesScanned,
		"files_changed":   stats.FilesChanged,
		"events_inserted": stats.EventsInserted,
		"duration_ms":     stats.DurationMs,
		"finished_at":     stats.FinishedAt.Format("2006-01-02T15:04:05-07:00"),
	}
}
