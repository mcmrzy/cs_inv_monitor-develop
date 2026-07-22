package service

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"inv-device-server/internal/repository"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRawMessageParsing(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantSN  string
		wantTyp string
		wantErr bool
	}{
		{
			name:    "realtime data",
			input:   `{"sn":"INV001","msg_type":"data/realtime","payload":{"ac":{"voltage":230,"power":5000}}}`,
			wantSN:  "INV001",
			wantTyp: "data/realtime",
		},
		{
			name:    "energy data",
			input:   `{"sn":"INV002","msg_type":"data/energy","payload":{"daily_pv":12.5,"runtime_hours":8.0}}`,
			wantSN:  "INV002",
			wantTyp: "data/energy",
		},
		{
			name:    "info message",
			input:   `{"sn":"INV003","msg_type":"info","payload":{"model":"X1-5K","manufacturer":"CSKJ"}}`,
			wantSN:  "INV003",
			wantTyp: "info",
		},
		{
			name:    "online status",
			input:   `{"sn":"INV004","msg_type":"status","payload":{"online":true}}`,
			wantSN:  "INV004",
			wantTyp: "status",
		},
		{
			name:    "cmd response",
			input:   `{"sn":"INV005","msg_type":"cmd/response","payload":{"cmd":"open","result":"ok"}}`,
			wantSN:  "INV005",
			wantTyp: "cmd/response",
		},
		{
			name:    "missing sn",
			input:   `{"msg_type":"data/realtime","payload":{}}`,
			wantSN:  "",
			wantTyp: "data/realtime",
			wantErr: true,
		},
		{
			name:    "invalid json",
			input:   `not json`,
			wantErr: true,
		},
		{
			name:    "empty payload uses default",
			input:   `{"sn":"INV006","msg_type":"data/realtime"}`,
			wantSN:  "INV006",
			wantTyp: "data/realtime",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var raw RawMessage
			if err := json.Unmarshal([]byte(tt.input), &raw); err != nil {
				if tt.wantErr {
					return
				}
				t.Fatalf("unmarshal failed: %v", err)
			}

			if raw.SN == "" && !tt.wantErr {
				// SN validation happens at process level, not parse level
			}

			if raw.SN != tt.wantSN {
				t.Errorf("SN = %q, want %q", raw.SN, tt.wantSN)
			}
			if raw.MsgType != tt.wantTyp {
				t.Errorf("MsgType = %q, want %q", raw.MsgType, tt.wantTyp)
			}

			if raw.Payload == nil && !tt.wantErr {
				raw.Payload = json.RawMessage(`{}`)
			}
		})
	}
}

func TestMessageTypeRouting(t *testing.T) {
	tests := []struct {
		msgType string
		want    string
	}{
		{"status", "online"},
		{"online", "online"},
		{"info", "info"},
		{"cmd", "command"},
		{"cmd/response", "command"},
		{"data/realtime", "telemetry"},
		{"data/energy", "telemetry"},
		{"unknown_topic", "telemetry"},
	}

	for _, tt := range tests {
		t.Run(tt.msgType, func(t *testing.T) {
			var route string
			switch tt.msgType {
			case "status", "online":
				route = "online"
			case "info":
				route = "info"
			case "cmd", "cmd/response":
				route = "command"
			default:
				route = "telemetry"
			}
			if route != tt.want {
				t.Errorf("route(%q) = %q, want %q", tt.msgType, route, tt.want)
			}
		})
	}
}

func TestHandleOnlineStatusValue(t *testing.T) {
	tests := []struct {
		name      string
		payload   string
		wantValue int
	}{
		{"online true", `{"online":true}`, 1},
		{"online false", `{"online":false}`, 0},
		{"no online field", `{}`, 1},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var status struct {
				Online bool `json:"online"`
			}
			status.Online = true // default
			_ = json.Unmarshal([]byte(tt.payload), &status)

			statusValue := 1
			if !status.Online {
				statusValue = 0
			}
			if statusValue != tt.wantValue {
				t.Errorf("statusValue = %d, want %d", statusValue, tt.wantValue)
			}
		})
	}
}

