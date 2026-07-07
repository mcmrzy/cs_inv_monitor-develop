package mqtt

import (
	"context"
	"crypto/tls"
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
	onOtaCmdAck    func(sn string, payload []byte)
	onStatusChange func(sn string, online bool)
	onCmdResult     func(sn string, payload []byte)
}

func (c *Client) SetOtaStatusHandler(handler func(sn string, payload []byte)) {
	c.onOtaStatus = handler
}

func (c *Client) SetOtaCmdAckHandler(handler func(sn string, payload []byte)) {
	c.onOtaCmdAck = handler
}

func (c *Client) SetStatusChangeHandler(handler func(sn string, online bool)) {
	c.onStatusChange = handler
}

func (c *Client) SetCmdResultHandler(handler func(sn string, payload []byte)) {
	c.onCmdResult = handler
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

// heartbeatKey returns the Redis key for device heartbeat with TTL.
// Each device gets an independent key that auto-expires after timeout,
// enabling Redis Keyspace Notifications for event-driven offline detection.
func heartbeatKey(sn string) string {
	return "device:heartbeat:" + sn
}

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
		// Set independent key with TTL for event-driven expiry detection
		h.rdb.Set(ctx, heartbeatKey(sn), now.Unix(), onlineTimeoutSeconds*time.Second)
	}
}

func (h *Hub) IsDeviceOnline(sn string) bool {
	if h.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		// Check if the heartbeat key exists (TTL handles expiry automatically)
		return h.rdb.Exists(ctx, heartbeatKey(sn)).Val() > 0
	}
	return false
}

