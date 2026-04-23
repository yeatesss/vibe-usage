// Package config parses CLI flags and environment to build a validated Config.
package config

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

type Config struct {
	DataDir           string
	Tick              time.Duration
	LogLevel          string
	ClaudeProjectsDir string
	CodexSessionsDir  string
}

// Load parses CLI args (typically os.Args[1:]) and returns validated Config.
// Precedence: flag > env (VIBEUSAGE_*) > default.
func Load(args []string) (*Config, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("resolve home dir: %w", err)
	}

	defaultDataDir := filepath.Join(home, "Library", "Application Support", "VibeUsage")
	defaultClaude := filepath.Join(home, ".claude", "projects")
	defaultCodex := filepath.Join(home, ".codex", "sessions")

	cfg := &Config{
		DataDir:           envOr("VIBEUSAGE_DATA_DIR", defaultDataDir),
		Tick:              30 * time.Second,
		LogLevel:          envOr("VIBEUSAGE_LOG_LEVEL", "info"),
		ClaudeProjectsDir: envOr("VIBEUSAGE_CLAUDE_DIR", defaultClaude),
		CodexSessionsDir:  envOr("VIBEUSAGE_CODEX_DIR", defaultCodex),
	}

	fs := flag.NewFlagSet("vibeusage-backend", flag.ContinueOnError)
	fs.StringVar(&cfg.DataDir, "data-dir", cfg.DataDir, "data directory (defaults to ~/Library/Application Support/VibeUsage)")
	fs.DurationVar(&cfg.Tick, "tick", cfg.Tick, "ingest poll interval (10s..10m)")
	fs.StringVar(&cfg.LogLevel, "log-level", cfg.LogLevel, "log level: debug|info|warn|error")
	fs.StringVar(&cfg.ClaudeProjectsDir, "claude-dir", cfg.ClaudeProjectsDir, "Claude projects directory")
	fs.StringVar(&cfg.CodexSessionsDir, "codex-dir", cfg.CodexSessionsDir, "Codex sessions directory")

	if err := fs.Parse(args); err != nil {
		return nil, err
	}

	if cfg.Tick < 10*time.Second || cfg.Tick > 10*time.Minute {
		return nil, fmt.Errorf("--tick must be between 10s and 10m; got %s", cfg.Tick)
	}
	switch cfg.LogLevel {
	case "debug", "info", "warn", "error":
	default:
		return nil, fmt.Errorf("--log-level must be debug|info|warn|error; got %q", cfg.LogLevel)
	}

	return cfg, nil
}

func envOr(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}
