package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"
)

// PipelineHealthHandlerTestSuite tests for PipelineHealthHandler
type PipelineHealthHandlerTestSuite struct {
	suite.Suite
	rdb               *redis.Client
	s                   *miniredis.Miniredis
	handler           *PipelineHealthHandler
	router            *gin.Engine
}

// SetupSuite runs before all tests in the suite
func (suite *PipelineHealthHandlerTestSuite) SetupSuite() {
	// Start a mock Redis server
	s, err := miniredis.Run()
	assert.NoError(suite.T(), err)
	suite.s = s

	// Connect to mock Redis
	suite.rdb = redis.NewClient(&redis.Options{
		Addr: s.Addr(),
	})

	// Create handler
	suite.handler = NewPipelineHealthHandler(suite.rdb)

	// Setup Gin router
	gin.SetMode(gin.TestMode)
	suite.router = gin.Default()
	suite.router.GET("/api/v1/system/pipeline-health", suite.handler.GetPipelineHealth)
	suite.router.GET("/api/v1/system/pipeline-metrics", suite.handler.GetPipelineMetrics)
	suite.router.GET("/api/v1/system/health/ping-redis", suite.handler.PingRedis)
}

// TearDownSuite runs after all tests in the suite
func (suite *PipelineHealthHandlerTestSuite) TearDownSuite() {
	if suite.s != nil {
		suite.s.Close()
	}
	if suite.rdb != nil {
		suite.rdb.Close()
	}
}

// TestPipelineHealth_AllOK tests when all services are healthy
func (suite *PipelineHealthHandlerTestSuite) TestPipelineHealth_AllOK() {
	// Set all services as healthy
	ctx := context.Background()
	suite.rdb.Set(ctx, "pipeline:health:bridge", "ok", 0)
	suite.rdb.Set(ctx, "pipeline:health:device-server", "ok", 0)
	suite.rdb.Set(ctx, "pipeline:health:api", "ok", 0)

	// Create test request
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/system/pipeline-health", nil)

	// Call handler
	suite.handler.GetPipelineHealth(c)

	// Assert response
	suite.Equal(http.StatusOK, w.Code)
	var result map[string]interface{}
	suite.NoError(json.Unmarshal(w.Body.Bytes(), &result))

	// Verify overall status is "ok"
	overallStatus, ok := result["overall_status"].(string)
	suite.True(ok)
	suite.Equal("ok", overallStatus)

	// Verify we have 3 service statuses
	serviceStatuses, ok := result["service_statuses"].([]interface{})
	suite.True(ok)
	suite.Len(serviceStatuses, 3)
}

// TestPipelineHealth_DegradedWhenServiceDown tests when one or more services are degraded/down
func (suite *PipelineHealthHandlerTestSuite) TestPipelineHealth_DegradedWhenServiceDown() {
	ctx := context.Background()

	// Set bridge as degraded, others ok
	suite.rdb.Set(ctx, "pipeline:health:bridge", "degraded", 0)
	suite.rdb.Set(ctx, "pipeline:health:device-server", "ok", 0)
	suite.rdb.Set(ctx, "pipeline:health:api", "ok", 0)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/system/pipeline-health", nil)

	suite.handler.GetPipelineHealth(c)

	suite.Equal(http.StatusOK, w.Code)
	var result map[string]interface{}
	suite.NoError(json.Unmarshal(w.Body.Bytes(), &result))

	// Overall should be "degraded" since one service is degraded
	overallStatus, ok := result["overall_status"].(string)
	suite.True(ok)
	suite.Equal("degraded", overallStatus)
}

// TestPipelineHealth_DownWhenServiceDown tests when a service is down
func (suite *PipelineHealthHandlerTestSuite) TestPipelineHealth_DownWhenServiceDown() {
	ctx := context.Background()

	// Set bridge as down
	suite.rdb.Set(ctx, "pipeline:health:bridge", "down", 0)
	suite.rdb.Set(ctx, "pipeline:health:device-server", "ok", 0)
	suite.rdb.Set(ctx, "pipeline:health:api", "ok", 0)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/system/pipeline-health", nil)

	suite.handler.GetPipelineHealth(c)

	suite.Equal(http.StatusOK, w.Code)
	var result map[string]interface{}
	suite.NoError(json.Unmarshal(w.Body.Bytes(), &result))

	// Overall should be "down" since one service is down
	overallStatus, ok := result["overall_status"].(string)
	suite.True(ok)
	suite.Equal("down", overallStatus)
}

