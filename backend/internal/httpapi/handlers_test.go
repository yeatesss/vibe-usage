package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
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
}

func (f *fakeUsage) Query(tool, rangeName string) (*usage.QueryResult, error) {
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

func newRouter(usg UsageQuerier, hc HealthCheck, version string) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterRoutes(r, usg, hc, version)
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

func TestHandlers_Version(t *testing.T) {
	hc := &fakeHealth{}
	r := newRouter(&fakeUsage{}, hc, "0.1.0")

	req := httptest.NewRequest("GET", "/version", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), `"version":"0.1.0"`)
}
