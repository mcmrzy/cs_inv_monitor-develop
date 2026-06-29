package mqtt

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
	"time"

	"inv-device-server/internal/config"
	"inv-device-server/pkg/logger"

	"github.com/eclipse/paho.golang/autopaho"
	"github.com/eclipse/paho.golang/paho"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

type Client struct {
	cm     *autopaho.ConnectionManager
	config *config.MQTTConfig
	hub    *Hub

	onOtaStatus    func(sn string, payload []byte)
	onStatusChange func(sn string, online bool)
}

func (c *Client) SetOtaStatusHandler(handler func(sn string, payload []byte)) {
	c.onOtaStatus = handler
}

func (c *Client) SetStatusChangeHandler(handler func(sn string, online bool)) {
	c.onStatusChange = handler
}

type Hub struct {
	rdb *redis.Client

	cmdChan chan *DeviceCommand
	stats   MQTTStats
}

type DeviceCommand struct {
	DeviceSN   string
	CmdType    string
	Params     map[string]interface{}
	RawPayload []byte // OTA 等命令的原始 JSON，直接作为 MQTT payload 发送
}

type MQTTStats struct {
	DataReceived  int64     `json:"data_received"`
	InfoReceived  int64     `json:"info_received"`
	AlarmReceived int64     `json:"alarm_received"`
	CmdSent       int64     `json:"cmd_sent"`
	LastDataAt    time.Time `json:"last_data_at"`
	OnlineClients int       `json:"online_clients"`
}

const onlineTimeoutSeconds = 120

func NewHub(rdb *redis.Client) *Hub {
	return &Hub{
		rdb:     rdb,
		cmdChan: make(chan *DeviceCommand, 10000),
	}
}

func (h *Hub) MarkDeviceOnline(sn string) {
	now := time.Now()

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
		if err != nil {
			return false
		}
		var ts int64
		if _, err := fmt.Sscanf(tsStr, "%d", &ts); err != nil {
			return false
		}
		return time.Now().Unix()-ts < onlineTimeoutSeconds
	}
	return false
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
			var ts int64
			if _, err := fmt.Sscanf(tsStr, "%d", &ts); err != nil {
				continue
			}
			if ts > cutoff {
				sns = append(sns, sn)
			}
		}
		return sns
	}
	return nil
}

func (h *Hub) GetCmdChan() chan<- *DeviceCommand {
	return h.cmdChan
}

func (h *Hub) GetStats() MQTTStats {
	h.stats.OnlineClients = len(h.GetOnlineDeviceSNs())
	return h.stats
}

func NewClient(cfg *config.MQTTConfig, hub *Hub) *Client {
	return &Client{
		config: cfg,
		hub:    hub,
	}
}

func (c *Client) Connect(ctx context.Context) error {
	scheme := "mqtt"
	if c.config.TLSInsecure || c.config.Port == 8883 {
		scheme = "tls"
	}

	serverURL, err := url.Parse(fmt.Sprintf("%s://%s:%d", scheme, c.config.Broker, c.config.Port))
	if err != nil {
		return fmt.Errorf("parse MQTT broker URL: %w", err)
	}

	cliCfg := autopaho.ClientConfig{
		ServerUrls:                    []*url.URL{serverURL},
		KeepAlive:                     120,
		CleanStartOnInitialConnection: false,
		SessionExpiryInterval:         86400,
		OnConnectionUp: func(cm *autopaho.ConnectionManager, connAck *paho.Connack) {
			logger.Info("MQTT connected (command channel only)")
			if _, err := cm.Subscribe(ctx, &paho.Subscribe{
				Subscriptions: []paho.SubscribeOptions{
					{Topic: "cs_inv/+/data/#", QoS: 1},
					{Topic: "cs_inv/+/status", QoS: 1},
					{Topic: "cs_inv/+/ota/status", QoS: 1},
				},
			}); err != nil {
				logger.Error("Failed to subscribe to topic", zap.Error(err))
			} else {
				logger.Info("Subscribed to cs_inv/+/data/#, cs_inv/+/status, cs_inv/+/ota/status")
			}
		},
		OnConnectError: func(err error) {
			logger.Error("MQTT connection error", zap.Error(err))
		},
		ClientConfig: paho.ClientConfig{
			ClientID: c.config.ClientID,
			OnPublishReceived: []func(paho.PublishReceived) (bool, error){
				func(pr paho.PublishReceived) (bool, error) {
					topic := pr.Packet.Topic
					sn := extractSN(topic)

					// 设备状态主题（LWT 离线/上线消息）：不更新在线心跳时间戳
					if isDeviceStatusTopic(topic) {
						online := parseStatusOnline(pr.Packet.Payload)
						if online {
							// 设备主动上报在线，更新心跳
							c.hub.MarkDeviceOnline(sn)
							c.hub.stats.DataReceived++
							c.hub.stats.LastDataAt = time.Now()
						}
						// LWT 离线消息不更新心跳，让 Redis 时间戳自然过期
						if c.onStatusChange != nil {
							c.onStatusChange(sn, online)
						}
						return true, nil
					}

					// 非状态主题（数据/OTA 等）：设备发了真实数据，标记在线
					c.hub.MarkDeviceOnline(sn)
					c.hub.stats.DataReceived++
					c.hub.stats.LastDataAt = time.Now()

					// 处理 OTA 状态上报
					if isOtaStatusTopic(topic) && c.onOtaStatus != nil {
						c.onOtaStatus(sn, pr.Packet.Payload)
					}
					return true, nil
				},
			},
			OnClientError: func(err error) {
				logger.Error("MQTT client error", zap.Error(err))
			},
			OnServerDisconnect: func(d *paho.Disconnect) {
				if d.Properties != nil && d.Properties.ReasonString != "" {
					logger.Error("MQTT server disconnect", zap.String("reason", d.Properties.ReasonString))
				} else {
					logger.Error("MQTT server disconnect", zap.Uint8("reason_code", d.ReasonCode))
				}
			},
		},
	}

	if c.config.Username != "" {
		cliCfg.ConnectUsername = c.config.Username
		cliCfg.ConnectPassword = []byte(c.config.Password)
	}

	cm, err := autopaho.NewConnection(ctx, cliCfg)
	if err != nil {
		return fmt.Errorf("create MQTT connection: %w", err)
	}

	c.cm = cm

	if err = cm.AwaitConnection(ctx); err != nil {
		return fmt.Errorf("await MQTT connection: %w", err)
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
			c.sendCommand(ctx, cmd)
		}
	}
}

