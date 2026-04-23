// Package httpapi is a thin gin-based HTTP layer.
// It depends only on narrow interfaces (UsageQuerier, HealthCheck) for testability.
package httpapi

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/yeatesss/vibe-usage/backend/internal/usage"
)

type UsageQuerier interface {
	Query(tool, rangeName string) (*usage.QueryResult, error)
}

type HealthCheck interface {
	StartedAt() time.Time
	IsFirstPassDone() bool
	LastIngestStats() map[string]any
}

// NewRouter creates a gin.Engine with all routes registered.
func NewRouter(usg UsageQuerier, hc HealthCheck, version string) *gin.Engine {
	r := gin.New()
	r.Use(gin.Recovery())
	RegisterRoutes(r, usg, hc, version)
	return r
}

// NewServer wraps the router in an *http.Server; caller is responsible for
// calling http.Serve(listener) and server.Shutdown(ctx).
func NewServer(handler http.Handler) *http.Server {
	return &http.Server{
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
	}
}

// ShutdownWithTimeout gracefully stops the server with a bounded deadline.
func ShutdownWithTimeout(srv *http.Server, d time.Duration) error {
	ctx, cancel := context.WithTimeout(context.Background(), d)
	defer cancel()
	return srv.Shutdown(ctx)
}
