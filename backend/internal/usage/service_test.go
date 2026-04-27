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

type fakeReader struct {
	sums     []store.ModelTokenSum
	sessions int
	totals   map[int64]int64

	// Per-project overrides; non-nil presence picks the *ForProject path.
	projectSums     map[string][]store.ModelTokenSum
	projectSessions map[string]int
	projectTotals   map[string]map[int64]int64
}

func (f *fakeReader) SumByModel(tool string, startUTC, endUTC int64) ([]store.ModelTokenSum, error) {
	return f.sums, nil
}
func (f *fakeReader) SumByModelForProject(tool, project string, startUTC, endUTC int64) ([]store.ModelTokenSum, error) {
	if f.projectSums != nil {
		return f.projectSums[project], nil
	}
	return nil, nil
}
func (f *fakeReader) TotalInRange(tool string, startUTC, endUTC int64) (int64, error) {
	return f.totals[startUTC], nil
}
func (f *fakeReader) TotalInRangeForProject(tool, project string, startUTC, endUTC int64) (int64, error) {
	if f.projectTotals != nil {
		return f.projectTotals[project][startUTC], nil
	}
	return 0, nil
}
func (f *fakeReader) DistinctSessions(tool string, startUTC, endUTC int64) (int, error) {
	return f.sessions, nil
}
func (f *fakeReader) DistinctSessionsForProject(tool, project string, startUTC, endUTC int64) (int, error) {
	if f.projectSessions != nil {
		return f.projectSessions[project], nil
	}
	return 0, nil
}

func TestService_Query_Today(t *testing.T) {
	now := time.Date(2026, 4, 22, 15, 30, 0, 0, sgt)
	clock := NewFixedClock(now)

	reader := &fakeReader{
		sums: []store.ModelTokenSum{
			{Model: "claude-sonnet-4-6", Input: 1_000_000, Output: 1_000_000, Requests: 5},
		},
		sessions: 2,
		totals:   map[int64]int64{},
	}
	profile := pricing.Profile{
		Model: "claude-sonnet-4-6", Source: "claude",
		Input:  decimal.RequireFromString("3.00"),
		Output: decimal.RequireFromString("15.00"),
	}
	calc := pricing.New(pricing.NewMapResolver([]pricing.Profile{profile}))
	svc := NewService(reader, calc, clock)

	res, err := svc.Query("claude", "today", "")
	require.NoError(t, err)
	assert.Equal(t, int64(1_000_000), res.Metrics.InputTokens)
	assert.Equal(t, "18.00", res.Metrics.CostUSD)
	assert.Equal(t, 2, res.Sessions)
	assert.Equal(t, 24, len(res.Series.Values))
	assert.Equal(t, 24, len(res.Series.Labels))
	assert.Equal(t, "Now", res.Series.Labels[23])
	assert.Equal(t, "", res.Project)
}

func TestService_Query_WithProjectFilter(t *testing.T) {
	now := time.Date(2026, 4, 22, 15, 30, 0, 0, sgt)
	clock := NewFixedClock(now)

	reader := &fakeReader{
		// Empty all-project sums to make sure they are NOT consulted.
		sums: nil,
		projectSums: map[string][]store.ModelTokenSum{
			"/Users/me/proj-a": {
				{Model: "claude-sonnet-4-6", Input: 500_000, Output: 500_000, Requests: 3},
			},
		},
		projectSessions: map[string]int{"/Users/me/proj-a": 1},
		projectTotals:   map[string]map[int64]int64{},
	}
	profile := pricing.Profile{
		Model: "claude-sonnet-4-6", Source: "claude",
		Input:  decimal.RequireFromString("3.00"),
		Output: decimal.RequireFromString("15.00"),
	}
	calc := pricing.New(pricing.NewMapResolver([]pricing.Profile{profile}))
	svc := NewService(reader, calc, clock)

	res, err := svc.Query("claude", "today", "/Users/me/proj-a")
	require.NoError(t, err)
	assert.Equal(t, int64(500_000), res.Metrics.InputTokens)
	assert.Equal(t, "9.00", res.Metrics.CostUSD)
	assert.Equal(t, 1, res.Sessions)
	assert.Equal(t, "/Users/me/proj-a", res.Project)
}

func TestService_Query_InvalidRange(t *testing.T) {
	svc := NewService(&fakeReader{}, pricing.New(pricing.NewMapResolver(nil)), NewFixedClock(time.Now()))
	_, err := svc.Query("claude", "bogus", "")
	assert.Error(t, err)
}
