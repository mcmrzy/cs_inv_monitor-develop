package handler

import (
	"context"
	"encoding/json"
	"fmt"
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

// DLQHandlerTestSuite tests for DLQHandler
type DLQHandlerTestSuite struct {
	suite.Suite
	rdb     *redis.Client
	s       *miniredis.Miniredis
	handler *DLQHandler
	router  *gin.Engine
}

// SetupSuite runs before all tests in the suite
func (suite *DLQHandlerTestSuite) SetupSuite() {
	// Start a mock Redis server
	s, err := miniredis.Run()
	assert.NoError(suite.T(), err)
	suite.s = s

	// Connect to mock Redis
	suite.rdb = redis.NewClient(&redis.Options{
		Addr: s.Addr(),
	})

	// Create handler
	suite.handler = NewDLQHandler(suite.rdb)

	// Setup Gin router — NOTE: retry-all and clear use query param ?consumer_type=xxx
	// to avoid Gin wildcard conflict between :id and :consumer_type at the same path level.
	gin.SetMode(gin.TestMode)
	suite.router = gin.Default()
	suite.router.GET("/api/v1/system/dlq", suite.handler.List)
	suite.router.POST("/api/v1/system/dlq/:id/retry", suite.handler.Retry)
	suite.router.DELETE("/api/v1/system/dlq/:id", suite.handler.Delete)
	suite.router.POST("/api/v1/system/dlq/retry-all", suite.handler.RetryAll)
	suite.router.DELETE("/api/v1/system/dlq/clear", suite.handler.Clear)
	suite.router.GET("/api/v1/system/dlq/stats", suite.handler.Stats)
}

// TearDownSuite runs after all tests in the suite
func (suite *DLQHandlerTestSuite) TearDownSuite() {
	if suite.s != nil {
		suite.s.Close()
	}
	if suite.rdb != nil {
		suite.rdb.Close()
	}
}

// SetupTest runs before each test
func (suite *DLQHandlerTestSuite) SetupTest() {
	// Clear all DLQ keys before each test
	ctx := context.Background()
	suite.rdb.Del(ctx, "kafka:dlq:bridge")
	suite.rdb.Del(ctx, "kafka:dlq:device-server")
	suite.rdb.Del(ctx, "kafka:dlq:api")
	suite.rdb.Del(ctx, "kafka:topic:test-topic")
}

// TestDLQHandler_List tests listing DLQ messages with pagination
func (suite *DLQHandlerTestSuite) TestDLQHandler_List() {
	ctx := context.Background()

	// Create mock DLQ data
	messages := []DLQMessage{
		{
			ID:            "bridge-0",
			ConsumerType:  "bridge",
			OriginalTopic: "test-topic",
			Key:           "device-123",
			Value:         map[string]interface{}{"data": "value1"},
			ErrorMessage:  "processing failed",
			FailedAt:      time.Now(),
			RetryCount:    0,
		},
		{
			ID:            "bridge-1",
			ConsumerType:  "bridge",
			OriginalTopic: "test-topic",
			Key:           "device-456",
			Value:         map[string]interface{}{"data": "value2"},
			ErrorMessage:  "timeout error",
			FailedAt:      time.Now(),
			RetryCount:    1,
		},
		{
			ID:            "device-server-0",
			ConsumerType:  "device-server",
			OriginalTopic: "device-events",
			Key:           "device-789",
			Value:         map[string]interface{}{"data": "value3"},
			ErrorMessage:  "validation error",
			FailedAt:      time.Now(),
			RetryCount:    2,
		},
	}

	// Add messages to DLQ
	for _, msg := range messages {
		msgJSON, _ := json.Marshal(msg)
		suite.rdb.RPush(ctx, fmt.Sprintf("kafka:dlq:%s", msg.ConsumerType), string(msgJSON))
	}

	// Test default pagination (page=1, size=20)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/system/dlq", nil)

	suite.handler.List(c)

	suite.Equal(http.StatusOK, w.Code)
	result := extractData(suite.T(), w.Body.Bytes())

	// Verify total count
	total, ok := result["total"].(float64)
	suite.True(ok)
	suite.Equal(float64(3), total)

	// Verify pagination
	page, ok := result["page"].(float64)
	suite.True(ok)
	suite.Equal(float64(1), page)

	size, ok := result["size"].(float64)
	suite.True(ok)
	suite.Equal(float64(20), size)

	// Verify items
	items, ok := result["items"].([]interface{})
	suite.True(ok)
	suite.Len(items, 3)

	// Test custom pagination
	w = httptest.NewRecorder()
	c, _ = gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/system/dlq?page=1&size=2", nil)

	suite.handler.List(c)

	suite.Equal(http.StatusOK, w.Code)
	result = extractData(suite.T(), w.Body.Bytes())

	total, ok = result["total"].(float64)
	suite.True(ok)
	suite.Equal(float64(3), total)

	totalPages, ok := result["total_pages"].(float64)
	suite.True(ok)
	suite.Equal(float64(2), totalPages)

	items, ok = result["items"].([]interface{})
	suite.True(ok)
	suite.Len(items, 2) // Only 2 items on first page

	// Test filter by consumer type
	w = httptest.NewRecorder()
	c, _ = gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/system/dlq?consumer_type=device-server", nil)

	suite.handler.List(c)

	suite.Equal(http.StatusOK, w.Code)
	result = extractData(suite.T(), w.Body.Bytes())

	total, ok = result["total"].(float64)
	suite.True(ok)
	suite.Equal(float64(1), total) // Only 1 device-server message
}

// TestDLQHandler_List_Empty tests listing when DLQ is empty
func (suite *DLQHandlerTestSuite) TestDLQHandler_List_Empty() {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/system/dlq", nil)

	suite.handler.List(c)

	suite.Equal(http.StatusOK, w.Code)
	result := extractData(suite.T(), w.Body.Bytes())

	total, ok := result["total"].(float64)
	suite.True(ok)
	suite.Equal(float64(0), total)

	// items may be null (nil slice in Go -> JSON null) or empty array — both mean 0 items
	items, ok := result["items"].([]interface{})
	if ok {
		suite.Len(items, 0)
	}
}

// TestDLQHandler_Retry tests retrying a DLQ message
func (suite *DLQHandlerTestSuite) TestDLQHandler_Retry() {
	ctx := context.Background()

	// Create a mock DLQ message
	msg := DLQMessage{
		ID:            "bridge-0",
		ConsumerType:  "bridge",
		OriginalTopic: "test-topic",
		Key:           "device-123",
		Value:         map[string]interface{}{"data": "value1"},
		ErrorMessage:  "processing failed",
		FailedAt:      time.Now(),
		RetryCount:    0,
	}

	msgJSON, _ := json.Marshal(msg)
	suite.rdb.RPush(ctx, "kafka:dlq:bridge", string(msgJSON))

	// Retry the message
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("POST", "/api/v1/system/dlq/bridge-0/retry", nil)
	c.Params = gin.Params{{Key: "id", Value: "bridge-0"}}

	suite.handler.Retry(c)

	suite.Equal(http.StatusOK, w.Code)
	result := extractData(suite.T(), w.Body.Bytes())

	// Verify success message
	message, ok := result["message"].(string)
	suite.True(ok)
	suite.Equal("Message re-enqueued for retry", message)

	// Verify message was removed from DLQ
	dlqCount, _ := suite.rdb.LLen(ctx, "kafka:dlq:bridge").Result()
	suite.Equal(int64(0), dlqCount)

	// Verify message was added to original topic
	topicCount, _ := suite.rdb.LLen(ctx, "kafka:topic:test-topic").Result()
	suite.Equal(int64(1), topicCount)

	// Verify retry count was incremented
	topicMsg, _ := suite.rdb.LIndex(ctx, "kafka:topic:test-topic", 0).Result()
	var retriedMsg DLQMessage
	suite.NoError(json.Unmarshal([]byte(topicMsg), &retriedMsg))
	suite.Equal(1, retriedMsg.RetryCount)
}

// TestDLQHandler_Retry_NotFound tests retrying a non-existent message
func (suite *DLQHandlerTestSuite) TestDLQHandler_Retry_NotFound() {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("POST", "/api/v1/system/dlq/bridge-999/retry", nil)
	c.Params = gin.Params{{Key: "id", Value: "bridge-999"}}

	suite.handler.Retry(c)

	suite.Equal(http.StatusNotFound, w.Code)
}

// TestDLQHandler_Retry_InvalidID tests retrying with invalid message ID
func (suite *DLQHandlerTestSuite) TestDLQHandler_Retry_InvalidID() {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("POST", "/api/v1/system/dlq/invalid-id/retry", nil)
	c.Params = gin.Params{{Key: "id", Value: "invalid-id"}}

	suite.handler.Retry(c)

	suite.Equal(http.StatusBadRequest, w.Code)
}

// TestDLQHandler_Delete tests deleting a DLQ message
func (suite *DLQHandlerTestSuite) TestDLQHandler_Delete() {
	ctx := context.Background()

	// Create mock DLQ messages
	msg1 := DLQMessage{
		ID:           "bridge-0",
		ConsumerType: "bridge",
		Value:        map[string]interface{}{"data": "value1"},
		ErrorMessage: "error1",
	}
	msg2 := DLQMessage{
		ID:           "bridge-1",
		ConsumerType: "bridge",
		Value:        map[string]interface{}{"data": "value2"},
		ErrorMessage: "error2",
	}

	msg1JSON, _ := json.Marshal(msg1)
	msg2JSON, _ := json.Marshal(msg2)
	suite.rdb.RPush(ctx, "kafka:dlq:bridge", string(msg1JSON), string(msg2JSON))

	// Delete first message
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("DELETE", "/api/v1/system/dlq/bridge-0", nil)
	c.Params = gin.Params{{Key: "id", Value: "bridge-0"}}

	suite.handler.Delete(c)

	suite.Equal(http.StatusOK, w.Code)

	// Verify message was removed
	dlqCount, _ := suite.rdb.LLen(ctx, "kafka:dlq:bridge").Result()
	suite.Equal(int64(1), dlqCount) // Only msg2 remains

	// Verify correct message remains
	remainingMsg, _ := suite.rdb.LIndex(ctx, "kafka:dlq:bridge", 0).Result()
	var remaining DLQMessage
	suite.NoError(json.Unmarshal([]byte(remainingMsg), &remaining))
	suite.Equal("bridge-1", remaining.ID)
}

// TestDLQHandler_RetryAll tests bulk retry of all messages
func (suite *DLQHandlerTestSuite) TestDLQHandler_RetryAll() {
	ctx := context.Background()

	// Create multiple DLQ messages
	for i := 0; i < 3; i++ {
		msg := DLQMessage{
			ID:            fmt.Sprintf("bridge-%d", i),
			ConsumerType:  "bridge",
			OriginalTopic: "test-topic",
			Value:         map[string]interface{}{"data": fmt.Sprintf("value%d", i)},
			ErrorMessage:  fmt.Sprintf("error%d", i),
		}
		msgJSON, _ := json.Marshal(msg)
		suite.rdb.RPush(ctx, "kafka:dlq:bridge", string(msgJSON))
	}

	// Retry all messages via query param
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("POST", "/api/v1/system/dlq/retry-all?consumer_type=bridge", nil)

	suite.handler.RetryAll(c)

	suite.Equal(http.StatusOK, w.Code)
	result := extractData(suite.T(), w.Body.Bytes())

	successCount, ok := result["success_count"].(float64)
	suite.True(ok)
	suite.Equal(float64(3), successCount)

	// Verify DLQ is empty
	dlqCount, _ := suite.rdb.LLen(ctx, "kafka:dlq:bridge").Result()
	suite.Equal(int64(0), dlqCount)

	// Verify all messages moved to topic
	topicCount, _ := suite.rdb.LLen(ctx, "kafka:topic:test-topic").Result()
	suite.Equal(int64(3), topicCount)
}

// TestDLQHandler_Clear tests clearing all DLQ messages
func (suite *DLQHandlerTestSuite) TestDLQHandler_Clear() {
	ctx := context.Background()

	// Create mock DLQ messages
	for i := 0; i < 5; i++ {
		msg := DLQMessage{
			ID:           fmt.Sprintf("bridge-%d", i),
			ConsumerType: "bridge",
			Value:        fmt.Sprintf("value%d", i),
		}
		msgJSON, _ := json.Marshal(msg)
		suite.rdb.RPush(ctx, "kafka:dlq:bridge", string(msgJSON))
	}

	// Clear DLQ via query param
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("DELETE", "/api/v1/system/dlq/clear?consumer_type=bridge", nil)

	suite.handler.Clear(c)

	suite.Equal(http.StatusOK, w.Code)

	// Verify DLQ is empty
	dlqCount, _ := suite.rdb.LLen(ctx, "kafka:dlq:bridge").Result()
	suite.Equal(int64(0), dlqCount)
}

// TestDLQHandler_Stats tests DLQ statistics
func (suite *DLQHandlerTestSuite) TestDLQHandler_Stats() {
	ctx := context.Background()

	// Add messages to different consumer DLQs
	for i := 0; i < 3; i++ {
		msg := DLQMessage{ID: fmt.Sprintf("bridge-%d", i), Value: "data"}
		msgJSON, _ := json.Marshal(msg)
		suite.rdb.RPush(ctx, "kafka:dlq:bridge", string(msgJSON))
	}

	for i := 0; i < 2; i++ {
		msg := DLQMessage{ID: fmt.Sprintf("device-server-%d", i), Value: "data"}
		msgJSON, _ := json.Marshal(msg)
		suite.rdb.RPush(ctx, "kafka:dlq:device-server", string(msgJSON))
	}

	// Get stats
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/system/dlq/stats", nil)

	suite.handler.Stats(c)

	suite.Equal(http.StatusOK, w.Code)
	result := extractData(suite.T(), w.Body.Bytes())

	byConsumer, ok := result["by_consumer"].(map[string]interface{})
	suite.True(ok)

	bridgeCount, ok := byConsumer["bridge"].(float64)
	suite.True(ok)
	suite.Equal(float64(3), bridgeCount)

	deviceServerCount, ok := byConsumer["device-server"].(float64)
	suite.True(ok)
	suite.Equal(float64(2), deviceServerCount)

	total, ok := result["total"].(float64)
	suite.True(ok)
	suite.Equal(float64(5), total)
}

// TestParseMessageID tests the parseMessageID helper function
func TestParseMessageID(t *testing.T) {
	tests := []struct {
		name         string
		id           string
		expectedType string
		expectedIdx  int64
		expectError  bool
	}{
		{"ValidID", "bridge-0", "bridge", 0, false},
		{"ValidIDWithIndex", "device-server-42", "device-server", 42, false},
		{"ValidIDLargeIndex", "api-999", "api", 999, false},
		{"InvalidFormat", "invalid", "", 0, true},
		{"InvalidIndex", "bridge-abc", "", 0, true},
		{"EmptyID", "", "", 0, true},
		{"OnlyHyphen", "-", "", 0, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			consumerType, index, err := parseMessageID(tt.id)
			
			if tt.expectError {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.expectedType, consumerType)
				assert.Equal(t, tt.expectedIdx, index)
			}
		})
	}
}

// Run the test suite
func TestDLQHandlerTestSuite(t *testing.T) {
	suite.Run(t, new(DLQHandlerTestSuite))
}
