package store

import (
	"fmt"
	"time"

	"github.com/shopspring/decimal"
)

// PricingRow mirrors a pricing_profiles row with decimals already parsed.
type PricingRow struct {
	Model, Source   string
	EffectiveFrom   time.Time
	Input           decimal.Decimal
	CachedInput     decimal.Decimal
	CacheCreation   decimal.Decimal
	Output          decimal.Decimal
	ReasoningOutput decimal.Decimal
}

// LoadPricing returns all rows from pricing_profiles. Caller (pricing.Resolver)
// is responsible for keeping only the latest per (source, model).
func (s *Store) LoadPricing() ([]PricingRow, error) {
	const q = `SELECT model, source, effective_from,
	                 input_usd_per_million, cached_input_usd_per_million,
	                 cache_creation_usd_per_million, output_usd_per_million,
	                 reasoning_output_usd_per_million
	           FROM pricing_profiles`
	rows, err := s.db.Query(q)
	if err != nil {
		return nil, fmt.Errorf("query pricing: %w", err)
	}
	defer rows.Close()

	var out []PricingRow
	for rows.Next() {
		var r PricingRow
		var effective string
		var input, cachedInput, cacheCreation, output, reasoning string
		if err := rows.Scan(&r.Model, &r.Source, &effective,
			&input, &cachedInput, &cacheCreation, &output, &reasoning); err != nil {
			return nil, fmt.Errorf("scan pricing row: %w", err)
		}
		r.EffectiveFrom, err = time.Parse("2006-01-02", effective)
		if err != nil {
			return nil, fmt.Errorf("parse effective_from %q: %w", effective, err)
		}
		if r.Input, err = decimal.NewFromString(input); err != nil {
			return nil, fmt.Errorf("parse input rate: %w", err)
		}
		if r.CachedInput, err = decimal.NewFromString(cachedInput); err != nil {
			return nil, fmt.Errorf("parse cached_input rate: %w", err)
		}
		if r.CacheCreation, err = decimal.NewFromString(cacheCreation); err != nil {
			return nil, fmt.Errorf("parse cache_creation rate: %w", err)
		}
		if r.Output, err = decimal.NewFromString(output); err != nil {
			return nil, fmt.Errorf("parse output rate: %w", err)
		}
		if r.ReasoningOutput, err = decimal.NewFromString(reasoning); err != nil {
			return nil, fmt.Errorf("parse reasoning_output rate: %w", err)
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}
