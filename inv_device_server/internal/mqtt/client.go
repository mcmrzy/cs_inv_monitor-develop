package mqtt

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"

	"inv-device-server/internal/config"
	"inv-device-server/pkg/logger"

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

type Client struct {
	client mqtt.Client
	config *config.MQTTConfig
	hub    *Hub
}

type Hub struct {
	rdb *redis.Client

	snToLastSeen map[string]time.Time
	snMux        sync.RWMutex

	cmdChan chan *DeviceCommand
	stats   MQTTStats
}

type DeviceCommand struct {
	DeviceSN string
	CmdType  string
	Params   map[string]interface{}
}

type MQTTStats struct {
	DataReceived   int64     `json:"data_received"`
	InfoReceived   int64     `json:"info_received"`
	AlarmReceived  int64     `json:"alarm_received"`
	CmdSent        int64     `json:"cmd_sent"`
	LastDataAt     time.Time `json:"last_data_at"`
	OnlineClients  int       `json:"online_clients"`
}

const onlineTimeoutSeconds = 120

func NewHub(rdb *redis.Client) *Hub {
	return &Hub{
		rdb:          rdb,
		snToLastSeen: make(map[string]time.Time),
		cmdChan:      make(chan *DeviceCommand, 200),
	}
}

func (h *Hub) MarkDeviceOnline(sn string) {
	now := time.Now()
	h.snMux.Lock()
	h.snToLastSeen[sn] = now
	h.snMux.Unlock()

	if h.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		h.rdb.HSet(ctx, "device:online", sn, now.Unix())
	}
}

func (h *Hub) IsDeviceOnline(sn string) bool {
	if h.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		tsStr, err := h.rdb.HGet(ctx, "device:online", sn).Result()
		if err != nil || tsStr == "" {
			return false
		}
		ts, err := strconv.ParseInt(tsStr, 10, 64)
		if err != nil {
			return false
		}
		return time.Now().Unix()-ts < onlineTimeoutSeconds
	}

	h.snMux.RLock()
	defer h.snMux.RUnlock()
	lastSeen, ok := h.snToLastSeen[sn]
	if !ok {
		return false
	}
	return time.Since(lastSeen) < time.Duration(onlineTimeoutSeconds)*time.Second
}

func (h *Hub) GetOnlineDeviceSNs() []string {
	if h.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		cutoff := time.Now().Unix() - onlineTimeoutSeconds
		all, err := h.rdb.HGetAll(ctx, "device:online").Result()
		if err != nil {
			return nil
		}
		var sns []string
		for sn, tsStr := range all {
			ts, err := strconv.ParseInt(tsStr, 10, 64)
			if err != nil {
				continue
			}
			if ts > cutoff {
				sns = append(sns, sn)
			}
		}
		return sns
	}

	h.snMux.RLock()
	defer h.snMux.RUnlock()
	cutoff := time.Now().Add(-time.Duration(onlineTimeoutSeconds) * time.Second)
	var sns []string
	for sn, lastSeen := range h.snToLastSeen {
		if lastSeen.After(cutoff) {
			sns = append(sns, sn)
		}
	}
	return sns
}

func (h *Hub) GetCmdChan() chan<- *DeviceCommand {
	return h.cmdChan
}

func (h *Hub) GetStats() MQTTStats {
	h.stats.OnlineClients = len(h.GetOnlineDeviceSNs())
	return h.stats
}

func NewClient(cfg *config.MQTTConfig, hub *Hub) *Client {
	opts := mqtt.NewClientOptions()
	opts.AddBroker(fmt.Sprintf("ssl://%s:%d", cfg.Broker, cfg.Port))
	opts.SetClientID(cfg.ClientID)
	opts.SetUsername(cfg.Username)
	opts.SetPassword(cfg.Password)
	opts.SetAutoReconnect(true)
	opts.SetCleanSession(true)
	opts.SetKeepAlive(60 * time.Second)
	opts.SetPingTimeout(10 * time.Second)
	opts.SetConnectTimeout(30 * time.Second)
	opts.SetMaxReconnectInterval(60 * time.Second)

	opts.SetTLSConfig(&tls.Config{
		ServerName:         cfg.Broker,
		MinVersion:         tls.VersionTLS12,
		InsecureSkipVerify: cfg.TLSInsecure,
	})

	opts.OnConnect = func(c mqtt.Client) {
		logger.Info("MQTT connected (command channel only)")
	}

	opts.OnConnectionLost = func(c mqtt.Client, err error) {
		logger.Error("MQTT connection lost", zap.Error(err))
	}

	client := mqtt.NewClient(opts)

	return &Client{
		client: client,
		config: cfg,
		hub:    hub,
	}
}

func (c *Client) Connect(ctx context.Context) error {
	token := c.client.Connect()
	if !token.WaitTimeout(30 * time.Second) {
		return fmt.Errorf("MQTT connection timeout")
	}
	if err := token.Error(); err != nil {
		return fmt.Errorf("MQTT connection error: %w", err)
	}

	go c.handleCommands(ctx)
	return nil
}

func (c *Client) handleCommands(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case cmd := <-c.hub.cmdChan:
			c.sendCommand(cmd)
		}
	}
}

func (c *Client) sendCommand(cmd *DeviceCommand) {
	c.hub.stats.CmdSent++

	topic := fmt.Sprintf("cs_inv/%s/cmd", cmd.DeviceSN)

	payload := map[string]string{
		"topic": cmd.CmdType,
	}
	if v, ok := cmd.Params["value"]; ok {
		payload["payload"] = fmt.Sprintf(`{"value":%v}`, v)
	} else if params, ok := cmd.Params["params"]; ok {
		body, _ := json.Marshal(params)
		payload["payload"] = string(body)
	} else {
		payload["payload"] = ""
	}

	body, err := json.Marshal(payload)
	if err != nil {
		logger.Error("Failed to marshal command", zap.Error(err))
		return
	}

	token := c.client.Publish(topic, 1, false, body)
	if err := token.Error(); err != nil {
		logger.Error("Failed to publish command",
			zap.String("sn", cmd.DeviceSN),
			zap.String("cmd", cmd.CmdType),
			zap.Error(err))
		return
	}

	logger.Info("Command sent",
		zap.String("sn", cmd.DeviceSN),
		zap.String("cmd", cmd.CmdType))
}

func (c *Client) Disconnect() {
	c.client.Disconnect(250)
	logger.Info("MQTT client disconnected")
}

func extractSN(topic string) string {
	parts := strings.Split(topic, "/")
	if len(parts) >= 4 && parts[0] == "$share" {
		return parts[3]
	}
	if len(parts) >= 2 {
		return parts[1]
	}
	return ""
}