func (h *Hub) GetOnlineDeviceSNs() []string {
	if h.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		var sns []string
		var cursor uint64
		for {
			keys, nextCursor, err := h.rdb.Scan(ctx, cursor, "device:heartbeat:*", 1000).Result()
			if err != nil {
				break
			}
			for _, key := range keys {
				sns = append(sns, strings.TrimPrefix(key, "device:heartbeat:"))
			}
			cursor = nextCursor
			if cursor == 0 {
				break
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

	// 配置 TLS（跳过证书验证）
	var tlsConfig *tls.Config
	if c.config.TLSInsecure {
		tlsConfig = &tls.Config{
			InsecureSkipVerify: true,
		}
	}

	cliCfg := autopaho.ClientConfig{
		ServerUrls:                    []*url.URL{serverURL},
		TlsCfg:                        tlsConfig,
		KeepAlive:                     120,
		CleanStartOnInitialConnection: false,
		SessionExpiryInterval:         86400,
		OnConnectionUp: func(cm *autopaho.ConnectionManager, connAck *paho.Connack) {
			logger.Info("MQTT connected (command channel only)")
			if _, err := cm.Subscribe(ctx, &paho.Subscribe{
				Subscriptions: []paho.SubscribeOptions{
					{Topic: "cs_inv/#", QoS: 1},
				},
			}); err != nil {
				logger.Error("Failed to subscribe to topic", zap.Error(err))
			} else {
				logger.Info("Subscribed to cs_inv/#")
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

					// 设备状态主题（LWT 离线/上线消息）
					if isDeviceStatusTopic(topic) {
						online := parseStatusOnline(pr.Packet.Payload)
						if online {
							// 设备主动上报在线，更新心跳
							c.hub.MarkDeviceOnline(sn)
							c.hub.stats.DataReceived++
							c.hub.stats.LastDataAt = time.Now()
						}
						// LWT 离线消息：不刷新心跳 key，让 120s TTL 自然过期
						// 不主动删除 key，避免设备短暂断连后重连导致状态抖动
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
					
					// 处理 OTA 命令确认
					if isOtaCmdAckTopic(topic) && c.onOtaCmdAck != nil {
						c.onOtaCmdAck(sn, pr.Packet.Payload)
					}

					// 处理命令执行结果上报
					if isCmdResultTopic(topic) && c.onCmdResult != nil {
						c.onCmdResult(sn, pr.Packet.Payload)
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

// isOtaCommand 判断是否为 OTA 相关命令
func isOtaCommand(cmdType string) bool {
	return cmdType == "ota_upgrade" || cmdType == "ota_notify" || cmdType == "start"
}

func (c *Client) sendCommand(ctx context.Context, cmd *DeviceCommand) {
	c.hub.stats.CmdSent++

	// OTA命令使用专用主题 cs_inv/{sn}/ota/cmd，其他命令使用通用主题 cs_inv/{sn}/cmd
	var topic string
	if isOtaCommand(cmd.CmdType) {
		topic = fmt.Sprintf("cs_inv/%s/ota/cmd", cmd.DeviceSN)
	} else {
		topic = fmt.Sprintf("cs_inv/%s/cmd", cmd.DeviceSN)
	}

	// OTA 命令有原始 JSON，直接发送
	if isOtaCommand(cmd.CmdType) && len(cmd.RawPayload) > 0 {
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

	// 构造符合文档规范的 MQTT payload: {"cmd": ..., "params": ..., "task_id": ...}
	mqttPayload := c.buildMqttPayload(cmd)
	body, err := json.Marshal(mqttPayload)
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
		zap.String("cmd", cmd.CmdType),
		zap.String("task_id", mqttPayload["task_id"].(string)))
}

// buildMqttPayload 构造符合控制命令文档规范的 MQTT payload
// 格式: {"cmd": "set_control", "params": {...}, "task_id": "cmd_xxx"}
func (c *Client) buildMqttPayload(cmd *DeviceCommand) map[string]interface{} {
	payload := map[string]interface{}{
		"cmd": cmd.CmdType,
	}

	// 从 RawPayload 中提取 task_id（来自 API Server 的请求体）
	var taskID string
	if len(cmd.RawPayload) > 0 {
		var rawReq map[string]interface{}
		if err := json.Unmarshal(cmd.RawPayload, &rawReq); err == nil {
			if tid, ok := rawReq["task_id"].(string); ok {
				taskID = tid
			}
			// 使用 RawPayload 中的 params（可能比 cmd.Params 更完整）
			if params, ok := rawReq["params"]; ok && params != nil {
				payload["params"] = params
			} else if cmd.Params != nil && len(cmd.Params) > 0 {
				payload["params"] = cmd.Params
			}
		} else {
			if cmd.Params != nil && len(cmd.Params) > 0 {
				payload["params"] = cmd.Params
			}
		}
	} else if cmd.Params != nil && len(cmd.Params) > 0 {
		payload["params"] = cmd.Params
	}

	if taskID == "" {
		taskID = fmt.Sprintf("cmd_%d", time.Now().UnixNano())
	}
	payload["task_id"] = taskID

	return payload
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

// isOtaCmdAckTopic 匹配 cs_inv/{sn}/ota/cmd_ack
func isOtaCmdAckTopic(topic string) bool {
	parts := strings.Split(topic, "/")
	// 匹配 cs_inv/{sn}/ota/cmd_ack
	if len(parts) >= 4 && parts[0] == "cs_inv" && parts[2] == "ota" && parts[3] == "cmd_ack" {
		return true
	}
	// 匹配共享订阅 $share/{group}/cs_inv/{sn}/ota/cmd_ack
	if len(parts) >= 7 && parts[0] == "$share" && parts[3] == "cs_inv" && parts[5] == "ota" && parts[6] == "cmd_ack" {
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

// isCmdResultTopic 匹配 cs_inv/{sn}/cmd_result
func isCmdResultTopic(topic string) bool {
	parts := strings.Split(topic, "/")
	if len(parts) == 3 && parts[0] == "cs_inv" && parts[2] == "cmd_result" {
		return true
	}
	// 匹配共享订阅 $share/{group}/cs_inv/{sn}/cmd_result
	if len(parts) >= 6 && parts[0] == "$share" && parts[3] == "cs_inv" && parts[5] == "cmd_result" {
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