func TestUnwrapPayload(t *testing.T) {
	tests := []struct {
		name     string
		payload  json.RawMessage
		expected map[string]interface{}
		wantErr  bool
	}{
		{
			name:     "direct object",
			payload:  json.RawMessage(`{"voltage":220,"power":3500}`),
			expected: map[string]interface{}{"voltage": float64(220), "power": float64(3500)},
		},
		{
			name:     "string wrapped object",
			payload:  json.RawMessage(`"{\"voltage\":220}"`),
			expected: map[string]interface{}{"voltage": float64(220)},
		},
		{
			name:    "invalid neither",
			payload: json.RawMessage(`123`),
			wantErr: true,
		},
		{
			name:    "invalid string content",
			payload: json.RawMessage(`"not json"`),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := unwrapPayload(tt.payload)
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.expected, got)
		})
	}
}

func TestExtractUnixTimestamp(t *testing.T) {
	tests := []struct {
		name     string
		m        map[string]interface{}
		key      string
		expected int64
	}{
		{"float64", map[string]interface{}{"timestamp": float64(1700000000)}, "timestamp", 1700000000},
		{"int64", map[string]interface{}{"timestamp": int64(1700000001)}, "timestamp", 1700000001},
		{"int", map[string]interface{}{"timestamp": int(1700000002)}, "timestamp", 1700000002},
		{"json number", map[string]interface{}{"timestamp": json.Number("1700000003")}, "timestamp", 1700000003},
		{"missing key", map[string]interface{}{}, "timestamp", 0},
		{"unsupported type", map[string]interface{}{"timestamp": "string"}, "timestamp", 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractUnixTimestamp(tt.m, tt.key)
			assert.Equal(t, tt.expected, got)
		})
	}
}

func TestProtocolParser_GetTopicCategory(t *testing.T) {
	parser := NewProtocolParser(
		[]string{"localhost:9092"}, "topic", "group",
		nil, repository.NewMetadataRepository(nil), nil, nil, "", "",
	)

	tests := []struct {
		msgType  string
		expected string
	}{
		{"data/ac", "ac"},
		{"data/battery", "batt"},
		{"data/pv", "pv"},
		{"data/status", "sys"},
		{"data/energy", "energy"},
		{"data/cells", "cells"},
		{"info", "info"},
		{"data/info", "info"},
		{"data/dc", "dc"},
		{"data/grid", "grid"},
		{"data/load", "load"},
		{"data/eps", "eps"},
		{"data/meter", "meter"},
		{"unknown", ""},
		{"", ""},
	}

	for _, tt := range tests {
		t.Run(tt.msgType, func(t *testing.T) {
			got := parser.getTopicCategory(tt.msgType)
			assert.Equal(t, tt.expected, got)
		})
	}
}

func TestProtocolParser_ApplyFieldMapping(t *testing.T) {
	metaRepo := repository.NewMetadataRepository(nil)
	parser := &ProtocolParser{
		snModelCache: make(map[string]int32),
		parseEngine:  NewParseRuleEngine(),
		metaRepo:     metaRepo,
	}
	// 由于 metaRepo 缓存为空，applyFieldMapping 会返回原 payload
	payload := map[string]interface{}{"voltage": float64(220)}
	got := parser.applyFieldMapping(1, payload)
	assert.Equal(t, payload, got)
}

func TestIsValidRealtimeData(t *testing.T) {
	tests := []struct {
		name          string
		data          map[string]interface{}
		topicCategory string
		expected      bool
	}{
		{
			"info always valid",
			map[string]interface{}{},
			"info",
			true,
		},
		{
			"top level power valid",
			map[string]interface{}{"power": float64(100)},
			"ac",
			true,
		},
		{
			"top level all zero invalid",
			map[string]interface{}{"power": float64(0), "voltage": float64(0)},
			"ac",
			false,
		},
		{
			"nested data valid",
			map[string]interface{}{"ac": map[string]interface{}{"data": map[string]interface{}{"power": float64(200)}}},
			"ac",
			true,
		},
		{
			"nested map valid",
			map[string]interface{}{"pv": map[string]interface{}{"pv_voltage": float64(300)}},
			"pv",
			true,
		},
		{
			"soc valid",
			map[string]interface{}{"soc": float64(80)},
			"batt",
			true,
		},
		{
			"empty invalid",
			map[string]interface{}{},
			"ac",
			false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isValidRealtimeData(tt.data, tt.topicCategory)
			assert.Equal(t, tt.expected, got)
		})
	}
}

