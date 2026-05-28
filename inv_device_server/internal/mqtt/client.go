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
	"inv-device-server/internal/model"
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

	realtimeStore map[string]*model.DeviceRealtime
	realtimeMux   sync.RWMutex

	dataChan      chan *model.DeviceRealtime
	infoChan      chan *model.DeviceInfo
	alarmChan     chan *model.AlarmData
	cmdRespChan   chan *model.CommandResponse
	cmdChan       chan *model.DeviceCommand

	stats MQTTStats
}

type MQTTStats struct {
	DataReceived      int64     `json:"data_received"`
	InfoReceived      int64     `json:"info_received"`
	AlarmReceived     int64     `json:"alarm_received"`
	CmdRespReceived   int64     `json:"cmd_resp_received"`
	CmdSent           int64     `json:"cmd_sent"`
	DataDropped       int64     `json:"data_dropped"`
	InfoDropped       int64     `json:"info_dropped"`
	AlarmDropped      int64     `json:"alarm_dropped"`
	CmdRespDropped    int64     `json:"cmd_resp_dropped"`
	LastDataAt        time.Time `json:"last_data_at"`
	OnlineClients     int       `json:"online_clients"`
}

func (h *Hub) GetStats() MQTTStats {
	s := h.stats
	if h.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		onlineCount, _ := h.rdb.HLen(ctx, "device:online").Result()
		s.OnlineClients = int(onlineCount)
	} else {
		h.snMux.RLock()
		s.OnlineClients = len(h.snToLastSeen)
		h.snMux.RUnlock()
	}
	return s
}

func NewHub(rdb *redis.Client) *Hub {
	return &Hub{
		rdb:           rdb,
		snToLastSeen:  make(map[string]time.Time),
		realtimeStore: make(map[string]*model.DeviceRealtime),
		dataChan:      make(chan *model.DeviceRealtime, 2000),
		infoChan:      make(chan *model.DeviceInfo, 500),
		alarmChan:     make(chan *model.AlarmData, 1000),
		cmdRespChan:   make(chan *model.CommandResponse, 500),
		cmdChan:       make(chan *model.DeviceCommand, 200),
	}
}

func (h *Hub) GetDataChan() <-chan *model.DeviceRealtime {
	return h.dataChan
}

func (h *Hub) GetInfoChan() <-chan *model.DeviceInfo {
	return h.infoChan
}

func (h *Hub) GetAlarmChan() <-chan *model.AlarmData {
	return h.alarmChan
}

func (h *Hub) GetCmdRespChan() <-chan *model.CommandResponse {
	return h.cmdRespChan
}

func (h *Hub) GetCmdChan() chan<- *model.DeviceCommand {
	return h.cmdChan
}

func (h *Hub) GetRealtime(sn string) *model.DeviceRealtime {
	h.realtimeMux.RLock()
	defer h.realtimeMux.RUnlock()
	return h.realtimeStore[sn]
}