func (c *Client) sendCommand(ctx context.Context, cmd *DeviceCommand) {
	c.hub.stats.CmdSent++

	// OTA命令使用专用主题 cs_inv/{sn}/ota/cmd，其他命令使用通用主题 cs_inv/{sn}/cmd
	var topic string
	if cmd.CmdType == "ota_upgrade" || cmd.CmdType == "ota_notify" || cmd.CmdType == "start" {
		topic = fmt.Sprintf("cs_inv/%s/ota/cmd", cmd.DeviceSN)
	} else {
		topic = fmt.Sprintf("cs_inv/%s/cmd", cmd.DeviceSN)
	}

	// OTA 命令有原始 JSON，直接发送
	if len(cmd.RawPayload) > 0 {
		_, err := c.cm.Publish(ctx, &paho.Publish{
			QoS:     1,
			Topic:   topic,
			Payload: cmd.RawPayload,
		})
		if err != nil {
			logger.Error("Failed to publish OTA command",
				zap.String("sn", cmd.DeviceSN),
				zap.String("cmd", cmd.CmdType),
				zap.Error(err))
			return
		}
		logger.Info("OTA command sent",
			zap.String("sn", cmd.DeviceSN),
			zap.String("cmd", cmd.CmdType),
			zap.String("topic", topic))
		return
	}

	payload := map[string]string{
		"topic": cmd.CmdType,
	}
	if v, ok := cmd.Params["value"]; ok {
		payload["payload"] = fmt.Sprintf(`{"value":%v}`, v)
	} else if params, ok := cmd.Params["params"]; ok {
		body, _ := json.Marshal(params)
		payload["payload"] = string(body)
	} else if len(cmd.Params) > 0 {
		body, _ := json.Marshal(cmd.Params)
		payload["payload"] = string(body)
	} else {
		payload["payload"] = ""
	}

	body, err := json.Marshal(payload)
	if err != nil {
		logger.Error("Failed to marshal command", zap.Error(err))
		return
	}

	_, err = c.cm.Publish(ctx, &paho.Publish{
		QoS:     1,
		Topic:   topic,
		Payload: body,
	})
	if err != nil {
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
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := c.cm.Disconnect(ctx); err != nil {
		logger.Error("Failed to disconnect MQTT", zap.Error(err))
	}
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

func isOtaStatusTopic(topic string) bool {
	parts := strings.Split(topic, "/")
	// 匹配 cs_inv/{sn}/ota/status
	if len(parts) >= 4 && parts[0] == "cs_inv" && parts[2] == "ota" && parts[3] == "status" {
		return true
	}
	// 匹配共享订阅 $share/{group}/cs_inv/{sn}/ota/status
	if len(parts) >= 7 && parts[0] == "$share" && parts[3] == "cs_inv" && parts[5] == "ota" && parts[6] == "status" {
		return true
	}
	return false
}

// isDeviceStatusTopic 匹配 cs_inv/{sn}/status（设备在线/离线状态，含 LWT）
func isDeviceStatusTopic(topic string) bool {
	parts := strings.Split(topic, "/")
	// 匹配 cs_inv/{sn}/status（排除 cs_inv/{sn}/data/status 和 cs_inv/{sn}/ota/status）
	if len(parts) == 3 && parts[0] == "cs_inv" && parts[2] == "status" {
		return true
	}
	// 匹配共享订阅 $share/{group}/cs_inv/{sn}/status
	if len(parts) == 6 && parts[0] == "$share" && parts[3] == "cs_inv" && parts[5] == "status" {
		return true
	}
	return false
}

// parseStatusOnline 从 status 消息的 payload 中解析 online 字段
func parseStatusOnline(payload []byte) bool {
	var data map[string]interface{}
	if err := json.Unmarshal(payload, &data); err != nil {
		// 解析失败时默认认为在线（收到消息本身说明设备还在）
		return true
	}
	online, ok := data["online"].(bool)
	if !ok {
		return true
	}
	return online
}
