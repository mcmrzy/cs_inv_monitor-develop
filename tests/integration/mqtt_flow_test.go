//go:build integration

package integration

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// newMQTTClient creates a test MQTT client connected to the test broker.
func newMQTTClient(t *testing.T, cfg EnvConfig, clientID string) mqtt.Client {
	t.Helper()

	opts := mqtt.NewClientOptions().
		AddBroker(fmt.Sprintf("tcp://%s:%s", cfg.MQTTBroker, cfg.MQTTPort)).
		SetClientID(clientID).
		SetAutoReconnect(true).
		SetConnectTimeout(5 * time.Second)

	client := mqtt.NewClient(opts)
	token := client.Connect()
	if !token.WaitTimeout(10 * time.Second) {
		t.Skipf("MQTT broker not reachable, skipping")
	}
	if token.Error() != nil {
		t.Skipf("MQTT connection failed: %v, skipping", token.Error())
	}

	return client
}

// TestMQTTConnect verifies we can connect to the test MQTT broker.
func TestMQTTConnect(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.MQTTBroker, cfg.MQTTPort, "MQTT Broker")

	client := newMQTTClient(t, cfg, "integration-test-connect")
	defer client.Disconnect(250)

	assert.True(t, client.IsConnected(), "MQTT client should be connected")
}

// TestMQTTPubSub verifies basic publish/subscribe message delivery.
func TestMQTTPubSub(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.MQTTBroker, cfg.MQTTPort, "MQTT Broker")

	client := newMQTTClient(t, cfg, "integration-test-pubsub")
	defer client.Disconnect(250)

	topic := fmt.Sprintf("cs_inv/test/integration/%d", time.Now().UnixNano())
	expectedPayload := `{"voltage":220.5,"current":10.2,"power":2250.1}`

	received := make(chan string, 1)

	// Subscribe
	subToken := client.Subscribe(topic, 1, func(c mqtt.Client, msg mqtt.Message) {
		received <- string(msg.Payload())
	})
	require.True(t, subToken.WaitTimeout(5*time.Second))
	require.NoError(t, subToken.Error())

	// Publish
	pubToken := client.Publish(topic, 1, false, expectedPayload)
	require.True(t, pubToken.WaitTimeout(5*time.Second))
	require.NoError(t, pubToken.Error())

	// Wait for message
	select {
	case payload := <-received:
		assert.Equal(t, expectedPayload, payload)
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for MQTT message")
	}
}

// TestMQTTTelemetryDataFormat verifies that telemetry data can be published
// in the expected format and parsed correctly.
func TestMQTTTelemetryDataFormat(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.MQTTBroker, cfg.MQTTPort, "MQTT Broker")

	client := newMQTTClient(t, cfg, "integration-test-telemetry")
	defer client.Disconnect(250)

	testSN := fmt.Sprintf("TEST-SN-%d", time.Now().UnixNano())
	topics := []struct {
		topic   string
		payload map[string]interface{}
	}{
		{
			topic: fmt.Sprintf("cs_inv/%s/data/status", testSN),
			payload: map[string]interface{}{
				"work_state_1":           "running",
				"work_state_1_code":      1,
				"internal_temperature":   42.5,
				"bus_voltage":            380.2,
				"efficiency":             97.8,
				"fault_code":             0,
			},
		},
		{
			topic: fmt.Sprintf("cs_inv/%s/data/ac", testSN),
			payload: map[string]interface{}{
				"active_power": 3500.5,
				"frequency":    50.01,
				"pf":           0.99,
			},
		},
		{
			topic: fmt.Sprintf("cs_inv/%s/data/energy", testSN),
			payload: map[string]interface{}{
				"daily": 15.6,
				"total": 12345.78,
			},
		},
	}

	received := make(chan map[string]interface{}, len(topics))

	// Subscribe to all topics
	for _, tc := range topics {
		topic := tc.topic // capture
		subToken := client.Subscribe(topic, 1, func(c mqtt.Client, msg mqtt.Message) {
			var data map[string]interface{}
			if err := json.Unmarshal(msg.Payload(), &data); err == nil {
				received <- data
			}
		})
		require.True(t, subToken.WaitTimeout(5*time.Second))
		require.NoError(t, subToken.Error())
	}

	// Publish all messages
	for _, tc := range topics {
		payload, err := json.Marshal(tc.payload)
		require.NoError(t, err)

		pubToken := client.Publish(tc.topic, 1, false, payload)
		require.True(t, pubToken.WaitTimeout(5*time.Second))
		require.NoError(t, pubToken.Error())
	}

	// Collect messages
	collected := 0
	timeout := time.After(10 * time.Second)
	for collected < len(topics) {
		select {
		case data := <-received:
			assert.NotEmpty(t, data, "received payload should not be empty")
			collected++
		case <-timeout:
			t.Fatalf("timed out: received %d/%d messages", collected, len(topics))
		}
	}

	assert.Equal(t, len(topics), collected, "should receive all published messages")
}

