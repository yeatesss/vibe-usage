package usage

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/shopspring/decimal"

	"github.com/yeatesss/vibe-usage/backend/internal/pricing"
	"github.com/yeatesss/vibe-usage/backend/internal/store"
)

// ProjectsReader is the narrow store interface ProjectsService depends on.
type ProjectsReader interface {
	ListProjects(tool string, startUTC, endUTC int64) ([]store.ProjectAgg, error)
	SumByModelForProject(tool, project string, startUTC, endUTC int64) ([]store.ModelTokenSum, error)
}

// ProjectsService produces the per-project aggregation list. Cost is computed
// per-project by summing model-level pricing — same logic as the all-projects
// query, just scoped via the sessions JOIN.
type ProjectsService struct {
	reader ProjectsReader
	calc   *pricing.Calculator
	clock  Clock
}

func NewProjectsService(r ProjectsReader, calc *pricing.Calculator, clock Clock) *ProjectsService {
	return &ProjectsService{reader: r, calc: calc, clock: clock}
}

// Project is one row in the projects list response.
type Project struct {
	Cwd             string   `json:"cwd"`
	DisplayName     string   `json:"display_name"`
	GitBranches     []string `json:"git_branches"`
	InputTokens     int64    `json:"input_tokens"`
	OutputTokens    int64    `json:"output_tokens"`
	CacheReadTokens int64    `json:"cache_read_tokens"`
	CacheWriteTok   int64    `json:"cache_write_tokens"`
	ReasoningTok    int64    `json:"reasoning_output_tokens"`
	TotalTokens     int64    `json:"total_tokens"`
	CostUSD         string   `json:"cost_usd"`
	Requests        int64    `json:"requests"`
	Sessions        int64    `json:"sessions"`
	LastActiveAt    string   `json:"last_active_at,omitempty"`
	FirstActiveAt   string   `json:"first_active_at,omitempty"`
}

// ProjectsResult is the JSON payload for GET /usage/projects.
type ProjectsResult struct {
	Tool     string    `json:"tool"`
	Range    string    `json:"range"`
	Projects []Project `json:"projects"`
}

// List returns the per-project aggregation, sorted by cost descending.
// An empty cwd is mapped to display name "(unknown)".
func (s *ProjectsService) List(tool, rangeName string) (*ProjectsResult, error) {
	rb, err := BoundariesFor(rangeName, s.clock)
	if err != nil {
		return nil, err
	}
	startUTC := rb.Start.UTC().Unix()
	endUTC := rb.End.UTC().Unix()

	rows, err := s.reader.ListProjects(tool, startUTC, endUTC)
	if err != nil {
		return nil, fmt.Errorf("list projects: %w", err)
	}

	projects := make([]Project, 0, len(rows))
	for _, r := range rows {
		// Per-project cost requires the model breakdown — totals don't carry it.
		sums, err := s.reader.SumByModelForProject(tool, r.Cwd, startUTC, endUTC)
		if err != nil {
			return nil, fmt.Errorf("sum by model for project %q: %w", r.Cwd, err)
		}
		cost := decimal.Zero
		for _, m := range sums {
			cost = cost.Add(s.calc.Compute(tool, m.Model, pricing.TokenCounts{
				Input:           m.Input,
				Output:          m.Output,
				CacheRead:       m.CacheRead,
				CacheWrite:      m.CacheWrite,
				ReasoningOutput: m.Reasoning,
			}))
		}

		projects = append(projects, Project{
			Cwd:             r.Cwd,
			DisplayName:     displayName(r.Cwd),
			GitBranches:     splitBranches(r.GitBranches),
			InputTokens:     r.InputTokens,
			OutputTokens:    r.OutputTokens,
			CacheReadTokens: r.CacheReadTok,
			CacheWriteTok:   r.CacheWriteTok,
			ReasoningTok:    r.ReasoningTok,
			TotalTokens:     r.InputTokens + r.OutputTokens + r.CacheReadTok + r.CacheWriteTok,
			CostUSD:         cost.StringFixed(2),
			Requests:        r.Requests,
			Sessions:        r.Sessions,
			LastActiveAt:    formatUTC(r.LastActiveUTC),
			FirstActiveAt:   formatUTC(r.FirstActiveUTC),
		})
	}

	// Stable sort by cost desc; ties broken by total tokens then name.
	sort.SliceStable(projects, func(i, j int) bool {
		ci, _ := decimal.NewFromString(projects[i].CostUSD)
		cj, _ := decimal.NewFromString(projects[j].CostUSD)
		if !ci.Equal(cj) {
			return ci.GreaterThan(cj)
		}
		if projects[i].TotalTokens != projects[j].TotalTokens {
			return projects[i].TotalTokens > projects[j].TotalTokens
		}
		return projects[i].DisplayName < projects[j].DisplayName
	})

	return &ProjectsResult{Tool: tool, Range: rangeName, Projects: projects}, nil
}

func displayName(cwd string) string {
	if cwd == "" {
		return "(unknown)"
	}
	if base := filepath.Base(cwd); base != "" && base != "." && base != "/" {
		return base
	}
	return cwd
}

// splitBranches turns a comma-separated GROUP_CONCAT result into a deduplicated
// slice. SQLite's GROUP_CONCAT preserves DISTINCT ordering as encountered.
func splitBranches(s string) []string {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	seen := map[string]bool{}
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" || seen[p] {
			continue
		}
		seen[p] = true
		out = append(out, p)
	}
	return out
}

func formatUTC(unix int64) string {
	if unix <= 0 {
		return ""
	}
	return time.Unix(unix, 0).UTC().Format("2006-01-02T15:04:05Z")
}
