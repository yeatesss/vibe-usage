package httpapi

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

type usageQuery struct {
	Tool  string `form:"tool" binding:"required,oneof=claude codex"`
	Range string `form:"range" binding:"required,oneof=today week month year"`
}

type heatmapQuery struct {
	Tool  string `form:"tool" binding:"required,oneof=claude codex"`
	Weeks int    `form:"weeks"`
}

type tickBody struct {
	Tick string `json:"tick" binding:"required"`
}

func RegisterRoutes(r *gin.Engine, usg UsageQuerier, hm HeatmapQuerier, hc HealthCheck, tc TickConfigurer, version string) {
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

	r.GET("/usage/heatmap", func(c *gin.Context) {
		var q heatmapQuery
		if err := c.ShouldBindQuery(&q); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":  "invalid parameter",
				"detail": err.Error(),
			})
			return
		}
		res, err := hm.Query(q.Tool, q.Weeks)
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

	r.GET("/config/tick", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"tick": tc.Tick().String()})
	})

	r.PUT("/config/tick", func(c *gin.Context) {
		var body tickBody
		if err := c.ShouldBindJSON(&body); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid parameter", "detail": err.Error()})
			return
		}
		d, err := time.ParseDuration(body.Tick)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid duration", "detail": err.Error()})
			return
		}
		if err := tc.SetTick(d); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "out of range", "detail": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"tick": d.String()})
	})
}
