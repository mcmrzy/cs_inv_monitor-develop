package middleware

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"sync"
	"time"

	"inv-api-server/internal/job"
	"inv-api-server/pkg/logger"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// WebSocketProgressHandler manages real-time job progress updates
type WebSocketProgressHandler struct {
	jobStore    *job.JobStore
	rdb         *redis.Client
	upgrader    websocket.Upgrader
	connections map[string]map[string]*websocket.Conn // jobID -> userID -> connection
	connMux     sync.RWMutex
}

// NewWebSocketProgressHandler creates a new WebSocket progress handler
func NewWebSocketProgressHandler(jobStore *job.JobStore, rdb *redis.Client) *WebSocketProgressHandler {
	return &WebSocketProgressHandler{
		jobStore: jobStore,
		rdb:      rdb,
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				return true // Allow all origins for now
			},
			HandshakeTimeout: 45 * time.Second,
		},
		connections: make(map[string]map[string]*websocket.Conn),
	}
}

// HandleWebSocketProgress handles WebSocket connections for job progress
func (h *WebSocketProgressHandler) HandleWebSocketProgress(c *gin.Context) {
	jobID := c.Param("jobId")
	userIDStr := c.Query("user_id")

	if jobID == "" || userIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job_id and user_id required"})
		return
	}

	userID, err := strconv.ParseInt(userIDStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user_id"})
		return
	}

	// Verify user owns the job (or has permission)
	ctx := c.Request.Context()
	job, err := h.jobStore.GetJob(ctx, jobID)
	if err != nil || job == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "job not found"})
		return
	}

	// Check if user has access to this job
	if job.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "access denied to job"})
		return
	}

	// Upgrade HTTP to WebSocket
	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		logger.Error("WebSocket upgrade failed", zap.String("job_id", jobID), zap.Error(err))
		return
	}
	defer conn.Close()

	// Register connection
	h.registerConnection(jobID, userID, conn)
	defer h.unregisterConnection(jobID, userID)

	logger.Info("WebSocket client connected",
		zap.String("job_id", jobID),
		zap.Int64("user_id", userID))

	// Send initial job status
	initialMsg := map[string]interface{}{
		"type": "status",
		"data": map[string]interface{}{
			"job_id":    job.JobID,
			"job_type":  job.Type,
			"status":    job.Status,
			"total":     job.TotalItems,
			"progress":  job.Progress,
			"created_at": job.CreatedAt.Unix(),
			"updated_at": job.UpdatedAt.Unix(),
		},
	}

	if err := conn.WriteJSON(initialMsg); err != nil {
		logger.Error("Failed to send initial status", zap.Error(err))
		return
	}

	// Start monitoring job progress
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	progressChan := h.jobStore.SubscribeToJobProgress(ctx, jobID)
	defer cancel() // Ensure channel cleanup

	// Send progress updates to client
	for {
		select {
		case msg, ok := <-progressChan:
			if !ok {
				return // Channel closed
			}

			// Set write deadline
			conn.SetWriteDeadline(time.Now().Add(10 * time.Second))

			if err := conn.WriteMessage(websocket.TextMessage, []byte(msg)); err != nil {
				logger.Warn("WebSocket write failed", zap.String("job_id", jobID), zap.Error(err))
				return
			}

			// Parse message to check completion
			var progressData struct {
				JobID  string `json:"job_id"`
				Status string `json:"status"`
			}
			if json.Unmarshal([]byte(msg), &progressData) == nil {
				if progressData.Status == "completed" || progressData.Status == "failed" {
					// Send completion message
					completeMsg := map[string]interface{}{
						"type": "complete",
						"data": progressData,
					}
					conn.WriteJSON(completeMsg)
					return // Exit after job complete
				}
			}

		case <-time.After(5 * time.Minute):
			// Timeout - stop streaming
			logger.Info("WebSocket timeout reached", zap.String("job_id", jobID))
			return
		}
	}
}

