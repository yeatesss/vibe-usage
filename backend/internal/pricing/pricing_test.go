package pricing

import (
	"testing"
	"time"

	"github.com/shopspring/decimal"
	"github.com/stretchr/testify/assert"
)

func mustDec(s string) decimal.Decimal { return decimal.RequireFromString(s) }

func TestResolver_LatestEffectiveFrom(t *testing.T) {
	profiles := []Profile{
		{Model: "claude-sonnet-4", Source: "claude",
			EffectiveFrom: time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC),
			Input:         mustDec("2.50")},
		{Model: "claude-sonnet-4", Source: "claude",
			EffectiveFrom: time.Date(2025, 5, 1, 0, 0, 0, 0, time.UTC),
			Input:         mustDec("3.00")},
	}
	r := NewMapResolver(profiles)
	got, ok := r.Lookup("claude", "claude-sonnet-4")
	assert.True(t, ok)
	assert.True(t, got.Input.Equal(mustDec("3.00")))
}

func TestResolver_NotFound(t *testing.T) {
	r := NewMapResolver(nil)
	_, ok := r.Lookup("claude", "bogus")
	assert.False(t, ok)
}

func TestCalculator_Compute(t *testing.T) {
	profile := Profile{
		Model: "claude-sonnet-4-6", Source: "claude",
		Input:           mustDec("3.00"),
		CachedInput:     mustDec("0.30"),
		CacheCreation:   mustDec("3.75"),
		Output:          mustDec("15.00"),
		ReasoningOutput: mustDec("15.00"),
	}
	r := NewMapResolver([]Profile{profile})
	c := New(r)
	tc := TokenCounts{Input: 1_000_000, Output: 1_000_000}
	got := c.Compute("claude", "claude-sonnet-4-6", tc)
	assert.True(t, got.Equal(mustDec("18.00")), "got %s", got.String())

	tc = TokenCounts{Input: 1_000_000, CacheRead: 1_000_000, CacheWrite: 1_000_000, Output: 1_000_000}
	got = c.Compute("claude", "claude-sonnet-4-6", tc)
	assert.True(t, got.Equal(mustDec("22.05")), "got %s", got.String())
}

func TestCalculator_UnknownModelReturnsZero(t *testing.T) {
	c := New(NewMapResolver(nil))
	got := c.Compute("claude", "bogus", TokenCounts{Input: 1_000_000})
	assert.True(t, got.IsZero())
}

func TestCalculator_Linear(t *testing.T) {
	profile := Profile{
		Model: "m", Source: "s",
		Input: mustDec("1.23"), Output: mustDec("4.56"),
	}
	c := New(NewMapResolver([]Profile{profile}))
	a := TokenCounts{Input: 123, Output: 456}
	b := TokenCounts{Input: 789, Output: 101112}
	sum := TokenCounts{Input: a.Input + b.Input, Output: a.Output + b.Output}
	left := c.Compute("s", "m", a).Add(c.Compute("s", "m", b))
	right := c.Compute("s", "m", sum)
	assert.True(t, left.Equal(right), "left=%s right=%s", left, right)
}
