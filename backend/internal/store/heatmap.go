package store

// DailyModelSum is one (dayIndex, model) bucket of per-kind token sums
// plus request count. dayIndex is computed relative to the caller-provided
// day-zero UTC boundary: dayIndex = floor((ts_utc - dayZeroUTC) / 86400).
type DailyModelSum struct {
	DayIndex                                                  int
	Model                                                     string
	Input, Output, CacheRead, CacheWrite, Reasoning, Requests int64
}

// SumPerDayByModel returns per-day, per-model token totals for the given tool
// in [dayZeroUTC, endUTC). Callers pass dayZeroUTC aligned to the first
// display day's midnight in the target timezone; that way (ts_utc - dayZeroUTC)/86400
// produces a stable day index regardless of the DB-stored UTC values.
func (s *Store) SumPerDayByModel(tool string, dayZeroUTC, endUTC int64) ([]DailyModelSum, error) {
	const q = `
SELECT CAST((ts_utc - ?) / 86400 AS INTEGER) AS day_idx,
       model,
       COALESCE(SUM(input_tokens),0),
       COALESCE(SUM(output_tokens),0),
       COALESCE(SUM(cache_read_tokens),0),
       COALESCE(SUM(cache_write_tokens),0),
       COALESCE(SUM(reasoning_output_tokens),0),
       COUNT(*)
FROM usage_events
WHERE tool = ? AND ts_utc >= ? AND ts_utc < ?
GROUP BY day_idx, model`
	rows, err := s.db.Query(q, dayZeroUTC, tool, dayZeroUTC, endUTC)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []DailyModelSum
	for rows.Next() {
		var r DailyModelSum
		if err := rows.Scan(&r.DayIndex, &r.Model, &r.Input, &r.Output, &r.CacheRead, &r.CacheWrite, &r.Reasoning, &r.Requests); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}
