package httpapi

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type usageQuery struct {
	Tool  string `form:"tool" binding:"required,oneof=claude codex"`
	Range string `form:"range" binding:"required,oneof=today week month year"`
}

func RegisterRoutes(r *gin.Engine, usg UsageQuerier, hc HealthCheck, version string) {
	r.GET("/usage", func(c *gin.Context) {
		var q usageQuery
		if err := c.ShouldBindQuery(&q); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":  "invalid parameter",
				"detail": err.Error(),
			})
			return
		}
		res, err := usg.Query(q.Tool, q.Range)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "internal", "detail": err.Error()})
			return
		}
		c.JSON(http.StatusOK, res)
	})

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"ok":                      true,
			"version":                 version,
			"started_at":              hc.StartedAt().Format("2006-01-02T15:04:05-07:00"),
			"ingest_first_pass_done":  hc.IsFirstPassDone(),
			"last_ingest_stats":       hc.LastIngestStats(),
		})
	})

	r.GET("/version", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"version": version})
	})
}