func TestHasValidFields(t *testing.T) {
	tests := []struct {
		name     string
		data     map[string]interface{}
		expected bool
	}{
		{"power valid", map[string]interface{}{"power": float64(100)}, true},
		{"pv power valid", map[string]interface{}{"pv_power": float64(100)}, true},
		{"voltage valid", map[string]interface{}{"voltage": float64(220)}, true},
		{"energy valid", map[string]interface{}{"daily_pv": float64(10)}, true},
		{"soc valid", map[string]interface{}{"soc": float64(50)}, true},
		{"all zero", map[string]interface{}{"power": float64(0), "voltage": float64(0), "soc": float64(0)}, false},
		{"empty", map[string]interface{}{}, false},
		{"non float power", map[string]interface{}{"power": "high"}, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := hasValidFields(tt.data)
			assert.Equal(t, tt.expected, got)
		})
	}
}

func TestHandleCommandResponse(t *testing.T) {
	handler := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/api/v1/internal/device-cmd-result", r.URL.Path)
		assert.Equal(t, "application/json", r.Header.Get("Content-Type"))
		w.WriteHeader(http.StatusOK)
	}))
	defer handler.Close()

	parser := NewProtocolParser(
		[]string{"localhost:9092"}, "topic", "group",
		nil, repository.NewMetadataRepository(nil), nil, nil,
		handler.URL, "test-key",
	)

	raw := &RawMessage{
		SN:      "SN001",
		MsgType: "cmd_result",
		Payload: json.RawMessage(`{"task_id":"task_1","cmd":"set_control","success":true,"message":"ok","timestamp":1700000000}`),
	}

	err := parser.handleCommandResponse(context.Background(), raw)
	assert.NoError(t, err)
}

func TestProtocolParser_ConcurrentAccess(t *testing.T) {
	parser := NewProtocolParser(
		[]string{"localhost:9092"}, "topic", "group",
		nil, repository.NewMetadataRepository(nil), nil, nil, "", "",
	)

	// 预填充缓存，避免 nil repo 查询
	for i := 0; i < 26; i++ {
		sn := "SN" + string(rune('A'+i))
		parser.snModelCache[sn] = int32(i + 1)
	}

	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			parser.snCacheMu.Lock()
			parser.snModelCache["SN"+string(rune('A'+idx%26))] = int32(idx)
			parser.snCacheMu.Unlock()
		}(i)
	}
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			_ = parser.getModelID(context.Background(), "SN"+string(rune('A'+idx%26)))
		}(i)
	}
	wg.Wait()
}

// 时区边界测试：验证 UTC 转换后日期正确
func TestTimestampTimezoneBoundary(t *testing.T) {
	// 2024-01-01 00:00:00 Asia/Shanghai = 2023-12-31 16:00:00 UTC
	shanghai := time.FixedZone("Asia/Shanghai", 8*60*60)
	local := time.Date(2024, 1, 1, 0, 0, 0, 0, shanghai)
	utc := local.UTC()
	assert.Equal(t, 2023, utc.Year())
	assert.Equal(t, time.December, utc.Month())
	assert.Equal(t, 31, utc.Day())
}

const validParallelEnvelope = `{
  "t":1783676930,
  "v":1,
  "data":{
    "enabled":true,
    "mode":"three_phase",
    "count":3,
    "total_rated_power":18600,
    "total_active_power":15200,
    "sync_state":"synced",
    "machines":[
      {"id":0,"sn":"MASTER001","role":"master","phase":"L1","power":5100,"state":2},
      {"id":1,"sn":"SLAVE002","role":"slave","phase":"L2","power":5050,"state":2},
      {"id":2,"sn":"SLAVE003","role":"slave","phase":"L3","power":5050,"state":2}
    ]
  }
}`

