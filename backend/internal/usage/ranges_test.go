package usage

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var sgt, _ = time.LoadLocation("Asia/Singapore")

func TestRangeBoundaries_Today(t *testing.T) {
	now := time.Date(2026, 4, 22, 15, 30, 0, 0, sgt)
	rb, err := BoundariesFor("today", NewFixedClock(now))
	require.NoError(t, err)
	assert.Equal(t, time.Date(2026, 4, 22, 0, 0, 0, 0, sgt), rb.Start)
	assert.Equal(t, now, rb.End)
	assert.Equal(t, BucketHour, rb.Bucket)
	assert.Equal(t, 24, rb.BucketCount)
}

func TestRangeBoundaries_Week(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, sgt)
	rb, err := BoundariesFor("week", NewFixedClock(now))
	require.NoError(t, err)
	assert.Equal(t, time.Date(2026, 4, 20, 0, 0, 0, 0, sgt), rb.Start)
	assert.Equal(t, BucketDay, rb.Bucket)
	assert.Equal(t, 7, rb.BucketCount)
}

func TestRangeBoundaries_WeekSunday(t *testing.T) {
	now := time.Date(2026, 4, 26, 10, 0, 0, 0, sgt)
	rb, err := BoundariesFor("week", NewFixedClock(now))
	require.NoError(t, err)
	assert.Equal(t, time.Date(2026, 4, 20, 0, 0, 0, 0, sgt), rb.Start)
}

func TestRangeBoundaries_Month(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, sgt)
	rb, err := BoundariesFor("month", NewFixedClock(now))
	require.NoError(t, err)
	assert.Equal(t, time.Date(2026, 4, 1, 0, 0, 0, 0, sgt), rb.Start)
	assert.Equal(t, 30, rb.BucketCount)
}

func TestRangeBoundaries_Year(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, sgt)
	rb, err := BoundariesFor("year", NewFixedClock(now))
	require.NoError(t, err)
	assert.Equal(t, time.Date(2026, 1, 1, 0, 0, 0, 0, sgt), rb.Start)
	assert.Equal(t, BucketMonth, rb.Bucket)
	assert.Equal(t, 12, rb.BucketCount)
}

func TestRangeBoundaries_Invalid(t *testing.T) {
	_, err := BoundariesFor("bogus", NewFixedClock(time.Now()))
	assert.Error(t, err)
}