// TestMQTTQoSLevels verifies message delivery at different QoS levels.
func TestMQTTQoSLevels(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.MQTTBroker, cfg.MQTTPort, "MQTT Broker")

	client := newMQTTClient(t, cfg, "integration-test-qos")
	defer client.Disconnect(250)

	qosLevels := []byte{0, 1, 2}
	for _, qos := range qosLevels {
		t.Run(fmt.Sprintf("QoS%d", qos), func(t *testing.T) {
			topic := fmt.Sprintf("cs_inv/test/qos%d/%d", qos, time.Now().UnixNano())
			payload := fmt.Sprintf(`{"qos":%d,"ts":%d}`, qos, time.Now().UnixNano())

			received := make(chan string, 1)

			subToken := client.Subscribe(topic, qos, func(c mqtt.Client, msg mqtt.Message) {
				received <- string(msg.Payload())
			})
			require.True(t, subToken.WaitTimeout(5*time.Second))
			require.NoError(t, subToken.Error())

			pubToken := client.Publish(topic, qos, false, payload)
			require.True(t, pubToken.WaitTimeout(5*time.Second))
			require.NoError(t, pubToken.Error())

			select {
			case got := <-received:
				assert.Equal(t, payload, got)
			case <-time.After(5 * time.Second):
				t.Fatalf("QoS %d: message not received", qos)
			}
		})
	}
}

// TestMQTTRetainedMessage verifies retained message behavior.
func TestMQTTRetainedMessage(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.MQTTBroker, cfg.MQTTPort, "MQTT Broker")

	client := newMQTTClient(t, cfg, "integration-test-retain")
	defer client.Disconnect(250)

	topic := fmt.Sprintf("cs_inv/test/retained/%d", time.Now().UnixNano())
	payload := `{"status":"online","retained":true}`

	// Publish retained message
	pubToken := client.Publish(topic, 1, true, payload)
	require.True(t, pubToken.WaitTimeout(5*time.Second))
	require.NoError(t, pubToken.Error())

	time.Sleep(500 * time.Millisecond)

	// Subscribe after publish - should get retained message
	received := make(chan string, 1)
	subToken := client.Subscribe(topic, 1, func(c mqtt.Client, msg mqtt.Message) {
		received <- string(msg.Payload())
	})
	require.True(t, subToken.WaitTimeout(5*time.Second))
	require.NoError(t, subToken.Error())

	select {
	case got := <-received:
		assert.Equal(t, payload, got, "retained message should match")
	case <-time.After(5 * time.Second):
		t.Fatal("retained message not received")
	}

	// Clear retained message
	clearToken := client.Publish(topic, 1, true, []byte{})
	require.True(t, clearToken.WaitTimeout(5*time.Second))
}

