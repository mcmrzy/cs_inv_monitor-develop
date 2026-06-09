package handler

import (
	"context"
	"net/http"
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
		origin := r.Header.Get("Origin")
		if origin == "" {
			return true
		}
		allowedOrigins := []string{"http://localhost:3000", "http://localhost:5173"}
		for _, allowed := range allowedOrigins {
			if origin == allowed {
				return true
			}
		}
		return false
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

	pubsub := h.rdb.Subscribe(ctx, "realtime:data:"+sn)
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