package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"sync"
	"time"

	"inv-api-server/internal/service"
	"inv-api-server/pkg/logger"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

type WSHandler struct {
	rdb        *redis.Client
	jwtService *service.JWTService
	conns      map[string]int
	connsMux   sync.Mutex
}

func NewWSHandler(rdb *redis.Client, jwtService *service.JWTService) *WSHandler {
	return &WSHandler{
		rdb:        rdb,
		jwtService: jwtService,
		conns:      make(map[string]int),
	}
}

func (h *WSHandler) DeviceRealtime(c *gin.Context) {
	sn := c.Param("sn")

	token := c.Query("token")
	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "token required"})
		return
	}

	claims, err := h.jwtService.ParseToken(token)
	if err != nil {
		logger.Warn("WS auth failed", zap.String("sn", sn), zap.Error(err))
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
		return
	}

	_ = claims.UserID
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
			conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		case msg := <-ch:
			conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.WriteMessage(websocket.TextMessage, []byte(msg.Payload)); err != nil {
				logger.Warn("WS write failed", zap.String("sn", sn), zap.Error(err))
				return
			}
		}
	}
}