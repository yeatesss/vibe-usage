package usage

import (
	"testing"
	"time"

	"github.com/shopspring/decimal"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/yeatesss/vibe-usage/backend/internal/pricing"
	"github.com/yeatesss/vibe-usage/backend/internal/store"
)

type fakeHeatReader struct {
	captured struct{ tool string; dayZeroUTC, endUTC int64 }
	rows     []store.DailyModelSum
}

func (f *fakeHeatReader) SumPerDayByModel(tool string, dayZeroUTC, endUTC int64) ([]store.DailyModelSum, error) {
	f.captured.tool = tool
	f.captured.dayZeroUTC = dayZeroUTC
	f.captured.endUTC = endUTC
	return f.rows, nil
}

func TestHeatmap_Shape_And_Boundaries(t *testing.T) {
	// Wed 2026-04-22 15:30 SGT → current-week Monday is 2026-04-20;
	// with weeks=4 the grid starts Monday 2026-03-30 and ends Sunday 2026-04-26.
	now := time.Date(2026, 4, 22, 15, 30, 0, 0, sgt)
	reader := &fakeHeatReader{
		rows: []store.DailyModelSum{
			{DayIndex: 0, Model: "claude-sonnet-4-6", Input: 500_000, Output: 500_000, Requests: 2},  // 2026-03-30
			{DayIndex: 23, Model: "claude-sonnet-4-6", Input: 1_000_000, Output: 1_000_000, Requests: 5}, // 2026-04-22 (today)
		},
	}
	calc := pricing.New(pricing.NewMapResolver([]pricing.Profile{{
		Model: "claude-sonnet-4-6", Source: "claude",
		Input:  decimal.RequireFromString("3.00"),
		Output: decimal.RequireFromString("15.00"),
	}}))
	svc := NewHeatmapService(reader, calc, NewFixedClock(now))

	res, err := svc.Query("claude", 4)
	require.NoError(t, err)
	assert.Equal(t, 4, res.Weeks)
	assert.Equal(t, 28, len(res.Days))
	assert.Equal(t, "2026-03-30", res.StartDate)
	assert.Equal(t, "2026-04-26", res.EndDate)
	assert.Equal(t, "2026-04-22", res.Today)

	assert.Equal(t, "2026-03-30", res.Days[0].Date)
	assert.Equal(t, 0, res.Days[0].Weekday) // Monday
	assert.Equal(t, int64(1_000_000), res.Days[0].TotalTokens)
	assert.Equal(t, int64(2), res.Days[0].Requests)
	// 500k input @ $3 + 500k output @ $15 = $1.50 + $7.50 = $9.00
	assert.Equal(t, "9.0000", res.Days[0].CostUSD)
	assert.False(t, res.Days[0].IsFuture)

	assert.Equal(t, "2026-04-22", res.Days[23].Date)
	assert.Equal(t, int64(2_000_000), res.Days[23].TotalTokens)
	assert.Equal(t, "18.0000", res.Days[23].CostUSD)

	// Thu-Sun after today should be marked future with zero metrics.
	for i := 24; i < 28; i++ {
		assert.True(t, res.Days[i].IsFuture, "day %d should be future", i)
		assert.Equal(t, int64(0), res.Days[i].TotalTokens)
	}

	// Reader should have been called with a SGT-midnight-aligned day-zero UTC.
	dayZero := time.Unix(reader.captured.dayZeroUTC, 0).In(sgLocation)
	assert.Equal(t, time.Date(2026, 3, 30, 0, 0, 0, 0, sgLocation), dayZero)
}

func TestHeatmap_ClampWeeks(t *testing.T) {
	assert.Equal(t, defaultHeatmapWeeks, ClampHeatmapWeeks(0))
	assert.Equal(t, minHeatmapWeeks, ClampHeatmapWeeks(1))
	assert.Equal(t, maxHeatmapWeeks, ClampHeatmapWeeks(999))
	assert.Equal(t, 20, ClampHeatmapWeeks(20))
}
