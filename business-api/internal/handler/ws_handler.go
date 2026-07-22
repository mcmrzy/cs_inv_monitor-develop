package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"sync"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/logger"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

type WSHandler struct {
	rdb              *redis.Client
	jwtService       *service.JWTService
	contextValidator wsAuthorizationContextValidator
	deviceAccess     deviceAccessChecker
	allowedOrigins   map[string]struct{}
	conns            map[string]int
	connsMux         sync.Mutex
}

type wsAuthorizationContextValidator interface {
	ValidateAuthorizationSessionContext(context.Context, model.AuthorizationSessionContext) (bool, error)
}

type deviceAccessChecker interface {
	HasDeviceAccessV2(context.Context, model.ActorContext, string, string) (bool, error)
}

func NewWSHandler(rdb *redis.Client, jwtService *service.JWTService, contextValidator wsAuthorizationContextValidator, deviceAccess deviceAccessChecker, allowedOrigins []string) *WSHandler {
	origins := make(map[string]struct{}, len(allowedOrigins))
	for _, origin := range allowedOrigins {
		origins[origin] = struct{}{}
	}
	return &WSHandler{
		rdb:              rdb,
		jwtService:       jwtService,
		contextValidator: contextValidator,
		deviceAccess:     deviceAccess,
		allowedOrigins:   origins,
		conns:            make(map[string]int),
	}
}

func (h *WSHandler) checkOrigin(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	if _, allowAll := h.allowedOrigins["*"]; allowAll {
		return true
	}
	_, allowed := h.allowedOrigins[origin]
	return allowed
}

func (h *WSHandler) DeviceRealtime(c *gin.Context) {
	sn := c.Param("sn")

	token := c.Query("token")
	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "token required"})
		return
	}

	claims, err := h.jwtService.ParseAccessToken(token)
	if err != nil {
		logger.Warn("WS auth failed", zap.String("sn", sn), zap.Error(err))
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
		return
	}
	if h.contextValidator == nil || h.deviceAccess == nil || h.jwtService.IsBlacklisted(c.Request.Context(), claims.ID) ||
		!h.jwtService.ValidateAccessSession(c.Request.Context(), claims.UserID, claims.SessionID) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authorization context unavailable"})
		return
	}
	sessionContext := model.AuthorizationSessionContext{
		Actor: model.ActorContext{
			UserID: claims.UserID, RootTenantID: claims.RootTenantID,
			OrganizationID: claims.OrganizationID, MembershipID: claims.MembershipID,
			MembershipVersion: claims.MembershipVersion,
		},
		AuthorizationVersion: claims.AuthorizationVersion,
		SessionVersion:       claims.SessionVersion,
	}
	validContext, err := h.contextValidator.ValidateAuthorizationSessionContext(c.Request.Context(), sessionContext)
	if err != nil || !validContext {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authorization context revoked"})
		return
	}
	allowed, err := h.deviceAccess.HasDeviceAccessV2(c.Request.Context(), sessionContext.Actor, "device:view", sn)
	if err != nil || !allowed {
		c.JSON(http.StatusForbidden, gin.H{"error": "device access denied"})
		return
	}

	jti := h.jwtService.GetJTI(claims)
	h.connsMux.Lock()
	if h.conns[jti] >= 5 {
		h.connsMux.Unlock()
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "too many connections"})
		return
	}
	h.conns[jti]++
	h.connsMux.Unlock()

	defer func() {
		h.connsMux.Lock()
		h.conns[jti]--
		if h.conns[jti] <= 0 {
			delete(h.conns, jti)
		}
		h.connsMux.Unlock()
	}()

	upgrader := websocket.Upgrader{CheckOrigin: h.checkOrigin}
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		logger.Error("WS upgrade failed", zap.String("sn", sn), zap.Error(err))
		return
	}
	defer conn.Close()

	logger.Info("WS device connected", zap.String("sn", sn))

	ctx, cancel := context.WithCancel(c.Request.Context())
	defer cancel()

	// 连接建立后，先回填断连期间的历史消息（WebSocket 重连数据回填）
	historyKey := fmt.Sprintf("realtime:history:%s", sn)
	messages, err := h.rdb.LRange(ctx, historyKey, 0, -1).Result()
	if err == nil && len(messages) > 0 {
		// 可选：客户端传入 last_time（Unix秒），只回填该时间之后的数据
		var lastTime int64
		if lt := c.Query("last_time"); lt != "" {
			lastTime, _ = strconv.ParseInt(lt, 10, 64)
		}
		sentCount := 0
		// Redis LPUSH 是后进先出，LRANGE 0 -1 返回最新到最旧，需要反转为时间正序发送
		for i := len(messages) - 1; i >= 0; i-- {
			// 如果客户端传入了 last_time，跳过已收到的旧消息
			if lastTime > 0 {
				var probe struct {
					Timestamp int64 `json:"_timestamp"`
				}
				if json.Unmarshal([]byte(messages[i]), &probe) == nil && probe.Timestamp > 0 && probe.Timestamp <= lastTime {
					continue
				}
			}
			conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.WriteMessage(websocket.TextMessage, []byte(messages[i])); err != nil {
				logger.Warn("WS backfill write failed", zap.String("sn", sn), zap.Error(err))
				return
			}
			sentCount++
		}
		if sentCount > 0 {
			logger.Info("WS backfill sent", zap.String("sn", sn), zap.Int("count", sentCount))
		}
	}

	pubsub := h.rdb.Subscribe(ctx, "realtime:channel:"+sn)
	defer pubsub.Close()

	ch := pubsub.Channel()

	go func() {
		for {
			_, _, err := conn.ReadMessage()
			if err != nil {
				cancel()
				return
			}
		}
	}()

	heartbeatTicker := time.NewTicker(30 * time.Second)
	defer heartbeatTicker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-heartbeatTicker.C:
			if claims.ExpiresAt == nil || time.Now().After(claims.ExpiresAt.Time) || h.jwtService.IsBlacklisted(ctx, claims.ID) ||
				!h.jwtService.ValidateAccessSession(ctx, claims.UserID, claims.SessionID) {
				_ = conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.ClosePolicyViolation, "session expired"), time.Now().Add(time.Second))
				return
			}
			validContext, validateErr := h.contextValidator.ValidateAuthorizationSessionContext(ctx, sessionContext)
			allowed, accessErr := h.deviceAccess.HasDeviceAccessV2(ctx, sessionContext.Actor, "device:view", sn)
			if validateErr != nil || accessErr != nil || !validContext || !allowed {
				_ = conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.ClosePolicyViolation, "authorization revoked"), time.Now().Add(time.Second))
				return
			}
			conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		case msg, ok := <-ch:
			if !ok {
				return
			}
			conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.WriteMessage(websocket.TextMessage, []byte(msg.Payload)); err != nil {
				logger.Warn("WS write failed", zap.String("sn", sn), zap.Error(err))
				return
			}
		}
	}
}

