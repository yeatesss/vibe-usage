// Package pricing does decimal-precise cost calculation.
// Resolver provides (source,model) → Profile lookup; Calculator is pure arithmetic.
package pricing

import (
	"time"

	"github.com/shopspring/decimal"
)

type Profile struct {
	Model, Source   string
	EffectiveFrom   time.Time
	Input           decimal.Decimal
	CachedInput     decimal.Decimal
	CacheCreation   decimal.Decimal
	Output          decimal.Decimal
	ReasoningOutput decimal.Decimal
}

type Resolver interface {
	Lookup(source, model string) (Profile, bool)
}

type TokenCounts struct {
	Input, Output, CacheRead, CacheWrite, ReasoningOutput int64
}

// MapResolver keeps one Profile per (source, model), selecting MAX(effective_from).
// Construct once at startup with all rows loaded from sqlite.
type MapResolver struct {
	m map[string]Profile
}

func NewMapResolver(rows []Profile) *MapResolver {
	m := make(map[string]Profile, len(rows))
	for _, p := range rows {
		key := p.Source + "|" + p.Model
		if existing, ok := m[key]; !ok || p.EffectiveFrom.After(existing.EffectiveFrom) {
			m[key] = p
		}
	}
	return &MapResolver{m: m}
}

func (r *MapResolver) Lookup(source, model string) (Profile, bool) {
	p, ok := r.m[source+"|"+model]
	return p, ok
}

type Calculator struct{ resolver Resolver }

func New(r Resolver) *Calculator { return &Calculator{resolver: r} }

var million = decimal.NewFromInt(1_000_000)

// Compute returns full-precision cost (NOT rounded). Caller rounds at API boundary.
// Unknown model → decimal.Zero (degradation; caller may log).
func (c *Calculator) Compute(source, model string, tc TokenCounts) decimal.Decimal {
	p, ok := c.resolver.Lookup(source, model)
	if !ok {
		return decimal.Zero
	}
	sum := decimal.Zero
	sum = sum.Add(decimal.NewFromInt(tc.Input).Mul(p.Input))
	sum = sum.Add(decimal.NewFromInt(tc.CacheRead).Mul(p.CachedInput))
	sum = sum.Add(decimal.NewFromInt(tc.CacheWrite).Mul(p.CacheCreation))
	sum = sum.Add(decimal.NewFromInt(tc.Output).Mul(p.Output))
	sum = sum.Add(decimal.NewFromInt(tc.ReasoningOutput).Mul(p.ReasoningOutput))
	return sum.Div(million)
}
