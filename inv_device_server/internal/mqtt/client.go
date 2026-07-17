package mqtt

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
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
	onCmdResult    func(sn string, payload []byte)
	onAlarm        func(sn string, payload []byte)
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

func (c *Client) SetAlarmHandler(handler func(sn string, payload []byte)) {
	c.onAlarm = handler
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

const onlineTimeoutSeconds = 600

// onlineSetKey is the Redis Set that serves as a secondary index of online device SNs.
// The heartbeat keys (device:heartbeat:{sn}) remain the source of truth with TTL-based
// expiry; this Set is maintained for O(1) retrieval of all online device SNs.
const onlineSetKey = "device:online_set"

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
		// Pipeline: set heartbeat key with TTL + add SN to online set (secondary index)
		pipe := h.rdb.Pipeline()
		pipe.Set(ctx, heartbeatKey(sn), now.Unix(), onlineTimeoutSeconds*time.Second)
		pipe.SAdd(ctx, onlineSetKey, sn)
		if _, err := pipe.Exec(ctx); err != nil {
			logger.Warn("Failed to mark device online", zap.String("sn", sn), zap.Error(err))
		}
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
	if h.rdb == nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Primary: O(1) retrieval from Redis Set (secondary index)
	sns, err := h.rdb.SMembers(ctx, onlineSetKey).Result()
	if err == nil && len(sns) > 0 {
		return sns
	}

	// Fallback: scan heartbeat keys when set is empty (e.g. before initial rebuild)
	return h.scanHeartbeatKeys(ctx)
}

// scanHeartbeatKeys scans all device:heartbeat:* keys as a fallback.
func (h *Hub) scanHeartbeatKeys(ctx context.Context) []string {
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

// MarkDeviceOffline removes a device SN from the online set.
// The heartbeat key will expire naturally via TTL; this only cleans the secondary index.
func (h *Hub) MarkDeviceOffline(sn string) {
	if h.rdb == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := h.rdb.SRem(ctx, onlineSetKey, sn).Err(); err != nil {
		logger.Warn("Failed to mark device offline", zap.String("sn", sn), zap.Error(err))
	}
}

// RebuildOnlineSet scans all existing heartbeat keys and rebuilds the online set.
// Should be called on service startup to ensure the set is in sync with heartbeat keys.
func (h *Hub) RebuildOnlineSet(ctx context.Context) error {
	if h.rdb == nil {
		return nil
	}

	sns := h.scanHeartbeatKeys(ctx)

	// Replace the set atomically: delete old set, then add all current SNs
	pipe := h.rdb.Pipeline()
	pipe.Del(ctx, onlineSetKey)
	if len(sns) > 0 {
		members := make([]interface{}, len(sns))
		for i, sn := range sns {
			members[i] = sn
		}
		pipe.SAdd(ctx, onlineSetKey, members...)
	}
	if _, err := pipe.Exec(ctx); err != nil {
		logger.Error("Failed to rebuild online set", zap.Int("count", len(sns)), zap.Error(err))
		return err
	}
	logger.Info("Online set rebuilt", zap.Int("device_count", len(sns)))
	return nil
}

// StartOnlineSetReconciler periodically reconciles the online set with heartbeat keys.
// Runs every 5 minutes to clean up stale entries (devices whose heartbeat keys have expired
// but whose SNs were not removed from the set).
func (h *Hub) StartOnlineSetReconciler(ctx context.Context) {
	if h.rdb == nil {
		return
	}
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			h.reconcileOnlineSet(ctx)
		}
	}
}

// reconcileOnlineSet removes stale SNs from the online set whose heartbeat keys no longer exist.
func (h *Hub) reconcileOnlineSet(ctx context.Context) {
	setSNs, err := h.rdb.SMembers(ctx, onlineSetKey).Result()
	if err != nil {
		logger.Warn("Failed to get online set for reconciliation", zap.Error(err))
		return
	}
	if len(setSNs) == 0 {
		return
	}

	// Check which SNs in the set no longer have a heartbeat key
	var stale []interface{}
	for _, sn := range setSNs {
		if h.rdb.Exists(ctx, heartbeatKey(sn)).Val() == 0 {
			stale = append(stale, sn)
		}
	}
	if len(stale) > 0 {
		h.rdb.SRem(ctx, onlineSetKey, stale...)
		logger.Info("Reconciled online set",
			zap.Int("stale_removed", len(stale)),
			zap.Int("remaining", len(setSNs)-len(stale)))
	}
}

