package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/yeatesss/vibe-usage/backend/internal/usage"
)

type fakeUsage struct {
	res *usage.QueryResult
	err error

	gotProject string // captured for assertion in project-filter tests
}

func (f *fakeUsage) Query(tool, rangeName, project string) (*usage.QueryResult, error) {
	f.gotProject = project
	return f.res, f.err
}

type fakeHeatmap struct {
	res *usage.HeatmapResult
	err error
}

func (f *fakeHeatmap) Query(tool string, weeks int) (*usage.HeatmapResult, error) {
	return f.res, f.err
}

type fakeProjects struct {
	res *usage.ProjectsResult
	err error
}

func (f *fakeProjects) List(tool, rangeName string) (*usage.ProjectsResult, error) {
	return f.res, f.err
}

type fakeHealth struct {
	firstPass bool
	startedAt time.Time
}

func (f *fakeHealth) StartedAt() time.Time  { return f.startedAt }
func (f *fakeHealth) IsFirstPassDone() bool { return f.firstPass }
func (f *fakeHealth) LastIngestStats() map[string]any {
	return map[string]any{"files_scanned": 0}
}

type fakeTick struct {
	cur time.Duration
	err error
}

func (f *fakeTick) Tick() time.Duration { return f.cur }
func (f *fakeTick) SetTick(d time.Duration) error {
	if f.err != nil {
		return f.err
	}
	f.cur = d
	return nil
}

func newRouter(usg UsageQuerier, hc HealthCheck, version string) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterRoutes(r, usg, &fakeHeatmap{}, &fakeProjects{}, hc, &fakeTick{cur: 30 * time.Second}, version)
	return r
}

func newRouterWithProjects(usg UsageQuerier, pq ProjectsQuerier) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterRoutes(r, usg, &fakeHeatmap{}, pq, &fakeHealth{}, &fakeTick{cur: 30 * time.Second}, "test")
	return r
}

func newRouterWithTick(tc TickConfigurer) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterRoutes(r, &fakeUsage{}, &fakeHeatmap{}, &fakeProjects{}, &fakeHealth{}, tc, "test")
	return r
}

func TestHandlers_Usage_Valid(t *testing.T) {
	usg := &fakeUsage{res: &usage.QueryResult{Tool: "claude", Range: "today"}}
	hc := &fakeHealth{firstPass: true, startedAt: time.Now()}
	r := newRouter(usg, hc, "0.1.0")

	req := httptest.NewRequest("GET", "/usage?tool=claude&range=today", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	require.Equal(t, http.StatusOK, w.Code)
	var body usage.QueryResult
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &body))
	assert.Equal(t, "claude", body.Tool)
}

func TestHandlers_Usage_InvalidTool(t *testing.T) {
	usg := &fakeUsage{}
	hc := &fakeHealth{}
	r := newRouter(usg, hc, "0.1.0")

	req := httptest.NewRequest("GET", "/usage?tool=invalid&range=today", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestHandlers_Usage_InvalidRange(t *testing.T) {
	usg := &fakeUsage{}
	hc := &fakeHealth{}
	r := newRouter(usg, hc, "0.1.0")

	req := httptest.NewRequest("GET", "/usage?tool=claude&range=decade", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestHandlers_Health(t *testing.T) {
	hc := &fakeHealth{firstPass: true, startedAt: time.Date(2026, 4, 22, 0, 0, 0, 0, time.UTC)}
	r := newRouter(&fakeUsage{}, hc, "0.1.0")

	req := httptest.NewRequest("GET", "/health", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)

	var body map[string]any
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &body))
	assert.Equal(t, true, body["ok"])
	assert.Equal(t, true, body["ingest_first_pass_done"])
	assert.Equal(t, "0.1.0", body["version"])
}

func TestHandlers_GetTick(t *testing.T) {
	tc := &fakeTick{cur: 45 * time.Second}
	r := newRouterWithTick(tc)

	req := httptest.NewRequest("GET", "/config/tick", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	require.Equal(t, http.StatusOK, w.Code)
	var body map[string]any
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &body))
	assert.Equal(t, "45s", body["tick"])
}

func TestHandlers_PutTick_Valid(t *testing.T) {
	tc := &fakeTick{cur: 30 * time.Second}
	r := newRouterWithTick(tc)

	req := httptest.NewRequest("PUT", "/config/tick", strings.NewReader(`{"tick":"60s"}`))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	require.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, 60*time.Second, tc.cur)
}

func TestHandlers_PutTick_BadDuration(t *testing.T) {
	tc := &fakeTick{cur: 30 * time.Second}
	r := newRouterWithTick(tc)

	req := httptest.NewRequest("PUT", "/config/tick", strings.NewReader(`{"tick":"not-a-duration"}`))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
	assert.Equal(t, 30*time.Second, tc.cur, "bad input must not mutate state")
}

func TestHandlers_PutTick_OutOfRange(t *testing.T) {
	tc := &fakeTick{cur: 30 * time.Second, err: errors.New("out of range")}
	r := newRouterWithTick(tc)

	req := httptest.NewRequest("PUT", "/config/tick", strings.NewReader(`{"tick":"60s"}`))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestHandlers_Usage_PassesProjectFilter(t *testing.T) {
	usg := &fakeUsage{res: &usage.QueryResult{Tool: "claude", Range: "week"}}
	r := newRouter(usg, &fakeHealth{}, "0.1.0")

	req := httptest.NewRequest("GET", "/usage?tool=claude&range=week&project=/Users/me/proj-a", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	require.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "/Users/me/proj-a", usg.gotProject)
}

func TestHandlers_Usage_NoProjectIsPassedAsEmpty(t *testing.T) {
	usg := &fakeUsage{res: &usage.QueryResult{Tool: "claude", Range: "week"}}
	r := newRouter(usg, &fakeHealth{}, "0.1.0")

	req := httptest.NewRequest("GET", "/usage?tool=claude&range=week", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	require.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "", usg.gotProject)
}

func TestHandlers_Projects_Valid(t *testing.T) {
	pq := &fakeProjects{res: &usage.ProjectsResult{
		Tool: "claude", Range: "month",
		Projects: []usage.Project{
			{Cwd: "/Users/me/proj-a", DisplayName: "proj-a", CostUSD: "12.34", TotalTokens: 1000},
			{Cwd: "/Users/me/proj-b", DisplayName: "proj-b", CostUSD: "1.20", TotalTokens: 200},
		},
	}}
	r := newRouterWithProjects(&fakeUsage{}, pq)

	req := httptest.NewRequest("GET", "/usage/projects?tool=claude&range=month", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	require.Equal(t, http.StatusOK, w.Code)
	var body usage.ProjectsResult
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &body))
	assert.Len(t, body.Projects, 2)
	assert.Equal(t, "proj-a", body.Projects[0].DisplayName)
	assert.Equal(t, "12.34", body.Projects[0].CostUSD)
}

func TestHandlers_Projects_InvalidRange(t *testing.T) {
	r := newRouterWithProjects(&fakeUsage{}, &fakeProjects{})

	req := httptest.NewRequest("GET", "/usage/projects?tool=claude&range=decade", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestHandlers_Version(t *testing.T) {
	hc := &fakeHealth{}
	r := newRouter(&fakeUsage{}, hc, "0.1.0")

	req := httptest.NewRequest("GET", "/version", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), `"version":"0.1.0"`)
}