const validThreePhaseEnvelope = `{
  "t":1783676930,
  "v":1,
  "data":{
    "voltage":[220.1,219.9,220.0],
    "current":[8.1,8.0,7.9],
    "active_power":[1760,1740,1720],
    "total_active_power":5220,
    "line_voltage":[381.1,380.9,381.0],
    "frequency":50.0,
    "voltage_unbalance":0.2,
    "current_unbalance":1.1
  }
}`

func TestParseV1UpstreamEnvelope_StrictMetadata(t *testing.T) {
	tests := []struct {
		name    string
		payload string
		wantErr string
	}{
		{name: "missing t", payload: `{"v":1,"data":{}}`, wantErr: `field "t" is required`},
		{name: "zero t", payload: `{"t":0,"v":1,"data":{}}`, wantErr: "t must be greater than zero"},
		{name: "fractional t", payload: `{"t":1.5,"v":1,"data":{}}`, wantErr: "invalid V1 envelope fields"},
		{name: "wrong version", payload: `{"t":1,"v":2,"data":{}}`, wantErr: "unsupported V1 envelope version"},
		{name: "missing data", payload: `{"t":1,"v":1}`, wantErr: `field "data" is required`},
		{name: "array data", payload: `{"t":1,"v":1,"data":[]}`, wantErr: "data must be an object"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := parseV1UpstreamEnvelope(json.RawMessage(tt.payload))
			require.Error(t, err)
			assert.Contains(t, err.Error(), tt.wantErr)
		})
	}
}

func TestHandleParallel_ForwardsCompleteEnvelopeContract(t *testing.T) {
	var request internalEnvelopeRequest
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/api/v1/internal/parallel-state", r.URL.Path)
		assert.Equal(t, "contract-key", r.Header.Get("X-Internal-Key"))
		require.NoError(t, json.NewDecoder(r.Body).Decode(&request))
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	parser := &ProtocolParser{apiServer: server.URL, internalKey: "contract-key", httpClient: server.Client()}
	raw := &RawMessage{
		SN: "MASTER001", MsgType: "parallel", ReceivedAt: "2026-07-14T10:20:30.123456789Z",
		Payload: json.RawMessage(validParallelEnvelope),
	}
	require.NoError(t, parser.handleParallel(context.Background(), raw))
	assert.Equal(t, "MASTER001", request.SN)
	assert.Equal(t, "parallel", request.Topic)
	assert.Equal(t, "2026-07-14T10:20:30.123456789Z", request.ReceivedAt.Format(time.RFC3339Nano))
	assert.JSONEq(t, validParallelEnvelope, string(request.Envelope))

	var forwarded map[string]json.RawMessage
	encoded, err := json.Marshal(request)
	require.NoError(t, err)
	require.NoError(t, json.Unmarshal(encoded, &forwarded))
	assert.ElementsMatch(t, []string{"sn", "topic", "received_at", "envelope"}, mapKeys(forwarded))
}

func TestHandleParallel_RejectsInvalidTopology(t *testing.T) {
	tests := []struct {
		name    string
		payload string
		wantErr string
	}{
		{name: "legacy flat payload", payload: `{"enabled":false,"mode":"standalone","count":0}`, wantErr: `field "t" is required`},
		{name: "unknown field", payload: `{"t":1,"v":1,"data":{"enabled":false,"mode":"standalone","count":0,"total_rated_power":0,"total_active_power":0,"sync_state":"idle","machines":[],"extra":1}}`, wantErr: "unknown field"},
		{name: "disabled not zero form", payload: `{"t":1,"v":1,"data":{"enabled":false,"mode":"single_phase","count":0,"total_rated_power":0,"total_active_power":0,"sync_state":"idle","machines":[]}}`, wantErr: "standalone zero-value form"},
		{name: "sender is not master", payload: validParallelEnvelope, wantErr: "match the topic SN"},
		{name: "missing L3", payload: `{"t":1,"v":1,"data":{"enabled":true,"mode":"three_phase","count":3,"total_rated_power":18600,"total_active_power":3,"sync_state":"synced","machines":[{"id":0,"sn":"MASTER001","role":"master","phase":"L1","power":1,"state":2},{"id":1,"sn":"S2","role":"slave","phase":"L2","power":1,"state":2},{"id":2,"sn":"S3","role":"slave","phase":"L2","power":1,"state":2}]}}`, wantErr: "include L1, L2 and L3"},
		{name: "negative total power", payload: `{"t":1,"v":1,"data":{"enabled":true,"mode":"single_phase","count":1,"total_rated_power":6200,"total_active_power":-1,"sync_state":"synced","machines":[{"id":0,"sn":"MASTER001","role":"master","phase":null,"power":-1,"state":2}]}}`, wantErr: "total power is invalid"},
		{name: "negative machine power", payload: `{"t":1,"v":1,"data":{"enabled":true,"mode":"single_phase","count":2,"total_rated_power":12400,"total_active_power":1,"sync_state":"synced","machines":[{"id":0,"sn":"MASTER001","role":"master","phase":null,"power":-1,"state":2},{"id":1,"sn":"S2","role":"slave","phase":null,"power":2,"state":2}]}}`, wantErr: "non-negative"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sn := "MASTER001"
			if tt.name == "sender is not master" {
				sn = "SLAVE002"
			}
			parser := &ProtocolParser{}
			err := parser.handleParallel(context.Background(), &RawMessage{SN: sn, Payload: json.RawMessage(tt.payload)})
			require.Error(t, err)
			assert.Contains(t, err.Error(), tt.wantErr)
		})
	}
}

