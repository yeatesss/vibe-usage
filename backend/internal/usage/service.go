package usage

import (
	"fmt"

	"github.com/shopspring/decimal"

	"github.com/yeatesss/vibe-usage/backend/internal/pricing"
	"github.com/yeatesss/vibe-usage/backend/internal/store"
)

// Reader is the narrow store interface usage depends on (ISP + DIP).
//
// The *ForProject variants restrict aggregation to a single project (cwd) by
// joining usage_events with the sessions table. They are only consulted when
// the caller passes a non-empty project filter to Query.
type Reader interface {
	SumByModel(tool string, startUTC, endUTC int64) ([]store.ModelTokenSum, error)
	SumByModelForProject(tool, project string, startUTC, endUTC int64) ([]store.ModelTokenSum, error)
	TotalInRange(tool string, startUTC, endUTC int64) (int64, error)
	TotalInRangeForProject(tool, project string, startUTC, endUTC int64) (int64, error)
	DistinctSessions(tool string, startUTC, endUTC int64) (int, error)
	DistinctSessionsForProject(tool, project string, startUTC, endUTC int64) (int, error)
}

type Service struct {
	reader Reader
	calc   *pricing.Calculator
	clock  Clock
}

func NewService(r Reader, calc *pricing.Calculator, clock Clock) *Service {
	return &Service{reader: r, calc: calc, clock: clock}
}

type Metrics struct {
	InputTokens           int64  `json:"input_tokens"`
	OutputTokens          int64  `json:"output_tokens"`
	CacheReadTokens       int64  `json:"cache_read_tokens"`
	CacheWriteTokens      int64  `json:"cache_write_tokens"`
	TotalTokens           int64  `json:"total_tokens"`
	ReasoningOutputTokens int64  `json:"reasoning_output_tokens"`
	CostUSD               string `json:"cost_usd"`
	Requests              int64  `json:"requests"`
}

type Series struct {
	Values []int64  `json:"values"`
	Labels []string `json:"labels"`
}

type QueryResult struct {
	Tool       string  `json:"tool"`
	Range      string  `json:"range"`
	Project    string  `json:"project,omitempty"` // cwd filter, empty when "all projects"
	RangeStart string  `json:"range_start"`
	RangeEnd   string  `json:"range_end"`
	Bucket     Bucket  `json:"bucket"`
	Metrics    Metrics `json:"metrics"`
	Sessions   int     `json:"sessions"`
	Series     Series  `json:"series"`
}

// Query aggregates usage for the given tool/range. When project is non-empty,
// results are filtered to events from sessions whose cwd matches.
func (s *Service) Query(tool, rangeName, project string) (*QueryResult, error) {
	rb, err := BoundariesFor(rangeName, s.clock)
	if err != nil {
		return nil, err
	}

	startUTC := rb.Start.UTC().Unix()
	endUTC := rb.End.UTC().Unix()

	var sums []store.ModelTokenSum
	if project == "" {
		sums, err = s.reader.SumByModel(tool, startUTC, endUTC)
	} else {
		sums, err = s.reader.SumByModelForProject(tool, project, startUTC, endUTC)
	}
	if err != nil {
		return nil, fmt.Errorf("sum by model: %w", err)
	}

	var m Metrics
	cost := decimal.Zero
	for _, r := range sums {
		m.InputTokens += r.Input
		m.OutputTokens += r.Output
		m.CacheReadTokens += r.CacheRead
		m.CacheWriteTokens += r.CacheWrite
		m.ReasoningOutputTokens += r.Reasoning
		m.Requests += r.Requests
		cost = cost.Add(s.calc.Compute(tool, r.Model, pricing.TokenCounts{
			Input:           r.Input,
			Output:          r.Output,
			CacheRead:       r.CacheRead,
			CacheWrite:      r.CacheWrite,
			ReasoningOutput: r.Reasoning,
		}))
	}
	m.TotalTokens = m.InputTokens + m.OutputTokens + m.CacheReadTokens + m.CacheWriteTokens
	m.CostUSD = cost.StringFixed(2)

	var sessions int
	if project == "" {
		sessions, err = s.reader.DistinctSessions(tool, startUTC, endUTC)
	} else {
		sessions, err = s.reader.DistinctSessionsForProject(tool, project, startUTC, endUTC)
	}
	if err != nil {
		return nil, fmt.Errorf("distinct sessions: %w", err)
	}

	values := make([]int64, rb.BucketCount)
	labels := make([]string, rb.BucketCount)
	for i, b := range rb.Buckets {
		labels[i] = b.Label
		var total int64
		if project == "" {
			total, err = s.reader.TotalInRange(tool, b.StartUTC, b.EndUTC)
		} else {
			total, err = s.reader.TotalInRangeForProject(tool, project, b.StartUTC, b.EndUTC)
		}
		if err != nil {
			return nil, fmt.Errorf("series bucket %d: %w", i, err)
		}
		values[i] = total
	}

	return &QueryResult{
		Tool:       tool,
		Range:      rangeName,
		Project:    project,
		RangeStart: rb.Start.Format("2006-01-02T15:04:05-07:00"),
		RangeEnd:   rb.End.Format("2006-01-02T15:04:05-07:00"),
		Bucket:     rb.Bucket,
		Metrics:    m,
		Sessions:   sessions,
		Series:     Series{Values: values, Labels: labels},
	}, nil
}