func (h *Hub) MarkSeen(sn string) {
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

func (h *Hub) GetAllRealtimeSNs() []string {
	h.realtimeMux.RLock()
	defer h.realtimeMux.RUnlock()
	sns := make([]string, 0, len(h.realtimeStore))
	for sn := range h.realtimeStore {
		sns = append(sns, sn)
	}
	return sns
}

func (h *Hub) GetOnlineDeviceSNs() []string {
	if h.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		cutoff := time.Now().Unix() - onlineTimeoutSeconds
		all, err := h.rdb.HGetAll(ctx, "device:online").Result()
		if err != nil {
			h.snMux.RLock()
			defer h.snMux.RUnlock()
			cutoffTime := time.Now().Add(-time.Duration(onlineTimeoutSeconds) * time.Second)
			var sns []string
			for sn, lastSeen := range h.snToLastSeen {
				if lastSeen.After(cutoffTime) {
					sns = append(sns, sn)
				}
			}
			return sns
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

const onlineTimeoutSeconds = 120

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
		InsecureSkipVerify: true,
	})

	opts.OnConnect = func(c mqtt.Client) {
		logger.Info("MQTT connected")
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

	if err := c.subscribeTopics(); err != nil {
		return fmt.Errorf("subscribe error: %w", err)
	}

	go c.handleCommands(ctx)

	return nil
}

func (c *Client) subscribeTopics() error {
	topics := []struct {
		topic   string
		qos     byte
		handler mqtt.MessageHandler
	}{
		{"$share/inv-group/cs_inv/+/status", 1, c.handleStatusMessage},
		{"$share/inv-group/cs_inv/+/info", 1, c.handleInfoMessage},
		{"$share/inv-group/cs_inv/+/data/ac", 0, c.handleDataACMessage},
		{"$share/inv-group/cs_inv/+/data/battery", 0, c.handleDataBatteryMessage},
		{"$share/inv-group/cs_inv/+/data/pv", 0, c.handleDataPVMessage},
		{"$share/inv-group/cs_inv/+/data/status", 0, c.handleDataStatusMessage},
		{"$share/inv-group/cs_inv/+/data/energy", 0, c.handleDataEnergyMessage},
		{"$share/inv-group/cs_inv/+/data/cells", 0, c.handleDataCellsMessage},
		{"$share/inv-group/cs_inv/+/data/alarm", 1, c.handleAlarmMessage},
		{"$share/inv-group/cs_inv/+/cmd/response", 1, c.handleCmdResponseMessage},
	}

	for _, t := range topics {
		token := c.client.Subscribe(t.topic, t.qos, t.handler)
		if err := token.Error(); err != nil {
			return fmt.Errorf("subscribe %s error: %w", t.topic, err)
		}
		logger.Info("Subscribed to topic", zap.String("topic", t.topic))
	}

	return nil
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

func (c *Client) handleStatusMessage(client mqtt.Client, msg mqtt.Message) {
	sn := extractSN(msg.Topic())

	var status model.OnlineStatus
	if err := json.Unmarshal(msg.Payload(), &status); err != nil {
		logger.Warn("Failed to parse status message",
			zap.String("sn", sn),
			zap.String("payload", string(msg.Payload())),
			zap.Error(err))
		return
	}

	c.hub.MarkSeen(sn)

	c.hub.realtimeMux.Lock()
	rt := c.hub.getOrCreateRealtimeLocked(sn)
	rt.OnlineStatus = &status
	rt.UpdatedAt = time.Now()
	c.hub.realtimeMux.Unlock()

	sendToDataChan(c.hub, rt, sn)

	logger.Debug("Device status updated",
		zap.String("sn", sn),
		zap.Bool("online", status.Online),
		zap.Int("rssi", status.RSSI))
}

func (c *Client) handleInfoMessage(client mqtt.Client, msg mqtt.Message) {
	var info model.DeviceInfo
	if err := json.Unmarshal(msg.Payload(), &info); err != nil {
		logger.Warn("Failed to parse info message", zap.Error(err))
		return
	}

	sn := extractSN(msg.Topic())
	if info.SN != "" {
		sn = info.SN
	}
	info.SN = sn

	select {
	case c.hub.infoChan <- &info:
		c.hub.stats.InfoReceived++
	default:
		c.hub.stats.InfoDropped++
		logger.Warn("Info channel full, dropping", zap.String("sn", sn))
	}
}

func (c *Client) handleDataACMessage(client mqtt.Client, msg mqtt.Message) {
	var data model.ACData
	if err := json.Unmarshal(msg.Payload(), &data); err != nil {
		logger.Warn("Failed to parse AC data", zap.Error(err))
		return
	}

	sn := extractSN(msg.Topic())
	data.SN = sn
	data.ReceivedAt = time.Now()

	c.hub.MarkSeen(sn)

	c.hub.realtimeMux.Lock()
	rt := c.hub.getOrCreateRealtimeLocked(sn)
	rt.AC = &data
	rt.UpdatedAt = time.Now()
	c.hub.realtimeMux.Unlock()

	sendToDataChan(c.hub, rt, sn)
}

func (c *Client) handleDataBatteryMessage(client mqtt.Client, msg mqtt.Message) {
	var data model.BatteryData
	if err := json.Unmarshal(msg.Payload(), &data); err != nil {
		logger.Warn("Failed to parse battery data", zap.Error(err))
		return
	}

	sn := extractSN(msg.Topic())
	data.SN = sn
	data.ReceivedAt = time.Now()

	c.hub.MarkSeen(sn)

	c.hub.realtimeMux.Lock()
	rt := c.hub.getOrCreateRealtimeLocked(sn)
	rt.Battery = &data
	rt.UpdatedAt = time.Now()
	c.hub.realtimeMux.Unlock()

	sendToDataChan(c.hub, rt, sn)
}

func (c *Client) handleDataPVMessage(client mqtt.Client, msg mqtt.Message) {
	payload := remapLegacyPV(msg.Payload())

	var data model.PVData
	if err := json.Unmarshal(payload, &data); err != nil {
		logger.Warn("Failed to parse PV data", zap.Error(err))
		return
	}

	sn := extractSN(msg.Topic())
	data.SN = sn
	data.ReceivedAt = time.Now()

	c.hub.MarkSeen(sn)

	c.hub.realtimeMux.Lock()
	rt := c.hub.getOrCreateRealtimeLocked(sn)
	rt.PV = &data
	rt.UpdatedAt = time.Now()
	c.hub.realtimeMux.Unlock()

	sendToDataChan(c.hub, rt, sn)
}

func (c *Client) handleDataStatusMessage(client mqtt.Client, msg mqtt.Message) {
	var data model.SystemStatus
	if err := json.Unmarshal(msg.Payload(), &data); err != nil {
		logger.Warn("Failed to parse system status", zap.Error(err))
		return
	}

	sn := extractSN(msg.Topic())
	data.SN = sn
	data.ReceivedAt = time.Now()

	c.hub.MarkSeen(sn)

	c.hub.realtimeMux.Lock()
	rt := c.hub.getOrCreateRealtimeLocked(sn)
	rt.SysStatus = &data
	rt.UpdatedAt = time.Now()
	c.hub.realtimeMux.Unlock()

	sendToDataChan(c.hub, rt, sn)
}

func (c *Client) handleDataEnergyMessage(client mqtt.Client, msg mqtt.Message) {
	payload := remapLegacyEnergy(msg.Payload())

	var data model.EnergyData
	if err := json.Unmarshal(payload, &data); err != nil {
		logger.Warn("Failed to parse energy data", zap.Error(err))
		return
	}

	sn := extractSN(msg.Topic())
	data.SN = sn
	data.ReceivedAt = time.Now()

	c.hub.MarkSeen(sn)

	c.hub.realtimeMux.Lock()
	rt := c.hub.getOrCreateRealtimeLocked(sn)
	rt.Energy = &data
	rt.UpdatedAt = time.Now()
	c.hub.realtimeMux.Unlock()

	sendToDataChan(c.hub, rt, sn)
}

func (c *Client) handleDataCellsMessage(client mqtt.Client, msg mqtt.Message) {
	var data model.CellsData
	if err := json.Unmarshal(msg.Payload(), &data); err != nil {
		logger.Warn("Failed to parse cells data", zap.Error(err))
		return
	}

	sn := extractSN(msg.Topic())
	data.SN = sn
	data.ReceivedAt = time.Now()

	c.hub.MarkSeen(sn)

	c.hub.realtimeMux.Lock()
	rt := c.hub.getOrCreateRealtimeLocked(sn)
	rt.Cells = &data
	rt.UpdatedAt = time.Now()
	c.hub.realtimeMux.Unlock()

	sendToDataChan(c.hub, rt, sn)
}

func (c *Client) handleAlarmMessage(client mqtt.Client, msg mqtt.Message) {
	var alarm model.AlarmData
	if err := json.Unmarshal(msg.Payload(), &alarm); err != nil {
		logger.Warn("Failed to parse alarm message", zap.Error(err))
		return
	}

	sn := extractSN(msg.Topic())
	alarm.SN = sn
	alarm.ReceivedAt = time.Now()

	select {
	case c.hub.alarmChan <- &alarm:
		c.hub.stats.AlarmReceived++
	default:
		c.hub.stats.AlarmDropped++
		logger.Warn("Alarm channel full, dropping", zap.String("sn", sn))
	}
}

func (c *Client) handleCmdResponseMessage(client mqtt.Client, msg mqtt.Message) {
	var resp model.CommandResponse
	if err := json.Unmarshal(msg.Payload(), &resp); err != nil {
		logger.Warn("Failed to parse command response", zap.Error(err))
		return
	}

	sn := extractSN(msg.Topic())
	resp.SN = sn
	resp.ReceivedAt = time.Now()

	select {
	case c.hub.cmdRespChan <- &resp:
		c.hub.stats.CmdRespReceived++
	default:
		c.hub.stats.CmdRespDropped++
		logger.Warn("CmdResp channel full, dropping", zap.String("sn", sn))
	}
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

func (c *Client) sendCommand(cmd *model.DeviceCommand) {
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
		zap.String("topic", topic),
		zap.String("cmd", cmd.CmdType))
}

func (c *Client) Disconnect() {
	c.client.Disconnect(250)
	logger.Info("MQTT client disconnected")
}

func (h *Hub) getOrCreateRealtimeLocked(sn string) *model.DeviceRealtime {
	rt, ok := h.realtimeStore[sn]
	if !ok {
		rt = &model.DeviceRealtime{DeviceSN: sn}
		h.realtimeStore[sn] = rt
	}
	return rt
}

func sendToDataChan(hub *Hub, rt *model.DeviceRealtime, sn string) {
	select {
	case hub.dataChan <- rt:
		hub.stats.DataReceived++
		hub.stats.LastDataAt = time.Now()
	default:
		hub.stats.DataDropped++
		logger.Warn("Data channel full, dropping", zap.String("sn", sn))
	}
}

func remapLegacyPV(payload []byte) []byte {
	var raw map[string]interface{}
	if err := json.Unmarshal(payload, &raw); err != nil {
		return payload
	}
	changed := false
	if v, ok := raw["pv1_v"]; ok {
		raw["pv_voltage"] = v
		changed = true
	}
	if v, ok := raw["pv1_i"]; ok {
		raw["pv_current"] = v
		changed = true
	}
	if v, ok := raw["pv1_p"]; ok {
		raw["pv_power"] = v
		changed = true
	}
	if !changed {
		return payload
	}
	b, _ := json.Marshal(raw)
	return b
}

func remapLegacyEnergy(payload []byte) []byte {
	var raw map[string]interface{}
	if err := json.Unmarshal(payload, &raw); err != nil {
		return payload
	}
	changed := false
	if v, ok := raw["daily"]; ok {
		raw["daily_pv"] = v
		changed = true
	}
	if v, ok := raw["total"]; ok {
		raw["total_pv"] = v
		changed = true
	}
	if v, ok := raw["hours"]; ok {
		raw["runtime_hours"] = v
		changed = true
	}
	if !changed {
		return payload
	}
	b, _ := json.Marshal(raw)
	return b
}
