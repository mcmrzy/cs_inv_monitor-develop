package middleware

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
)

var (
	TotalRequests   *prometheus.CounterVec
	RequestDuration *prometheus.HistogramVec
	RequestsInFlight prometheus.Gauge
)

func InitMetrics() {
	TotalRequests = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "api_gateway_requests_total",
			Help: "网关处理的请求总数",
		},
		[]string{"method", "path", "status"},
	)
	RequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "api_gateway_request_duration_seconds",
			Help:    "请求处理延迟（秒）",
			Buckets: []float64{0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10},
		},
		[]string{"method", "path", "status"},
	)
	RequestsInFlight = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "api_gateway_requests_in_flight",
			Help: "当前正在处理的请求数",
		},
	)
	prometheus.MustRegister(TotalRequests, RequestDuration, RequestsInFlight)
}

func Prometheus() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.URL.Path == "/metrics" {
			c.Next()
			return
		}

		RequestsInFlight.Inc()
		start := time.Now()

		c.Next()

		RequestsInFlight.Dec()
		status := strconv.Itoa(c.Writer.Status())
		method := c.Request.Method
		path := c.FullPath()
		if path == "" {
			path = c.Request.URL.Path
		}

		TotalRequests.WithLabelValues(method, path, status).Inc()
		RequestDuration.WithLabelValues(method, path, status).Observe(time.Since(start).Seconds())
	}
}
