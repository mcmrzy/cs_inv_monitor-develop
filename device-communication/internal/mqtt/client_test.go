package mqtt

import (
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
)

func TestUniqueClientIDAddsInstanceSuffix(t *testing.T) {
	id := uniqueClientID("inv-device-server")
	assert.True(t, strings.HasPrefix(id, "inv-device-server-"))
	assert.Greater(t, len(id), len("inv-device-server-"))
}

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
		{"v1 cmd response", "cs_inv/ABC123/cmd/response", true},
		{"shared v1 cmd response", "$share/group/cs_inv/ABC123/cmd/response", true},
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

func TestMQTTStats_ConcurrentSafety(t *testing.T) {
	// Create new MQTT client with mock config
	rdb := redis.NewClient(&redis.Options{
		Addr: "localhost:6379",
	})
	defer rdb.Close()

	hub := NewHub(rdb)
	initialStats := hub.GetStats()
	var wg sync.WaitGroup
	numGoroutines := 1000

	// Launch 1000 goroutines each incrementing stats concurrently
	wg.Add(numGoroutines)
	for i := 0; i < numGoroutines; i++ {
		go func() {
			defer wg.Done()
			hub.stats.DataReceived.Add(1)
			hub.stats.InfoReceived.Add(1)
			hub.stats.AlarmReceived.Add(1)
			hub.stats.CmdSent.Add(1)
			hub.stats.LastDataAt.Store(time.Now())
		}()
	}

	// Wait for all goroutines to complete
	wg.Wait()

	// Verify all counters end up at exactly 1000 using atomic operations
	finalStats := hub.GetStats()
	expectedValue := initialStats.DataReceived + int64(numGoroutines)

	assert.Equal(t, expectedValue, finalStats.DataReceived,
		"DataReceived should be %d but got %d", expectedValue, finalStats.DataReceived)
	assert.Equal(t, initialStats.InfoReceived+int64(numGoroutines), finalStats.InfoReceived,
		"InfoReceived should be %d but got %d", initialStats.InfoReceived+int64(numGoroutines), finalStats.InfoReceived)
	assert.Equal(t, initialStats.AlarmReceived+int64(numGoroutines), finalStats.AlarmReceived,
		"AlarmReceived should be %d but got %d", initialStats.AlarmReceived+int64(numGoroutines), finalStats.AlarmReceived)
	assert.Equal(t, initialStats.CmdSent+int64(numGoroutines), finalStats.CmdSent,
		"CmdSent should be %d but got %d", initialStats.CmdSent+int64(numGoroutines), finalStats.CmdSent)
}

func TestHubStatsWithConcurrentAccess(t *testing.T) {
	// Create a hub without Redis to avoid connection attempts
	hub := NewHub(nil)
	var wg sync.WaitGroup

	// Simulate concurrent writes only
	numWriters := 50
	writesPerWriter := 100

	wg.Add(numWriters)

	// Start writers
	for i := 0; i < numWriters; i++ {
		go func() {
			defer wg.Done()
			for j := 0; j < writesPerWriter; j++ {
				hub.stats.DataReceived.Add(1)
				hub.stats.InfoReceived.Add(1)
				hub.stats.AlarmReceived.Add(1)
				hub.stats.CmdSent.Add(1)
				hub.stats.LastDataAt.Store(time.Now())
			}
		}()
	}

	wg.Wait()

	// If no panic occurred, the test passes
	stats := MQTTStats{
		DataReceived:  hub.stats.DataReceived.Load(),
		InfoReceived:  hub.stats.InfoReceived.Load(),
		AlarmReceived: hub.stats.AlarmReceived.Load(),
		CmdSent:       hub.stats.CmdSent.Load(),
		LastDataAt:    getAtomicTime(hub.stats.LastDataAt),
	}
	
	expectedValue := int64(numWriters * writesPerWriter)
	assert.Equal(t, expectedValue, stats.DataReceived)
	assert.Equal(t, expectedValue, stats.InfoReceived)
	assert.Equal(t, expectedValue, stats.AlarmReceived)
	assert.Equal(t, expectedValue, stats.CmdSent)
}