func (h *Hub) GetCmdChan() chan *DeviceCommand {
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
	// Determine whether TLS is needed: port 8883 implies TLS, or either
	// TLS mode flag is explicitly enabled.
	useTLS := c.config.TLSInsecure || c.config.TLSSkipVerify || c.config.Port == 8883
	scheme := "mqtt"
	if useTLS {
		scheme = "tls"
	}

	serverURL, err := url.Parse(fmt.Sprintf("%s://%s:%d", scheme, c.config.Broker, c.config.Port))
	if err != nil {
		return fmt.Errorf("parse MQTT broker URL: %w", err)
	}

	// TLS configuration — three modes (see MQTTConfig docs in config.go):
	//   1. tls_skip_verify=true  → skip all verification (DEV/TEST ONLY)
	//   2. tls_insecure=true     → certificate pinning via cert_sha256 (PRODUCTION)
	//   3. both false + port 8883 → standard CA-based verification (PRODUCTION)
	var tlsConfig *tls.Config
	if c.config.TLSSkipVerify {
		// ⚠ DEVELOPMENT / TESTING ONLY — completely skips certificate
		// verification. Never use in production.
		logger.Warn("MQTT TLS verification is disabled (tls_skip_verify=true) — this is insecure and must NOT be used in production")
		tlsConfig = &tls.Config{
			InsecureSkipVerify: true,
		}
	} else if c.config.TLSInsecure {
		expectedPin, err := hex.DecodeString(strings.TrimSpace(c.config.CertSHA256))
		if err != nil || len(expectedPin) != sha256.Size {
			return fmt.Errorf("MQTT certificate SHA-256 pin is required in pinned TLS mode")
		}
		tlsConfig = &tls.Config{
			// The legacy broker uses a private chain and a certificate without a
			// DNS SAN. Pin the exact leaf certificate instead of accepting any
			// certificate while the broker certificate is being replaced.
			InsecureSkipVerify: true,
			VerifyConnection: func(state tls.ConnectionState) error {
				if len(state.PeerCertificates) == 0 {
					return fmt.Errorf("MQTT broker did not present a certificate")
				}
				leaf, err := x509.ParseCertificate(state.PeerCertificates[0].Raw)
				if err != nil {
					return fmt.Errorf("parse MQTT broker certificate: %w", err)
				}
				now := time.Now()
				if now.Before(leaf.NotBefore) || now.After(leaf.NotAfter) {
					return fmt.Errorf("MQTT broker certificate is outside its validity period")
				}
				actual := sha256.Sum256(leaf.Raw)
				if subtle.ConstantTimeCompare(actual[:], expectedPin) != 1 {
					return fmt.Errorf("MQTT broker certificate pin mismatch")
				}
				return nil
			},
		}
	}
	// When neither flag is set but port is 8883, tlsConfig stays nil and Go
	// uses the default TLS verification with the system CA store.

	cliCfg := autopaho.ClientConfig{
		ServerUrls:                    []*url.URL{serverURL},
		TlsCfg:                        tlsConfig,
		KeepAlive:                     180,
		CleanStartOnInitialConnection: true,
		SessionExpiryInterval:         0,
		OnConnectionUp: func(cm *autopaho.ConnectionManager, connAck *paho.Connack) {
			c.setBrokerHealth("ok")
			logger.Info("MQTT connected (command channel only)")
			if _, err := cm.Subscribe(ctx, &paho.Subscribe{
				Subscriptions: []paho.SubscribeOptions{
					{Topic: "$share/inv-group/cs_inv/#", QoS: 1},
				},
			}); err != nil {
				logger.Error("Failed to subscribe to topic", zap.Error(err))
			} else {
				logger.Info("Subscribed to $share/inv-group/cs_inv/#")
			}
		},
		OnConnectError: func(err error) {
			c.setBrokerHealth("error")
			logger.Error("MQTT connection error", zap.Error(err))
		},
		ClientConfig: paho.ClientConfig{
			ClientID: uniqueClientID(c.config.ClientID),
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
						// LWT 离线消息：不刷新心跳 key，让 600s TTL 自然过期
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

					// 处理告警消息
					if isAlarmTopic(topic) && c.onAlarm != nil {
						c.onAlarm(sn, pr.Packet.Payload)
					}
					return true, nil
				},
			},
			OnClientError: func(err error) {
				c.setBrokerHealth("error")
				logger.Error("MQTT client error", zap.Error(err))
			},
			OnServerDisconnect: func(d *paho.Disconnect) {
				c.setBrokerHealth("disconnected")
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
	// autopaho owns the reconnect loop. Do not block process startup waiting for
	// the broker: the HTTP liveness/readiness endpoint must remain available and
	// report MQTT as not ready while reconnection continues.
	go c.handleCommands(ctx)
	logger.Info("MQTT connection manager started; initial connection is asynchronous")
	return nil
}

func uniqueClientID(base string) string {
	hostname, err := os.Hostname()
	if err != nil || hostname == "" {
		return base
	}
	hostname = strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' {
			return r
		}
		return -1
	}, hostname)
	if len(hostname) > 12 {
		hostname = hostname[len(hostname)-12:]
	}
	if hostname == "" {
		return base
	}
	return base + "-" + hostname
}