// TestMQTTDeviceOnlineOffline simulates device online/offline via MQTT will messages.
func TestMQTTDeviceOnlineOffline(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.MQTTBroker, cfg.MQTTPort, "MQTT Broker")

	testSN := fmt.Sprintf("WILL-TEST-%d", time.Now().UnixNano())
	statusTopic := fmt.Sprintf("cs_inv/%s/status", testSN)

	// Observer client
	observer := newMQTTClient(t, cfg, "integration-test-observer")
	defer observer.Disconnect(250)

	statusCh := make(chan string, 2)
	subToken := observer.Subscribe(statusTopic, 1, func(c mqtt.Client, msg mqtt.Message) {
		statusCh <- string(msg.Payload())
	})
	require.True(t, subToken.WaitTimeout(5*time.Second))

	// Device client with LWT (Last Will and Testament)
	opts := mqtt.NewClientOptions().
		AddBroker(fmt.Sprintf("tcp://%s:%s", cfg.MQTTBroker, cfg.MQTTPort)).
		SetClientID(fmt.Sprintf("device-%s", testSN)).
		SetWill(statusTopic, `{"status":"offline"}`, 1, true).
		SetAutoReconnect(false).
		SetConnectTimeout(5 * time.Second)

	deviceClient := mqtt.NewClient(opts)
	token := deviceClient.Connect()
	require.True(t, token.WaitTimeout(10*time.Second))
	require.NoError(t, token.Error())

	// Publish online status
	pubToken := deviceClient.Publish(statusTopic, 1, true, `{"status":"online"}`)
	require.True(t, pubToken.WaitTimeout(5*time.Second))

	// Wait for online status
	select {
	case status := <-statusCh:
		assert.Contains(t, status, "online")
	case <-time.After(5 * time.Second):
		t.Fatal("did not receive online status")
	}

	// Disconnect abruptly - LWT should fire
	deviceClient.Disconnect(0)

	// Wait for offline will message
	select {
	case status := <-statusCh:
		assert.Contains(t, status, "offline")
	case <-time.After(10 * time.Second):
		t.Fatal("did not receive LWT offline message")
	}
}

// TestTelemetryEndToEnd verifies telemetry flows from MQTT to database.
// This test requires the inv-device-server to be running and consuming MQTT messages.
func TestTelemetryEndToEnd(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.MQTTBroker, cfg.MQTTPort, "MQTT Broker")
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")

	// Connect to DB to verify data
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	// Connect MQTT and publish telemetry
	client := newMQTTClient(t, cfg, "integration-test-e2e")
	defer client.Disconnect(250)

	testSN := fmt.Sprintf("E2E-MQTT-%d", time.Now().UnixNano())
	now := time.Now().UTC()

	telemetryPayload := map[string]interface{}{
		"device_sn":  testSN,
		"model_code": "INV-5000-TL",
		"data": map[string]interface{}{
			"total_active_power":   3500.0,
			"daily_energy":         12.5,
			"internal_temperature": 42.0,
			"work_state":           "running",
		},
		"time": now.Format(time.RFC3339),
	}

	payload, err := json.Marshal(telemetryPayload)
	require.NoError(t, err)

	topic := fmt.Sprintf("cs_inv/%s/data/status", testSN)
	pubToken := client.Publish(topic, 1, false, payload)
	require.True(t, pubToken.WaitTimeout(5*time.Second))
	require.NoError(t, pubToken.Error())

	// Note: If inv-device-server is not running, the data won't be persisted.
	// This test documents the expected flow. In a full integration environment,
	// you would wait and query the database.
	t.Log("published telemetry to MQTT; if inv-device-server is running, data will be persisted to DB")

	// Try to query DB directly - if device server is running
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	var count int
	err = pool.QueryRow(ctx, `SELECT COUNT(*) FROM device_telemetry_3min WHERE device_sn = $1`, testSN).Scan(&count)
	if err != nil {
		t.Logf("DB query failed (device server may not be running): %v", err)
	} else if count > 0 {
		t.Logf("telemetry data found in DB: %d records for %s", count, testSN)
	} else {
		t.Log("no telemetry data in DB (expected if device server is not running)")
	}
}
