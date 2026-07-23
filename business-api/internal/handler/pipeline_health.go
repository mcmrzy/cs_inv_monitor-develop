package handler

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

// PipelineHealthStatus represents the health status of a single service in the pipeline
type PipelineHealthStatus struct {
	ServiceName    string            `json:"service_name"`
	ServiceType    string            `json:"service_type"` // bridge, device-server, api
	Status         string            `json:"status"`       // ok, degraded, down
	LastCheckTime  time.Time         `json:"last_check_time"`
	Message        string            `json:"message,omitempty"`
	ResponseTimeMs int64             `json:"response_time_ms,omitempty"`
	Metrics        map[string]string `json:"metrics,omitempty"`
}

// PipelineHealthResponse is the aggregated response for pipeline health check
type PipelineHealthResponse struct {
	OverallStatus   string                    `json:"overall_status"` // ok, degraded, down
	CheckTime       time.Time                 `json:"check_time"`
	ServiceStatuses []PipelineHealthStatus    `json:"service_statuses"`
}

// PipelineMetricsResponse contains aggregated metrics for the data pipeline
type PipelineMetricsResponse struct {
	OnlineDeviceCount   int                     `json:"online_device_count"`
	TotalDeviceCount    int                     `json:"total_device_count"`
	MessageRate         float64                 `json:"message_rate"`          // messages per second
	DLQPending          int                     `json:"dlq_pending"`           // total pending in all DLQs
	AvgKafkaLag         float64                 `json:"avg_kafka_lag"`         // average lag across consumers
	CommandSuccessRate  float64                 `json:"command_success_rate"`  // percentage (0-100)
	SnapshotTime        time.Time               `json:"snapshot_time"`
	AdditionalMetrics   map[string]interface{}  `json:"additional_metrics,omitempty"`
}

// PipelineHealthHandler handles pipeline health aggregation endpoints
type PipelineHealthHandler struct {
	rdb *redis.Client
}

// NewPipelineHealthHandler creates a new PipelineHealthHandler instance
func NewPipelineHealthHandler(rdb *redis.Client) *PipelineHealthHandler {
	return &PipelineHealthHandler{
		rdb: rdb,
	}
}

// GetPipelineHealth aggregates health status from all services in the pipeline
// @Summary Get pipeline health status
// @Description Get aggregated health status from all services (bridge, device-server, api)
// @Tags System Health
// @Router /api/v1/system/pipeline-health [get]
func (h *PipelineHealthHandler) GetPipelineHealth(c *gin.Context) {
	ctx := c.Request.Context()

	var statuses []PipelineHealthStatus
	hasDown := false
	hasDegraded := false

	// Check MQTT Bridge
	bridgeStart := time.Now()
	bridgeStatus := h.checkServiceHealth(ctx, "mqtt-bridge", "bridge", "pipeline:health:bridge")
	bridgeDuration := time.Since(bridgeStart).Milliseconds()
	if len(bridgeStatus.Metrics) == 0 {
		bridgeStatus.Metrics = make(map[string]string)
	}
	bridgeStatus.Metrics["response_time_ms"] = strconv.FormatInt(bridgeDuration, 10)
	statuses = append(statuses, bridgeStatus)
	if bridgeStatus.Status == "down" {
		hasDown = true
	} else if bridgeStatus.Status == "degraded" {
		hasDegraded = true
	}

	// Check Device Server
	deviceServerStart := time.Now()
	deviceServerStatus := h.checkServiceHealth(ctx, "device-server", "device-server", "pipeline:health:device-server")
	deviceServerDuration := time.Since(deviceServerStart).Milliseconds()
	if len(deviceServerStatus.Metrics) == 0 {
		deviceServerStatus.Metrics = make(map[string]string)
	}
	deviceServerStatus.Metrics["response_time_ms"] = strconv.FormatInt(deviceServerDuration, 10)
	statuses = append(statuses, deviceServerStatus)
	if deviceServerStatus.Status == "down" {
		hasDown = true
	} else if deviceServerStatus.Status == "degraded" {
		hasDegraded = true
	}

	// Check API Server
	apiStart := time.Now()
	apiStatus := h.checkServiceHealth(ctx, "api-server", "api", "pipeline:health:api")
	apiDuration := time.Since(apiStart).Milliseconds()
	if len(apiStatus.Metrics) == 0 {
		apiStatus.Metrics = make(map[string]string)
	}
	apiStatus.Metrics["response_time_ms"] = strconv.FormatInt(apiDuration, 10)
	statuses = append(statuses, apiStatus)
	if apiStatus.Status == "down" {
		hasDown = true
	} else if apiStatus.Status == "degraded" {
		hasDegraded = true
	}

	// Calculate overall status
	var overallStatus string
	if hasDown {
		overallStatus = "down"
	} else if hasDegraded {
		overallStatus = "degraded"
	} else {
		overallStatus = "ok"
	}

	response.Success(c, PipelineHealthResponse{
		OverallStatus:   overallStatus,
		CheckTime:       time.Now().UTC(),
		ServiceStatuses: statuses,
	})
}

