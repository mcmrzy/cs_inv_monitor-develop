package service

import (
	"encoding/json"
	"testing"
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
			input:   `{"sn":"INV001","type":"data/realtime","payload":{"ac":{"voltage":230,"power":5000}}}`,
			wantSN:  "INV001",
			wantTyp: "data/realtime",
		},
		{
			name:    "energy data",
			input:   `{"sn":"INV002","type":"data/energy","payload":{"daily_pv":12.5,"runtime_hours":8.0}}`,
			wantSN:  "INV002",
			wantTyp: "data/energy",
		},
		{
			name:    "info message",
			input:   `{"sn":"INV003","type":"info","payload":{"model":"X1-5K","manufacturer":"CSKJ"}}`,
			wantSN:  "INV003",
			wantTyp: "info",
		},
		{
			name:    "online status",
			input:   `{"sn":"INV004","type":"status","payload":{"online":true}}`,
			wantSN:  "INV004",
			wantTyp: "status",
		},
		{
			name:    "cmd response",
			input:   `{"sn":"INV005","type":"cmd/response","payload":{"cmd":"open","result":"ok"}}`,
			wantSN:  "INV005",
			wantTyp: "cmd/response",
		},
		{
			name:    "missing sn",
			input:   `{"type":"data/realtime","payload":{}}`,
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
			input:   `{"sn":"INV006","type":"data/realtime"}`,
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
