package mqtt

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestExtractSN(t *testing.T) {
	tests := []struct {
		name  string
		topic string
		want  string
	}{
		{"standard topic", "cs_inv/ABC123/data/ac", "ABC123"},
		{"status topic", "cs_inv/ABC123/status", "ABC123"},
		{"ota status topic", "cs_inv/ABC123/ota/status", "ABC123"},
		{"ota cmd_ack topic", "cs_inv/ABC123/ota/cmd_ack", "ABC123"},
		{"cmd result topic", "cs_inv/ABC123/cmd_result", "ABC123"},
		{"shared subscription", "$share/group/cs_inv/ABC123/data/ac", "ABC123"},
		{"shared status", "$share/group/cs_inv/ABC123/status", "ABC123"},
		{"shared ota", "$share/group/cs_inv/ABC123/ota/status", "ABC123"},
		{"too short", "cs_inv", ""},
		{"empty", "", ""},
		{"only slash", "/", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractSN(tt.topic)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestIsDeviceStatusTopic(t *testing.T) {
	tests := []struct {
		name  string
		topic string
		want  bool
	}{
		{"status topic", "cs_inv/ABC123/status", true},
		{"shared status", "$share/group/cs_inv/ABC123/status", true},
		{"data status", "cs_inv/ABC123/data/status", false},
		{"ota status", "cs_inv/ABC123/ota/status", false},
		{"data ac", "cs_inv/ABC123/data/ac", false},
		{"cmd", "cs_inv/ABC123/cmd", false},
		{"empty", "", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isDeviceStatusTopic(tt.topic)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestIsOtaStatusTopic(t *testing.T) {
	tests := []struct {
		name  string
		topic string
		want  bool
	}{
		{"ota status", "cs_inv/ABC123/ota/status", true},
		{"shared ota status", "$share/group/cs_inv/ABC123/ota/status", true},
		{"ota cmd_ack", "cs_inv/ABC123/ota/cmd_ack", false},
		{"status", "cs_inv/ABC123/status", false},
		{"data status", "cs_inv/ABC123/data/status", false},
		{"empty", "", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isOtaStatusTopic(tt.topic)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestIsOtaCmdAckTopic(t *testing.T) {
	tests := []struct {
		name  string
		topic string
		want  bool
	}{
		{"ota cmd_ack", "cs_inv/ABC123/ota/cmd_ack", true},
		{"shared ota cmd_ack", "$share/group/cs_inv/ABC123/ota/cmd_ack", true},
		{"ota status", "cs_inv/ABC123/ota/status", false},
		{"status", "cs_inv/ABC123/status", false},
		{"empty", "", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isOtaCmdAckTopic(tt.topic)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestIsCmdResultTopic(t *testing.T) {
	tests := []struct {
		name  string
		topic string
		want  bool
	}{
		{"cmd_result", "cs_inv/ABC123/cmd_result", true},
		{"shared cmd_result", "$share/group/cs_inv/ABC123/cmd_result", true},
		{"cmd", "cs_inv/ABC123/cmd", false},
		{"status", "cs_inv/ABC123/status", false},
		{"empty", "", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isCmdResultTopic(tt.topic)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestParseStatusOnline(t *testing.T) {
	tests := []struct {
		name    string
		payload []byte
		want    bool
	}{
		{"online true", []byte(`{"online":true}`), true},
		{"online false", []byte(`{"online":false}`), false},
		{"no online field", []byte(`{"rssi":-65}`), true},
		{"invalid json", []byte(`not json`), true},
		{"empty payload", []byte{}, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseStatusOnline(tt.payload)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestIsOtaCommand(t *testing.T) {
	tests := []struct {
		cmdType string
		want    bool
	}{
		{"ota_upgrade", true},
		{"ota_notify", true},
		{"start", true},
		{"set_control", false},
		{"reboot", false},
		{"", false},
	}

	for _, tt := range tests {
		t.Run(tt.cmdType, func(t *testing.T) {
			got := isOtaCommand(tt.cmdType)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestHubStats(t *testing.T) {
	hub := NewHub(nil)
	stats := hub.GetStats()
	assert.Equal(t, int64(0), stats.DataReceived)
	assert.Equal(t, int64(0), stats.InfoReceived)
	assert.Equal(t, int64(0), stats.AlarmReceived)
	assert.Equal(t, int64(0), stats.CmdSent)
	assert.Equal(t, 0, stats.OnlineClients)
}

func TestHubCommandChannel(t *testing.T) {
	hub := NewHub(nil)
	cmdChan := hub.GetCmdChan()

	cmd := &DeviceCommand{
		DeviceSN: "TEST001",
		CmdType:  "set_control",
		Params: map[string]interface{}{
			"power": 100,
		},
	}

	cmdChan <- cmd

	select {
	case received := <-hub.cmdChan:
		assert.Equal(t, "TEST001", received.DeviceSN)
		assert.Equal(t, "set_control", received.CmdType)
	default:
		t.Fatal("expected command in channel")
	}
}
