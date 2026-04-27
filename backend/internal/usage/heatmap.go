package usage

import (
	"fmt"
	"time"

	"github.com/shopspring/decimal"

	"github.com/yeatesss/vibe-usage/backend/internal/pricing"
	"github.com/yeatesss/vibe-usage/backend/internal/store"
)

// HeatmapReader is the narrow store dependency for the daily heatmap.
type HeatmapReader interface {
	SumPerDayByModel(tool string, dayZeroUTC, endUTC int64) ([]store.DailyModelSum, error)
}

// HeatmapDay is one calendar day in SGT.
type HeatmapDay struct {
	Date        string `json:"date"`         // "2026-04-23"
	Weekday     int    `json:"weekday"`      // Monday=0..Sunday=6
	TotalTokens int64  `json:"total_tokens"` // input+output+cache_read+cache_write
	CostUSD     string `json:"cost_usd"`
	Requests    int64  `json:"requests"`
	IsFuture    bool   `json:"is_future"`
}

// HeatmapResult is the /usage/heatmap payload.
type HeatmapResult struct {
	Tool      string       `json:"tool"`
	Weeks     int          `json:"weeks"`
	StartDate string       `json:"start_date"` // first day (Monday)
	EndDate   string       `json:"end_date"`   // last day (Sunday)
	Today     string       `json:"today"`
	Days      []HeatmapDay `json:"days"`
}

const (
	minHeatmapWeeks     = 4
	maxHeatmapWeeks     = 53
	defaultHeatmapWeeks = 15
)

// ClampHeatmapWeeks enforces the allowed [min, max] range; 0/negative → default.
func ClampHeatmapWeeks(n int) int {
	if n <= 0 {
		return defaultHeatmapWeeks
	}
	if n < minHeatmapWeeks {
		return minHeatmapWeeks
	}
	if n > maxHeatmapWeeks {
		return maxHeatmapWeeks
	}
	return n
}

// HeatmapService builds GitHub-style daily mosaics. It shares the pricing
// calculator and clock with Service but only needs the per-day reader.
type HeatmapService struct {
	reader HeatmapReader
	calc   *pricing.Calculator
	clock  Clock
}

func NewHeatmapService(r HeatmapReader, calc *pricing.Calculator, clock Clock) *HeatmapService {
	return &HeatmapService{reader: r, calc: calc, clock: clock}
}

// Query returns `weeks * 7` days ending on the Sunday of the current SGT week.
// Future days (within the current week but after today) have zero metrics and
// IsFuture=true so the UI can render an empty cell.
func (s *HeatmapService) Query(tool string, weeks int) (*HeatmapResult, error) {
	weeks = ClampHeatmapWeeks(weeks)

	now := s.clock.Now().In(sgLocation)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, sgLocation)

	// Monday-start week. Go Weekday: Sunday=0..Saturday=6; convert to Mon=0.
	daysFromMon := (int(today.Weekday()) + 6) % 7
	currentWeekMon := today.AddDate(0, 0, -daysFromMon)
	startDay := currentWeekMon.AddDate(0, 0, -(weeks-1)*7)
	endDay := currentWeekMon.AddDate(0, 0, 7) // exclusive, = next Monday

	dayZeroUTC := startDay.UTC().Unix()
	endUTC := endDay.UTC().Unix()
	todayIdx := int(today.Sub(startDay) / (24 * time.Hour))
	dayCount := weeks * 7

	sums, err := s.reader.SumPerDayByModel(tool, dayZeroUTC, endUTC)
	if err != nil {
		return nil, fmt.Errorf("heatmap sum per day: %w", err)
	}

	totals := make([]int64, dayCount)
	costs := make([]decimal.Decimal, dayCount)
	requests := make([]int64, dayCount)
	for i := range costs {
		costs[i] = decimal.Zero
	}
	for _, r := range sums {
		if r.DayIndex < 0 || r.DayIndex >= dayCount {
			continue
		}
		totals[r.DayIndex] += r.Input + r.Output + r.CacheRead + r.CacheWrite
		requests[r.DayIndex] += r.Requests
		costs[r.DayIndex] = costs[r.DayIndex].Add(s.calc.Compute(tool, r.Model, pricing.TokenCounts{
			Input:           r.Input,
			Output:          r.Output,
			CacheRead:       r.CacheRead,
			CacheWrite:      r.CacheWrite,
			ReasoningOutput: r.Reasoning,
		}))
	}

	days := make([]HeatmapDay, dayCount)
	for i := 0; i < dayCount; i++ {
		d := startDay.AddDate(0, 0, i)
		wd := (int(d.Weekday()) + 6) % 7
		days[i] = HeatmapDay{
			Date:        d.Format("2006-01-02"),
			Weekday:     wd,
			TotalTokens: totals[i],
			CostUSD:     costs[i].StringFixed(4),
			Requests:    requests[i],
			IsFuture:    i > todayIdx,
		}
	}

	return &HeatmapResult{
		Tool:      tool,
		Weeks:     weeks,
		StartDate: startDay.Format("2006-01-02"),
		EndDate:   endDay.AddDate(0, 0, -1).Format("2006-01-02"),
		Today:     today.Format("2006-01-02"),
		Days:      days,
	}, nil
}