// TestPipelineHealth_MissingKeys tests when health keys don't exist
func (suite *PipelineHealthHandlerTestSuite) TestPipelineHealth_MissingKeys() {
	// Don't set any health keys - they should all be missing

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/system/pipeline-health", nil)

	suite.handler.GetPipelineHealth(c)

	suite.Equal(http.StatusOK, w.Code)
	var result map[string]interface{}
	suite.NoError(json.Unmarshal(w.Body.Bytes(), &result))

	// Overall should be "down" when all keys are missing
	overallStatus, ok := result["overall_status"].(string)
	suite.True(ok)
	suite.Equal("down", overallStatus)
}

// TestPipelineHealth_PipelineMetrics tests metrics endpoint
func (suite *PipelineHealthHandlerTestSuite) TestPipelineHealth_PipelineMetrics() {
	ctx := context.Background()

	// Set up some metrics data
	suite.rdb.Set(ctx, "pipeline:metrics:snapshot", `{"message_rate": 100.5}`, 0)
	suite.rdb.Set(ctx, "kafka:lag:bridge-consumer", "10.5", 0)
	suite.rdb.Set(ctx, "kafka:lag:device-server-consumer", "20.3", 0)
	suite.rdb.Set(ctx, "pipeline:metrics:commands:success", "950", 0)
	suite.rdb.Set(ctx, "pipeline:metrics:commands:failure", "50", 0)

	// Create DLQ entries
	suite.rdb.LPush(ctx, "kafka:dlq:bridge", "msg1", "msg2")
	suite.rdb.LPush(ctx, "kafka:dlq:device-server", "msg3")

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/system/pipeline-metrics", nil)

	suite.handler.GetPipelineMetrics(c)

	suite.Equal(http.StatusOK, w.Code)
	var result map[string]interface{}
	suite.NoError(json.Unmarshal(w.Body.Bytes(), &result))

	// Verify DLQ count
	dlqPending, ok := result["dlq_pending"].(float64)
	suite.True(ok)
	suite.Equal(float64(3), dlqPending) // 2 from bridge + 1 from device-server

	// Verify command success rate
	successRate, ok := result["command_success_rate"].(float64)
	suite.True(ok)
	suite.Equal(float64(95.0), successRate) // 950/(950+50)*100
}

// TestPipelineHealth_PingRedis tests Redis ping functionality
func (suite *PipelineHealthHandlerTestSuite) TestPipelineHealth_PingRedis() {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/system/health/ping-redis", nil)

	suite.handler.PingRedis(c)

	suite.Equal(http.StatusOK, w.Code)
	var result map[string]interface{}
	suite.NoError(json.Unmarshal(w.Body.Bytes(), &result))

	status, ok := result["status"].(string)
	suite.True(ok)
	suite.Equal("pong", status)
}

// TestPipelineHealthServiceCheck tests the internal checkServiceHealth method
func (suite *PipelineHealthHandlerTestSuite) TestPipelineHealthServiceCheck() {
	ctx := context.Background()

	tests := []struct {
		name           string
		setupValue     string
		expectedStatus string
	}{
		{"HealthyService", "ok", "ok"},
		{"DegradedService", "degraded", "degraded"},
		{"DownService", "down", "down"},
		{"MissingService", "", "down"},
		{"InvalidStatus", "unknown", "degraded"},
	}

	for _, tt := range tests {
		suite.T().Run(tt.name, func(t *testing.T) {
			key := "test:health:key"
			if tt.setupValue != "" {
				suite.rdb.Set(ctx, key, tt.setupValue, 0)
			}

			result := suite.handler.checkServiceHealth(ctx, "test-service", "test-type", key)
		
			assert.Equal(suite.T(), tt.expectedStatus, result.Status)
			assert.Equal(suite.T(), "test-service", result.ServiceName)
			assert.Equal(suite.T(), "test-type", result.ServiceType)
			assert.WithinDuration(suite.T(), time.Now(), result.LastCheckTime, 2*time.Second)
		})
	}
}

