package store

import (
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestOpen_CreatesSchemaAndSeedsPricing(t *testing.T) {
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "data.db")

	st, err := Open(dbPath)
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	// pricing_profiles seeded: 7 claude + 2 codex = 9
	var n int
	require.NoError(t, st.DB().QueryRow("SELECT COUNT(*) FROM pricing_profiles").Scan(&n))
	assert.Equal(t, 9, n)

	// schema tables present
	for _, tbl := range []string{"usage_events", "log_files", "pricing_profiles", "metadata"} {
		var name string
		err := st.DB().QueryRow("SELECT name FROM sqlite_master WHERE type='table' AND name=?", tbl).Scan(&name)
		require.NoError(t, err, "table %s missing", tbl)
		assert.Equal(t, tbl, name)
	}

	// user_version bumped
	var uv int
	require.NoError(t, st.DB().QueryRow("PRAGMA user_version").Scan(&uv))
	assert.Equal(t, 1, uv)
}

func TestOpen_Idempotent(t *testing.T) {
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "data.db")

	st, err := Open(dbPath)
	require.NoError(t, err)
	require.NoError(t, st.Close())

	// Re-open: no error, pricing rows unchanged (idempotent migration)
	st2, err := Open(dbPath)
	require.NoError(t, err)
	t.Cleanup(func() { _ = st2.Close() })

	var n int
	require.NoError(t, st2.DB().QueryRow("SELECT COUNT(*) FROM pricing_profiles").Scan(&n))
	assert.Equal(t, 9, n)
}