// checkServiceHealth checks the health of a specific service by reading Redis key
func (h *PipelineHealthHandler) checkServiceHealth(ctx context.Context, serviceName, serviceType, healthKey string) PipelineHealthStatus {
	val, err := h.rdb.Get(ctx, healthKey).Result()
	if err != nil {
		if err == redis.Nil {
			return PipelineHealthStatus{
				ServiceName:   serviceName,
				ServiceType:   serviceType,
				Status:        "down",
				LastCheckTime: time.Now().UTC(),
				Message:       "health key not found",
			}
		}
		return PipelineHealthStatus{
			ServiceName:   serviceName,
			ServiceType:   serviceType,
			Status:        "down",
			LastCheckTime: time.Now().UTC(),
			Message:       fmt.Sprintf("Redis error: %v", err),
		}
	}

	switch val {
	case "ok":
		return PipelineHealthStatus{
			ServiceName:   serviceName,
			ServiceType:   serviceType,
			Status:        "ok",
			LastCheckTime: time.Now().UTC(),
		}
	case "degraded":
		return PipelineHealthStatus{
			ServiceName:   serviceName,
			ServiceType:   serviceType,
			Status:        "degraded",
			LastCheckTime: time.Now().UTC(),
			Message:       "service running but with issues",
		}
	case "down":
		return PipelineHealthStatus{
			ServiceName:   serviceName,
			ServiceType:   serviceType,
			Status:        "down",
			LastCheckTime: time.Now().UTC(),
			Message:       "service is down",
		}
	default:
		return PipelineHealthStatus{
			ServiceName:   serviceName,
			ServiceType:   serviceType,
			Status:        "degraded",
			LastCheckTime: time.Now().UTC(),
			Message:       fmt.Sprintf("unexpected status: %s", val),
		}
	}
}

// GetPipelineMetrics retrieves aggregated metrics for the data pipeline
// @Summary Get pipeline metrics
// @Description Get aggregated metrics including device counts, message rates, and Kafka lag
// @Tags System Health
// @Router /api/v1/system/pipeline-metrics [get]
func (h *PipelineHealthHandler) GetPipelineMetrics(c *gin.Context) {
	ctx := c.Request.Context()

	metrics := &PipelineMetricsResponse{
		SnapshotTime: time.Now().UTC(),
		AdditionalMetrics: make(map[string]interface{}),
	}

	// Get online device count from active heartbeat keys
	onlineCount, err := h.getOnlineDeviceCount(ctx)
	if err != nil {
		response.InternalError(c, "Failed to get device count")
		return
	}
	metrics.OnlineDeviceCount = onlineCount

	// Get total device count from database
	totalCount := h.getTotalDeviceCount(ctx)
	metrics.TotalDeviceCount = totalCount

	// Get message rate from Redis or calculate
	metrics.MessageRate = h.getMessageRate(ctx)

	// Get DLQ pending count
	metrics.DLQPending = h.getDLQPendingCount(ctx)

	// Get average Kafka lag
	metrics.AvgKafkaLag = h.getAverageKafkaLag(ctx)

	// Get command success rate
	metrics.CommandSuccessRate = h.getCommandSuccessRate(ctx)

	response.Success(c, metrics)
}

