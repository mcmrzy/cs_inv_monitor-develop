package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"inv-api-server/pkg/jwt"
	"inv-api-server/pkg/logger"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type WSHandler struct {
	rdb        *redis.Client
	jwtService *jwt.JWT
}

func NewWSHandler(rdb *redis.Client, jwtService *jwt.JWT) *WSHandler {
	return &WSHandler{rdb: rdb, jwtService: jwtService}
}

func (h *WSHandler) DeviceRealtime(c *gin.Context) {
	sn := c.Param("sn")

	token := c.Query("token")
	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "token required"})
		return
	}

	_, err := h.jwtService.ParseToken(token)
	if err != nil {
		logger.Warn("WS auth failed", zap.String("sn", sn), zap.Error(err))
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
		return
	}

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		logger.Error("WS upgrade failed", zap.String("sn", sn), zap.Error(err))
		return
	}
	defer conn.Close()

	logger.Info("WS device connected", zap.String("sn", sn))

	ctx, cancel := context.WithCancel(c.Request.Context())
	defer cancel()

	go func() {
		for {
			_, _, err := conn.ReadMessage()
			if err != nil {
				cancel()
				return
			}
		}
	}()

	pingTicker := time.NewTicker(15 * time.Second)
	defer pingTicker.Stop()

	pollTicker := time.NewTicker(2 * time.Second)
	defer pollTicker.Stop()

	var lastDataTime time.Time

	for {
		select {
		case <-ctx.Done():
			return
		case <-pingTicker.C:
			conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		case <-pollTicker.C:
			cacheKey := "realtime:latest:" + sn
			cached, err := h.rdb.Get(ctx, cacheKey).Result()
			if err != nil || cached == "" {
				continue
			}

			var data map[string]interface{}
			if json.Unmarshal([]byte(cached), &data) != nil {
				continue
			}

			if ut, ok := data["updated_at"].(string); ok {
				if t, err := time.Parse(time.RFC3339Nano, ut); err == nil {
					if !t.After(lastDataTime) {
						continue
					}
					lastDataTime = t
				}
			}

			conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.WriteMessage(websocket.TextMessage, []byte(cached)); err != nil {
				logger.Warn("WS write failed", zap.String("sn", sn), zap.Error(err))
				return
			}
		}
	}
}