// TestPipelineHealthResponseStructure tests the structure of responses
func (suite *PipelineHealthHandlerTestSuite) TestPipelineHealthResponseStructure() {
	ctx := context.Background()

	// Set all services healthy
	suite.rdb.Set(ctx, "pipeline:health:bridge", "ok", 0)
	suite.rdb.Set(ctx, "pipeline:health:device-server", "ok", 0)
	suite.rdb.Set(ctx, "pipeline:health:api", "ok", 0)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/system/pipeline-health", nil)

	suite.handler.GetPipelineHealth(c)

	suite.Equal(http.StatusOK, w.Code)
	
	var result PipelineHealthResponse
	suite.NoError(json.Unmarshal(w.Body.Bytes(), &result))

	// Verify required fields are present
	suite.Equal("ok", result.OverallStatus)
	suite.NotZero(result.CheckTime)
	suite.Len(result.ServiceStatuses, 3)

	// Verify each service has required fields
	for _, status := range result.ServiceStatuses {
		suite.NotEmpty(status.ServiceName)
		suite.NotEmpty(status.ServiceType)
		suite.Contains([]string{"ok", "degraded", "down"}, status.Status)
		suite.NotZero(status.LastCheckTime)
	}
}

// TestPipelineHealth_ConcurrentAccess tests concurrent access safety
func (suite *PipelineHealthHandlerTestSuite) TestPipelineHealth_ConcurrentAccess() {
	ctx := context.Background()
	suite.rdb.Set(ctx, "pipeline:health:bridge", "ok", 0)
	suite.rdb.Set(ctx, "pipeline:health:device-server", "degraded", 0)
	suite.rdb.Set(ctx, "pipeline:health:api", "ok", 0)

	// Run concurrent requests
	done := make(chan bool, 10)
	for i := 0; i < 10; i++ {
		go func() {
			w := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(w)
			c.Request = httptest.NewRequest("GET", "/api/v1/system/pipeline-health", nil)
			suite.handler.GetPipelineHealth(c)
			done <- true
		}()
	}

	// Wait for all goroutines to complete
	for i := 0; i < 10; i++ {
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			suite.T().Fatalf("Concurrent test timeout")
		}
	}
}

// Run the test suite
func TestPipelineHealthHandlerTestSuite(t *testing.T) {
	suite.Run(t, new(PipelineHealthHandlerTestSuite))
}

// Additional standalone tests
func TestPipelineHealth_StandaloneTests(t *testing.T) {
	t.Run("GetOnlineDeviceCount_Empty", func(t *testing.T) {
		s, err := miniredis.Run()
		assert.NoError(t, err)
		defer s.Close()

		rdb := redis.NewClient(&redis.Options{Addr: s.Addr()})
		defer rdb.Close()

		handler := NewPipelineHealthHandler(rdb)
		
		count, err := handler.getOnlineDeviceCount(context.Background())
		assert.NoError(t, err)
		assert.Equal(t, 0, count)
	})

	t.Run("GetDLQPendingCount_MultipleConsumers", func(t *testing.T) {
		s, err := miniredis.Run()
		assert.NoError(t, err)
		defer s.Close()

		rdb := redis.NewClient(&redis.Options{Addr: s.Addr()})
		defer rdb.Close()

		handler := NewPipelineHealthHandler(rdb)
		
		// Add messages to different DLQs
		rdb.LPush(context.Background(), "kafka:dlq:bridge", "msg1", "msg2", "msg3")
		rdb.LPush(context.Background(), "kafka:dlq:device-server", "msg4")
		rdb.LPush(context.Background(), "kafka:dlq:api", "msg5", "msg6")

		count := handler.getDLQPendingCount(context.Background())
		assert.Equal(t, 6, count)
	})

	t.Run("GetAverageKafkaLag_NoData", func(t *testing.T) {
		s, err := miniredis.Run()
		assert.NoError(t, err)
		defer s.Close()

		rdb := redis.NewClient(&redis.Options{Addr: s.Addr()})
		defer rdb.Close()

		handler := NewPipelineHealthHandler(rdb)
		
		lag := handler.getAverageKafkaLag(context.Background())
		assert.Equal(t, 0.0, lag)
	})

	t.Run("GetAverageKafkaLag_WithData", func(t *testing.T) {
		s, err := miniredis.Run()
		assert.NoError(t, err)
		defer s.Close()

		rdb := redis.NewClient(&redis.Options{Addr: s.Addr()})
		defer rdb.Close()

		handler := NewPipelineHealthHandler(rdb)
		
		rdb.Set(context.Background(), "kafka:lag:consumer1", "10", 0)
		rdb.Set(context.Background(), "kafka:lag:consumer2", "20", 0)
		rdb.Set(context.Background(), "kafka:lag:consumer3", "30", 0)

		lag := handler.getAverageKafkaLag(context.Background())
		assert.Equal(t, float64(20), lag) // (10+20+30)/3
	})
}
