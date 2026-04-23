package usage

import (
	"fmt"
	"time"
)

type Bucket string

const (
	BucketHour  Bucket = "hour"
	BucketDay   Bucket = "day"
	BucketMonth Bucket = "month"
)

// BucketBoundary represents one bucket's [StartUTC, EndUTC) in Unix seconds.
type BucketBoundary struct {
	StartUTC, EndUTC int64
	Label            string
}

// Boundaries summarizes a range for querying.
type Boundaries struct {
	Start, End   time.Time
	Bucket       Bucket
	BucketCount  int
	Buckets      []BucketBoundary
}

var sgLocation *time.Location

func init() {
	loc, err := time.LoadLocation("Asia/Singapore")
	if err != nil {
		sgLocation = time.FixedZone("SGT", 8*3600)
		return
	}
	sgLocation = loc
}

// Location returns Asia/Singapore.
func Location() *time.Location { return sgLocation }

// BoundariesFor builds bucket boundaries for a range name using clock.Now().
func BoundariesFor(rangeName string, clock Clock) (Boundaries, error) {
	now := clock.Now().In(sgLocation)
	switch rangeName {
	case "today":
		start := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, sgLocation)
		return buildHourly(start, now), nil
	case "week":
		weekday := int(now.Weekday())
		daysFromMon := (weekday + 6) % 7
		monStart := time.Date(now.Year(), now.Month(), now.Day()-daysFromMon, 0, 0, 0, 0, sgLocation)
		return buildDaily(monStart, now, 7, weekLabels()), nil
	case "month":
		monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, sgLocation)
		nextMonth := monthStart.AddDate(0, 1, 0)
		days := int(nextMonth.Sub(monthStart) / (24 * time.Hour))
		labels := monthLabels(days)
		return buildDaily(monthStart, now, days, labels), nil
	case "year":
		yearStart := time.Date(now.Year(), 1, 1, 0, 0, 0, 0, sgLocation)
		return buildMonthly(yearStart, now), nil
	default:
		return Boundaries{}, fmt.Errorf("unknown range %q", rangeName)
	}
}

func buildHourly(start, end time.Time) Boundaries {
	b := Boundaries{Start: start, End: end, Bucket: BucketHour, BucketCount: 24}
	b.Buckets = make([]BucketBoundary, 24)
	for i := 0; i < 24; i++ {
		bs := start.Add(time.Duration(i) * time.Hour)
		be := bs.Add(time.Hour)
		lbl := ""
		switch i {
		case 0:
			lbl = "00"
		case 6:
			lbl = "06"
		case 12:
			lbl = "12"
		case 18:
			lbl = "18"
		case 23:
			lbl = "Now"
		}
		b.Buckets[i] = BucketBoundary{StartUTC: bs.UTC().Unix(), EndUTC: be.UTC().Unix(), Label: lbl}
	}
	return b
}

func buildDaily(start, end time.Time, count int, labels []string) Boundaries {
	b := Boundaries{Start: start, End: end, Bucket: BucketDay, BucketCount: count}
	b.Buckets = make([]BucketBoundary, count)
	for i := 0; i < count; i++ {
		bs := start.AddDate(0, 0, i)
		be := bs.AddDate(0, 0, 1)
		lbl := ""
		if i < len(labels) {
			lbl = labels[i]
		}
		b.Buckets[i] = BucketBoundary{StartUTC: bs.UTC().Unix(), EndUTC: be.UTC().Unix(), Label: lbl}
	}
	return b
}

func buildMonthly(start, end time.Time) Boundaries {
	b := Boundaries{Start: start, End: end, Bucket: BucketMonth, BucketCount: 12}
	b.Buckets = make([]BucketBoundary, 12)
	months := []string{"J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"}
	for i := 0; i < 12; i++ {
		bs := time.Date(start.Year(), time.Month(i+1), 1, 0, 0, 0, 0, sgLocation)
		be := bs.AddDate(0, 1, 0)
		b.Buckets[i] = BucketBoundary{StartUTC: bs.UTC().Unix(), EndUTC: be.UTC().Unix(), Label: months[i]}
	}
	return b
}

func weekLabels() []string {
	return []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
}

func monthLabels(days int) []string {
	labels := make([]string, days)
	for _, d := range []int{1, 8, 15, 22, 29} {
		if d <= days {
			labels[d-1] = fmt.Sprintf("%d", d)
		}
	}
	return labels
}
