package store

import (
	"path/filepath"
	"testing"

	"github.com/shopspring/decimal"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLoadPricing(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "data.db")
	st, err := Open(dbPath)
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	rows, err := st.LoadPricing()
	require.NoError(t, err)
	assert.Len(t, rows, 9)

	var sonnet *PricingRow
	for i := range rows {
		if rows[i].Model == "claude-sonnet-4-6" && rows[i].Source == "claude" {
			sonnet = &rows[i]
			break
		}
	}
	require.NotNil(t, sonnet, "claude-sonnet-4-6 not found")
	assert.True(t, sonnet.Input.Equal(decimal.RequireFromString("3.00")))
	assert.True(t, sonnet.CachedInput.Equal(decimal.RequireFromString("0.30")))
	assert.True(t, sonnet.CacheCreation.Equal(decimal.RequireFromString("3.75")))
	assert.True(t, sonnet.Output.Equal(decimal.RequireFromString("15.00")))
	assert.True(t, sonnet.ReasoningOutput.Equal(decimal.RequireFromString("15.00")))
}