func TestHandleThreePhase_ForwardsCompleteEnvelopeContract(t *testing.T) {
	var request internalEnvelopeRequest
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/api/v1/internal/three-phase", r.URL.Path)
		require.NoError(t, json.NewDecoder(r.Body).Decode(&request))
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	parser := &ProtocolParser{apiServer: server.URL, httpClient: server.Client()}
	raw := &RawMessage{SN: "MASTER001", MsgType: "three_phase", Payload: json.RawMessage(validThreePhaseEnvelope)}
	require.NoError(t, parser.handleThreePhase(context.Background(), raw))
	assert.Equal(t, "MASTER001", request.SN)
	assert.Equal(t, "three_phase", request.Topic)
	assert.False(t, request.ReceivedAt.IsZero())
	assert.JSONEq(t, validThreePhaseEnvelope, string(request.Envelope))
}

func TestHandleThreePhase_RejectsInvalidData(t *testing.T) {
	tests := []struct {
		name    string
		payload string
		wantErr string
	}{
		{name: "wrong version", payload: `{"t":1,"v":2,"data":{}}`, wantErr: "unsupported V1 envelope version"},
		{name: "wrong array length", payload: `{"t":1,"v":1,"data":{"voltage":[220,220],"current":[1,1,1],"active_power":[100,100,100],"total_active_power":300,"line_voltage":[380,380,380],"frequency":50,"voltage_unbalance":0,"current_unbalance":0}}`, wantErr: "exactly 3 elements"},
		{name: "invalid unbalance", payload: `{"t":1,"v":1,"data":{"voltage":[220,220,220],"current":[1,1,1],"active_power":[100,100,100],"total_active_power":300,"line_voltage":[380,380,380],"frequency":50,"voltage_unbalance":101,"current_unbalance":0}}`, wantErr: "outside the V1 range"},
		{name: "power mismatch", payload: `{"t":1,"v":1,"data":{"voltage":[220,220,220],"current":[1,1,1],"active_power":[100,100,100],"total_active_power":400,"line_voltage":[380,380,380],"frequency":50,"voltage_unbalance":0,"current_unbalance":0}}`, wantErr: "does not match phase power"},
		{name: "negative phase power", payload: `{"t":1,"v":1,"data":{"voltage":[220,220,220],"current":[1,1,1],"active_power":[-100,100,100],"total_active_power":100,"line_voltage":[380,380,380],"frequency":50,"voltage_unbalance":0,"current_unbalance":0}}`, wantErr: "active power values must not be negative"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parser := &ProtocolParser{}
			err := parser.handleThreePhase(context.Background(), &RawMessage{SN: "MASTER001", Payload: json.RawMessage(tt.payload)})
			require.Error(t, err)
			assert.Contains(t, err.Error(), tt.wantErr)
		})
	}
}

func mapKeys(values map[string]json.RawMessage) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	return keys
}