// HandleProgressSSE handles Server-Sent Events for job progress
func (h *WebSocketProgressHandler) HandleProgressSSE(c *gin.Context) {
	jobID := c.Param("jobId")
	userIDStr := c.Query("user_id")

	if jobID == "" || userIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job_id and user_id required"})
		return
	}

	userID, err := strconv.ParseInt(userIDStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user_id"})
		return
	}

	// Verify user owns the job
	ctx := c.Request.Context()
	job, err := h.jobStore.GetJob(ctx, jobID)
	if err != nil || job == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "job not found"})
		return
	}

	if job.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
		return
	}

	// Set SSE headers
	c.Header("Content-Type", "text/event-stream")
	c.Header("Cache-Control", "no-cache")
	c.Header("Connection", "keep-alive")
	c.Header("X-Accel-Buffering", "no") // For nginx proxy

	c.Writer.Flush()

	// Send initial status
	h.sendSSEEvent(c, "status", map[string]interface{}{
		"job_id":    job.JobID,
		"job_type":  job.Type,
		"status":    job.Status,
		"total":     job.TotalItems,
		"progress":  job.Progress,
	})

	// Subscribe to progress updates
	ctx, cancel := context.WithCancel(c.Request.Context())
	defer cancel()

	progressChan := h.jobStore.SubscribeToJobProgress(ctx, jobID)

	for {
		select {
		case <-c.Request.Context().Done():
			return
		case msg, ok := <-progressChan:
			if !ok {
				return
			}

			var progressData struct {
				JobID  string `json:"job_id"`
				Status string `json:"status"`
			}
			if json.Unmarshal([]byte(msg), &progressData) == nil {
				h.sendSSEEvent(c, "progress", map[string]interface{}{
					"job_id": progressData.JobID,
					"status": progressData.Status,
				})
			}

			// Check if job completed
			if progressData.Status == "completed" || progressData.Status == "failed" {
				h.sendSSEEvent(c, "complete", map[string]interface{}{
					"job_id": progressData.JobID,
					"status": progressData.Status,
				})
				return
			}
		}
	}
}

// sendSSEEvent sends a single SSE event to the client
func (h *WebSocketProgressHandler) sendSSEEvent(c *gin.Context, eventType string, data interface{}) {
	jsonData, _ := json.Marshal(data)
	event := fmt.Sprintf("event: %s\ndata: %s\n\n", eventType, string(jsonData))
	c.Writer.WriteString(event)
	c.Writer.(http.Flusher).Flush()
}

// registerConnection adds a WebSocket connection to the registry
func (h *WebSocketProgressHandler) registerConnection(jobID string, userID int64, conn *websocket.Conn) {
	h.connMux.Lock()
	defer h.connMux.Unlock()

	if _, exists := h.connections[jobID]; !exists {
		h.connections[jobID] = make(map[string]*websocket.Conn)
	}

	userIDStr := strconv.FormatInt(userID, 10)
	h.connections[jobID][userIDStr] = conn
}

// unregisterConnection removes a WebSocket connection from registry
func (h *WebSocketProgressHandler) unregisterConnection(jobID string, userID int64) {
	h.connMux.Lock()
	defer h.connMux.Unlock()

	if conns, exists := h.connections[jobID]; exists {
		userIDStr := strconv.FormatInt(userID, 10)
		delete(conns, userIDStr)

		if len(conns) == 0 {
			delete(h.connections, jobID)
		}
	}
}

// broadcastProgress broadcasts progress update to all connected clients for a job
func (h *WebSocketProgressHandler) broadcastProgress(jobID string, progress int, status string) {
	h.connMux.RLock()
	defer h.connMux.RUnlock()

	conns, exists := h.connections[jobID]
	if !exists {
		return
	}

	msg := map[string]interface{}{
		"type": "progress",
		"data": map[string]interface{}{
			"job_id":   jobID,
			"progress": progress,
			"status":   status,
		},
	}

	for _, conn := range conns {
		conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
		if err := conn.WriteJSON(msg); err != nil {
			logger.Warn("Failed to broadcast progress",
				zap.String("job_id", jobID),
				zap.Error(err))
		}
	}
}

// BroadcastJobStatus broadcasts a job status update (completion/failure)
func (h *WebSocketProgressHandler) BroadcastJobStatus(jobID string, status string, errorMessage string) {
	h.connMux.RLock()
	defer h.connMux.RUnlock()

	conns, exists := h.connections[jobID]
	if !exists {
		return
	}

	msg := map[string]interface{}{
		"type": "complete",
		"data": map[string]interface{}{
			"job_id":         jobID,
			"status":         status,
			"error_message":  errorMessage,
		},
	}

	for _, conn := range conns {
		conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
		if err := conn.WriteJSON(msg); err != nil {
			logger.Warn("Failed to broadcast status",
				zap.String("job_id", jobID),
				zap.Error(err))
		}
	}

	// Remove connection registry entry for completed jobs
	if status == "completed" || status == "failed" {
		h.connMux.Lock()
		delete(h.connections, jobID)
		h.connMux.Unlock()
	}
}

// Cleanup removes all WebSocket connections
func (h *WebSocketProgressHandler) Cleanup() {
	h.connMux.Lock()
	defer h.connMux.Unlock()

	for _, conns := range h.connections {
		for userID, conn := range conns {
			conn.WriteControl(websocket.CloseMessage,
				websocket.FormatCloseMessage(websocket.CloseGoingAway, "server shutdown"),
				time.Now().Add(5*time.Second))
			logger.Debug("WebSocket connection closed during cleanup", zap.String("user_id", userID))
		}
	}

	h.connections = make(map[string]map[string]*websocket.Conn)
}