// PipelineHealthSSE provides Server-Sent Events stream for pipeline health updates
// @Summary SSE pipeline health stream
// @Description Real-time pipeline health status updates via SSE
// @Tags System Health
// @Router /api/v1/system/pipeline-health/stream [get]
func PipelineHealthSSE(rdb *redis.Client) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Set SSE headers
		c.Header("Content-Type", "text/event-stream")
		c.Header("Cache-Control", "no-cache")
		c.Header("Connection", "keep-alive")
		c.Header("Access-Control-Allow-Origin", "*")

		ctx := c.Request.Context()
		flusher, ok := c.Writer.(http.Flusher)
		if !ok {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "streaming not supported"})
			return
		}

		logger.Info("SSE pipeline_health stream started")
		defer logger.Info("SSE pipeline_health stream closed")

		// Send initial connection event
		c.Writer.WriteString("event: connected\n")
		c.Writer.WriteString("data: {\"message\": \"SSE pipeline health stream connected\"}\n\n")
		flusher.Flush()

		// Create ticker for periodic updates
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				// Fetch aggregated health data
				healthData := fetchPipelineHealthData(ctx, rdb)
				
				// Convert to JSON
				dataJSON, err := json.Marshal(healthData)
				if err != nil {
					logger.Error("Failed to marshal health data", zap.Error(err))
					continue
				}

				// Send SSE event
				c.Writer.WriteString("event: pipeline_health\n")
				c.Writer.WriteString(fmt.Sprintf("data: %s\n\n", dataJSON))
				flusher.Flush()
			}
		}
	}
}

// fetchPipelineHealthData aggregates health data from Redis
func fetchPipelineHealthData(ctx context.Context, rdb *redis.Client) map[string]interface{} {
	data := map[string]interface{}{
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	}

	// Get health status from all services
	services := []string{"bridge", "device-server", "api"}
	healthStatus := make(map[string]string)
	overallStatus := "ok"

	for _, service := range services {
		key := fmt.Sprintf("pipeline:health:%s", service)
		status, err := rdb.Get(ctx, key).Result()
		if err != nil {
			if err == redis.Nil {
				healthStatus[service] = "unknown"
				if overallStatus == "ok" {
					overallStatus = "degraded"
				}
			} else {
				healthStatus[service] = "error"
				overallStatus = "down"
			}
		} else {
			healthStatus[service] = status
			if status == "down" {
				overallStatus = "down"
			} else if status == "degraded" && overallStatus == "ok" {
				overallStatus = "degraded"
			}
		}
	}

	data["service_status"] = healthStatus
	data["overall_status"] = overallStatus

	// Get DLQ counts
	dlqCounts := make(map[string]int64)
	totalDLQ := int64(0)
	for _, service := range services {
		key := fmt.Sprintf("kafka:dlq:%s", service)
		count, err := rdb.LLen(ctx, key).Result()
		if err == nil {
			dlqCounts[service] = count
			totalDLQ += count
		}
	}
	data["dlq_pending"] = dlqCounts
	data["dlq_total"] = totalDLQ

	// Get online device count (from heartbeat keys)
	onlineCount := 0
	cursor := uint64(0)
	for {
		keys, nextCursor, err := rdb.Scan(ctx, cursor, "device:heartbeat:*", 100).Result()
		if err != nil {
			break
		}
		onlineCount += len(keys)
		cursor = nextCursor
		if cursor == 0 {
			break
		}
	}
	data["online_device_count"] = onlineCount

	return data
}
