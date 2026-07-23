package handler

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

// DLQMessage represents a dead letter queue message
type DLQMessage struct {
	ID            string                 `json:"id"`
	ConsumerType  string                 `json:"consumer_type"` // bridge, device-server, api
	OriginalTopic string                 `json:"original_topic"`
	Key           string                 `json:"key"`
	Value         interface{}            `json:"value"`
	ErrorMessage  string                 `json:"error_message"`
	FailedAt      time.Time              `json:"failed_at"`
	RetryCount    int                    `json:"retry_count"`
	Metadata      map[string]interface{} `json:"metadata,omitempty"`
}

// DLQListResponse is the paginated response for DLQ list
type DLQListResponse struct {
	Items      []DLQMessage `json:"items"`
	Total      int          `json:"total"`
	Page       int          `json:"page"`
	Size       int          `json:"size"`
	TotalPages int          `json:"total_pages"`
}

// DLQHandler manages dead letter queue operations
type DLQHandler struct {
	rdb *redis.Client
}

// NewDLQHandler creates a new DLQHandler instance
func NewDLQHandler(rdb *redis.Client) *DLQHandler {
	return &DLQHandler{
		rdb: rdb,
	}
}

// List returns paginated list of DLQ messages
// @Summary List DLQ messages
// @Description Get paginated list of dead letter queue messages
// @Tags DLQ Management
// @Param page query int false "Page number (default: 1)"
// @Param size query int false "Page size (default: 20)"
// @Param consumer_type query string false "Filter by consumer type"
// @Router /api/v1/system/dlq [get]
func (h *DLQHandler) List(c *gin.Context) {
	ctx := c.Request.Context()

	// Parse pagination parameters
	pageStr := c.DefaultQuery("page", "1")
	sizeStr := c.DefaultQuery("size", "20")
	consumerType := c.Query("consumer_type")

	page, err := strconv.Atoi(pageStr)
	if err != nil || page < 1 {
		page = 1
	}
	size, err := strconv.Atoi(sizeStr)
	if err != nil || size < 1 || size > 100 {
		size = 20
	}

	// Get all consumer types or filter by specific type
	consumerTypes := []string{"bridge", "device-server", "api"}
	if consumerType != "" {
		consumerTypes = []string{consumerType}
	}

	var allMessages []DLQMessage

	// Collect messages from all specified consumer types
	for _, ct := range consumerTypes {
		key := fmt.Sprintf("kafka:dlq:%s", ct)
		
		// Get messages using LRANGE
		messages, err := h.rdb.LRange(ctx, key, 0, -1).Result()
		if err != nil {
			continue
		}

		// Parse each message
		for i, msgJSON := range messages {
			var msg DLQMessage
			if err := json.Unmarshal([]byte(msgJSON), &msg); err != nil {
				// If JSON parsing fails, create a basic message
				msg = DLQMessage{
					ID:           fmt.Sprintf("%s-%d", ct, i),
					ConsumerType: ct,
					Value:        msgJSON,
					FailedAt:     time.Now(),
				}
			}
			msg.ConsumerType = ct
			if msg.ID == "" {
				msg.ID = fmt.Sprintf("%s-%d", ct, i)
			}
			allMessages = append(allMessages, msg)
		}
	}

	// Calculate pagination
	total := len(allMessages)
	totalPages := (total + size - 1) / size
	if totalPages == 0 {
		totalPages = 1
	}

	start := (page - 1) * size
	end := start + size
	if start > total {
		start = total
	}
	if end > total {
		end = total
	}

	pagedMessages := allMessages[start:end]

	response.Success(c, DLQListResponse{
		Items:      pagedMessages,
		Total:      total,
		Page:       page,
		Size:       size,
		TotalPages: totalPages,
	})
}

// Retry moves a DLQ message back to the original topic for reprocessing
// @Summary Retry DLQ message
// @Description Pop message from DLQ and re-enqueue to original topic
// @Tags DLQ Management
// @Param id path string true "DLQ message ID"
// @Router /api/v1/system/dlq/messages/:id/retry [post]
func (h *DLQHandler) Retry(c *gin.Context) {
	ctx := c.Request.Context()
	messageID := c.Param("id")

	// Parse message ID to get consumer type and index
	consumerType, index, err := parseMessageID(messageID)
	if err != nil {
		response.BadRequest(c, "Invalid message ID")
		return
	}

	key := fmt.Sprintf("kafka:dlq:%s", consumerType)

	// Get the message at the specified index
	messages, err := h.rdb.LRange(ctx, key, index, index).Result()
	if err != nil || len(messages) == 0 {
		response.NotFound(c, "Message not found")
		return
	}

	msgJSON := messages[0]

	// Parse the message to get original topic
	var msg DLQMessage
	if err := json.Unmarshal([]byte(msgJSON), &msg); err != nil {
		response.BadRequest(c, "Failed to parse message")
		return
	}

	if msg.OriginalTopic == "" {
		response.BadRequest(c, "Original topic not specified")
		return
	}

	// Remove from DLQ
	_, err = h.rdb.LRem(ctx, key, 1, msgJSON).Result()
	if err != nil {
		response.InternalError(c, "Failed to remove from DLQ")
		return
	}

	// Re-enqueue to original topic
	// In production, this would publish to Kafka topic
	// For now, we use Redis as a simple queue simulation
	originalKey := fmt.Sprintf("kafka:topic:%s", msg.OriginalTopic)
	
	// Prepare the message for re-enqueue (increment retry count)
	msg.RetryCount++
	retryJSON, err := json.Marshal(msg)
	if err != nil {
		response.InternalError(c, "Failed to serialize message")
		return
	}

	err = h.rdb.RPush(ctx, originalKey, string(retryJSON)).Err()
	if err != nil {
		response.InternalError(c, "Failed to re-enqueue message")
		return
	}

	response.Success(c, gin.H{
		"message": "Message re-enqueued for retry",
		"id":      messageID,
		"topic":   msg.OriginalTopic,
	})
}

