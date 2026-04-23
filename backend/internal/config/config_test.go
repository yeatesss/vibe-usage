package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// clearEnv uses t.Setenv (auto-restored on test end) to force all
// VIBEUSAGE_* vars empty so tests are hermetic. envOr treats "" as unset.
func clearEnv(t *testing.T) {
	t.Helper()
	for _, k := range []string{"VIBEUSAGE_DATA_DIR", "VIBEUSAGE_LOG_LEVEL", "VIBEUSAGE_CLAUDE_DIR", "VIBEUSAGE_CODEX_DIR"} {
		t.Setenv(k, "")
	}
}

func TestLoad_Defaults(t *testing.T) {
	clearEnv(t)
	home, err := os.UserHomeDir()
	require.NoError(t, err)
	cfg, err := Load([]string{})
	require.NoError(t, err)
	assert.Equal(t, filepath.Join(home, "Library", "Application Support", "VibeUsage"), cfg.DataDir)
	assert.Equal(t, 30*time.Second, cfg.Tick)
	assert.Equal(t, "info", cfg.LogLevel)
	assert.Equal(t, filepath.Join(home, ".claude", "projects"), cfg.ClaudeProjectsDir)
	assert.Equal(t, filepath.Join(home, ".codex", "sessions"), cfg.CodexSessionsDir)
}

func TestLoad_FlagOverride(t *testing.T) {
	clearEnv(t)
	cfg, err := Load([]string{"--data-dir", "/tmp/foo", "--tick", "10s", "--log-level", "debug"})
	require.NoError(t, err)
	assert.Equal(t, "/tmp/foo", cfg.DataDir)
	assert.Equal(t, 10*time.Second, cfg.Tick)
	assert.Equal(t, "debug", cfg.LogLevel)
}

func TestLoad_TickBounds(t *testing.T) {
	clearEnv(t)
	_, err := Load([]string{"--tick", "1s"})
	assert.Error(t, err, "tick below 10s should fail")
	_, err = Load([]string{"--tick", "11m"})
	assert.Error(t, err, "tick above 10m should fail")
}