func (c *Client) setBrokerHealth(status string) {
	if c.hub == nil || c.hub.rdb == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_ = c.hub.rdb.Set(ctx, "mqtt:broker:health", status, 0).Err()
	_ = c.hub.rdb.Set(ctx, "mqtt:broker:health:updated_at", time.Now().UTC().Unix(), 0).Err()
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
			if version, ok := rawReq["v"]; ok {
				payload["v"] = version
			}
			if timestamp, ok := rawReq["t"]; ok {
				payload["t"] = timestamp
			}
			if tid, ok := rawReq["task_id"].(string); ok {
				taskID = tid
			}
			if args, ok := rawReq["args"].([]interface{}); ok {
				payload["args"] = args
			} else {
				// 使用 RawPayload 中的 params（可能比 cmd.Params 更完整）
				if params, ok := rawReq["params"]; ok && params != nil {
					payload["params"] = params
				} else if cmd.Params != nil && len(cmd.Params) > 0 {
					payload["params"] = cmd.Params
				}
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
	if len(parts) == 6 && parts[0] == "$share" && parts[2] == "cs_inv" && parts[4] == "ota" && parts[5] == "status" {
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
	if len(parts) == 6 && parts[0] == "$share" && parts[2] == "cs_inv" && parts[4] == "ota" && parts[5] == "cmd_ack" {
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
	if len(parts) == 5 && parts[0] == "$share" && parts[2] == "cs_inv" && parts[4] == "status" {
		return true
	}
	return false
}

// isCmdResultTopic supports the final V1 cmd/response topic and the legacy
// cmd_result topic during the device migration window.
func isCmdResultTopic(topic string) bool {
	parts := strings.Split(topic, "/")
	if len(parts) == 3 && parts[0] == "cs_inv" && parts[2] == "cmd_result" {
		return true
	}
	if len(parts) == 4 && parts[0] == "cs_inv" && parts[2] == "cmd" && parts[3] == "response" {
		return true
	}
	// 匹配共享订阅 $share/{group}/cs_inv/{sn}/cmd_result
	if len(parts) == 5 && parts[0] == "$share" && parts[2] == "cs_inv" && parts[4] == "cmd_result" {
		return true
	}
	if len(parts) == 6 && parts[0] == "$share" && parts[2] == "cs_inv" && parts[4] == "cmd" && parts[5] == "response" {
		return true
	}
	return false
}

// isAlarmTopic 匹配 cs_inv/{sn}/alarm 或 cs_inv/{sn}/data/alarm（含共享订阅前缀）
func isAlarmTopic(topic string) bool {
	parts := strings.Split(topic, "/")
	if len(parts) < 3 {
		return false
	}
	return parts[len(parts)-1] == "alarm"
}

// isParallelTopic 匹配 cs_inv/{sn}/parallel（并机状态上报）
func isParallelTopic(topic string) bool {
	parts := strings.Split(topic, "/")
	// 匹配 cs_inv/{sn}/parallel
	if len(parts) == 3 && parts[0] == "cs_inv" && parts[2] == "parallel" {
		return true
	}
	// 匹配共享订阅 $share/{group}/cs_inv/{sn}/parallel
	if len(parts) == 5 && parts[0] == "$share" && parts[2] == "cs_inv" && parts[4] == "parallel" {
		return true
	}
	return false
}

// isThreePhaseTopic 匹配 cs_inv/{sn}/three_phase（三相数据上报）
func isThreePhaseTopic(topic string) bool {
	parts := strings.Split(topic, "/")
	// 匹配 cs_inv/{sn}/three_phase
	if len(parts) == 3 && parts[0] == "cs_inv" && parts[2] == "three_phase" {
		return true
	}
	// 匹配共享订阅 $share/{group}/cs_inv/{sn}/three_phase
	if len(parts) == 5 && parts[0] == "$share" && parts[2] == "cs_inv" && parts[4] == "three_phase" {
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