// Delete removes a specific DLQ message
// @Summary Delete DLQ message
// @Description Remove specific DLQ entry
// @Tags DLQ Management
// @Param id path string true "DLQ message ID"
// @Router /api/v1/system/dlq/messages/:id [delete]
func (h *DLQHandler) Delete(c *gin.Context) {
	ctx := c.Request.Context()
	messageID := c.Param("id")

	// Parse message ID to get consumer type and index
	consumerType, index, err := parseMessageID(messageID)
	if err != nil {
		response.BadRequest(c, "Invalid message ID")
		return
	}

	key := fmt.Sprintf("kafka:dlq:%s", consumerType)

	// Get the message at the specified index
	messages, err := h.rdb.LRange(ctx, key, index, index).Result()
	if err != nil || len(messages) == 0 {
		response.NotFound(c, "Message not found")
		return
	}

	// Remove the message from DLQ
	_, err = h.rdb.LRem(ctx, key, 1, messages[0]).Result()
	if err != nil {
		response.InternalError(c, "Failed to delete message")
		return
	}

	response.Success(c, gin.H{
		"message": "DLQ message deleted",
		"id":      messageID,
	})
}

// parseMessageID extracts consumer type and index from message ID
// Format: {consumer_type}-{index}
func parseMessageID(id string) (consumerType string, index int64, err error) {
	lastDash := strings.LastIndex(id, "-")
	if lastDash < 0 {
		return "", 0, fmt.Errorf("invalid message ID format: %s", id)
	}
	consumerType = id[:lastDash]
	indexStr := id[lastDash+1:]
	index, err = strconv.ParseInt(indexStr, 10, 64)
	if err != nil {
		return "", 0, fmt.Errorf("invalid index in message ID: %s", id)
	}
	return consumerType, index, nil
}

// RetryAll re-enqueues all messages in a specific consumer's DLQ
// This is a bulk operation - use with caution
func (h *DLQHandler) RetryAll(c *gin.Context) {
	ctx := c.Request.Context()
	consumerType := c.Query("consumer_type")

	if consumerType == "" {
		response.BadRequest(c, "Consumer type required")
		return
	}

	key := fmt.Sprintf("kafka:dlq:%s", consumerType)

	// Get all messages
	messages, err := h.rdb.LRange(ctx, key, 0, -1).Result()
	if err != nil {
		response.InternalError(c, "Failed to read DLQ")
		return
	}

	successCount := 0
	failCount := 0

	for _, msgJSON := range messages {
		var msg DLQMessage
		if err := json.Unmarshal([]byte(msgJSON), &msg); err != nil {
			failCount++
			continue
		}

		if msg.OriginalTopic == "" {
			failCount++
			continue
		}

		// Remove from DLQ
		_, err = h.rdb.LRem(ctx, key, 1, msgJSON).Result()
		if err != nil {
			failCount++
			continue
		}

		// Re-enqueue
		originalKey := fmt.Sprintf("kafka:topic:%s", msg.OriginalTopic)
		msg.RetryCount++
		retryJSON, err := json.Marshal(msg)
		if err != nil {
			failCount++
			continue
		}

		err = h.rdb.RPush(ctx, originalKey, string(retryJSON)).Err()
		if err != nil {
			failCount++
			continue
		}

		successCount++
	}

	response.Success(c, gin.H{
		"message":       "Bulk retry completed",
		"success_count": successCount,
		"fail_count":    failCount,
		"total":         len(messages),
	})
}

// Clear removes all messages from a specific consumer's DLQ
// This is a destructive operation - use with caution
func (h *DLQHandler) Clear(c *gin.Context) {
	ctx := c.Request.Context()
	consumerType := c.Query("consumer_type")

	if consumerType == "" {
		response.BadRequest(c, "Consumer type required")
		return
	}

	key := fmt.Sprintf("kafka:dlq:%s", consumerType)

	// Get count before deletion
	count, err := h.rdb.LLen(ctx, key).Result()
	if err != nil {
		response.InternalError(c, "Failed to get DLQ count")
		return
	}

	// Delete the key
	err = h.rdb.Del(ctx, key).Err()
	if err != nil {
		response.InternalError(c, "Failed to clear DLQ")
		return
	}

	response.Success(c, gin.H{
		"message": "DLQ cleared",
		"count":   count,
	})
}

// Stats returns statistics about DLQ messages
func (h *DLQHandler) Stats(c *gin.Context) {
	ctx := c.Request.Context()

	stats := make(map[string]int64)
	consumerTypes := []string{"bridge", "device-server", "api"}

	total := int64(0)
	for _, ct := range consumerTypes {
		key := fmt.Sprintf("kafka:dlq:%s", ct)
		count, err := h.rdb.LLen(ctx, key).Result()
		if err == nil {
			stats[ct] = count
			total += count
		}
	}

	stats["total"] = total

	response.Success(c, gin.H{
		"by_consumer": stats,
		"total":       total,
	})
}