// getOnlineDeviceCount gets the count of online devices from Redis heartbeat keys
func (h *PipelineHealthHandler) getOnlineDeviceCount(ctx context.Context) (int, error) {
	// Count device:heartbeat:* keys using SCAN
	keys := 0
	cursor := uint64(0)

	for {
		k, nextCursor, err := h.rdb.Scan(ctx, cursor, "device:heartbeat:*", 100).Result()
		if err != nil {
			return 0, err
		}
		keys += len(k)
		cursor = nextCursor
		if cursor == 0 {
			break
		}
	}

	return keys, nil
}

// getTotalDeviceCount gets the total number of devices from database
// Note: In production, this should query PostgreSQL; returns 0 as placeholder
func (h *PipelineHealthHandler) getTotalDeviceCount(ctx context.Context) int {
	// This would normally query PostgreSQL device tables
	// Placeholder implementation - needs DB connection injection
	return 0
}

// getMessageRate gets the current message rate (messages per second)
// Reads from pipeline:metrics:snapshot or estimates from recent activity
func (h *PipelineHealthHandler) getMessageRate(ctx context.Context) float64 {
	// Try to read from cached metrics snapshot
	_, err := h.rdb.Get(ctx, "pipeline:metrics:snapshot").Result()
	if err == nil {
		// Parse snapshot if available
		// For now, return estimated value
		return 0.0
	}

	// Estimate from recent message activity
	// This is a placeholder - actual implementation would track incoming messages
	return 0.0
}

// getDLQPendingCount gets the total number of messages in all DLQs
func (h *PipelineHealthHandler) getDLQPendingCount(ctx context.Context) int {
	total := 0

	// Count messages in each consumer's DLQ
	consumerTypes := []string{"bridge", "device-server", "api"}
	for _, consumerType := range consumerTypes {
		key := fmt.Sprintf("kafka:dlq:%s", consumerType)
		count, err := h.rdb.LLen(ctx, key).Result()
		if err == nil {
			total += int(count)
		}
	}

	return total
}

// getAverageKafkaLag gets the average Kafka consumer lag across all consumers
func (h *PipelineHealthHandler) getAverageKafkaLag(ctx context.Context) float64 {
	totalLag := 0.0
	count := 0

	// Check various Kafka lag metrics in Redis
	lagKeys := []string{
		"kafka:lag:bridge-consumer",
		"kafka:lag:device-server-consumer",
		"kafka:lag:api-consumer",
	}

	for _, key := range lagKeys {
		val, err := h.rdb.Get(ctx, key).Result()
		if err == nil {
			lag, parseErr := strconv.ParseFloat(val, 64)
			if parseErr == nil {
				totalLag += lag
				count++
			}
		}
	}

	if count == 0 {
		return 0.0
	}

	return totalLag / float64(count)
}

// getCommandSuccessRate gets the rate of successfully executed commands
func (h *PipelineHealthHandler) getCommandSuccessRate(ctx context.Context) float64 {
	// Read from command success/failure counters
	failureKey := "pipeline:metrics:commands:failure"
	successKey := "pipeline:metrics:commands:success"

	failureVal, _ := h.rdb.Get(ctx, failureKey).Result()
	successVal, _ := h.rdb.Get(ctx, successKey).Result()

	failure, fErr := strconv.Atoi(failureVal)
	success, sErr := strconv.Atoi(successVal)

	if fErr != nil || sErr != nil {
		return 100.0 // Return 100% if no data available
	}

	total := success + failure
	if total == 0 {
		return 100.0
	}

	return float64(success) / float64(total) * 100.0
}

// PingRedis returns PONG if Redis is reachable
func (h *PipelineHealthHandler) PingRedis(c *gin.Context) {
	ctx := c.Request.Context()
	
	result := h.rdb.Ping(ctx)
	if result.Err() != nil {
		response.InternalError(c, "Redis ping failed")
		return
	}
	
	response.Success(c, gin.H{
		"status": "pong",
		"message": "Redis is healthy",
	})
}
