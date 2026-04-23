package parser

import "regexp"

var (
	// Captures 'claude-{opus|sonnet|haiku}-{major}-{minor?}' optionally followed by -YYYYMMDD.
	claudeRe = regexp.MustCompile(`^(claude-(?:opus|sonnet|haiku)-\d+(?:-\d{1,2})?)(?:-\d{8})?$`)
	// Captures 'gpt-{major}.{minor}' with optional '-codex' and optional -YYYYMMDD.
	// The '-codex' suffix is appended in normalized form so pricing lookup matches
	// even when the CLI emits the bare model id (e.g., "gpt-5.4").
	codexRe = regexp.MustCompile(`^(gpt-\d+\.\d+)(?:-codex)?(?:-\d{8})?$`)
)

// NormalizeModel strips date suffixes (e.g., "-20250514") from Claude/Codex model IDs.
// Unknown patterns pass through unchanged; downstream pricing resolver will miss
// and cost-compute degrades to 0 (still stored in usage_events.model).
func NormalizeModel(raw string) string {
	if m := claudeRe.FindStringSubmatch(raw); len(m) == 2 {
		return m[1]
	}
	if m := codexRe.FindStringSubmatch(raw); len(m) == 2 {
		return m[1] + "-codex"
	}
	return raw
}
