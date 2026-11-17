package service

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

func TestModbusTelemetryIdentitySurvivesServiceRestart(t *testing.T) {
	cache := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: cache.Addr()})
	defer rdb.Close()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	p := &ProtocolParser{rdb: rdb, apiServer: server.URL, httpClient: server.Client()}
	ctx := context.Background()

	require.Empty(t, p.modbusTelemetryModel(ctx, "PANEL"))
	require.NoError(t, p.handleInfo(ctx, &RawMessage{SN: "PANEL", Payload: []byte(
		`{"model":"12KU","dsp_protocol":"modbus_rtu_v1.27","modbus_ac_power":true}`,
	)}))
	require.Equal(t, "12KU", p.modbusTelemetryModel(ctx, "PANEL"))
	require.Equal(t, "modbus_rtu_v1.27:ac_power", rdb.Get(ctx, "device:control:dsp_protocol:PANEL").Val())
	cache.FastForward(11 * time.Minute)
	restarted := &ProtocolParser{rdb: rdb}
	require.Equal(t, "12KU", restarted.modbusTelemetryModel(ctx, "PANEL"))

	require.NoError(t, p.handleInfo(ctx, &RawMessage{SN: "PANEL", Payload: []byte(
		`{"model":"3KU","dsp_protocol":"modbus_rtu_v1.27"}`,
	)}))
	require.Equal(t, "3KU", p.modbusTelemetryModel(ctx, "PANEL"))
	require.Equal(t, "modbus_rtu_v1.27", rdb.Get(ctx, "device:control:dsp_protocol:PANEL").Val())

	require.NoError(t, p.handleInfo(ctx, &RawMessage{SN: "PANEL", Payload: []byte(
		`{"model":"3KU","dsp_protocol":"modbus_rtu_v1.27","modbus_ac_power":true,"modbus_battery_settings":true}`,
	)}))
	require.Equal(t, "modbus_rtu_v1.27:ac_power:battery_settings", rdb.Get(ctx, "device:control:dsp_protocol:PANEL").Val())

	require.NoError(t, p.handleInfo(ctx, &RawMessage{SN: "PANEL", Payload: []byte(
		`{"model":"3KU","dsp_protocol":"modbus_rtu_v1.27","modbus_ac_power":true,"modbus_battery_settings":true,"modbus_system_settings":true}`,
	)}))
	require.Equal(t, "modbus_rtu_v1.27:ac_power:battery_settings:system_settings", rdb.Get(ctx, "device:control:dsp_protocol:PANEL").Val())
	require.NoError(t, p.handleInfo(ctx, &RawMessage{SN: "PANEL", Payload: []byte(
		`{"model":"3KU","dsp_protocol":"modbus_rtu_v1.27","modbus_ac_power":true}`,
	)}))
	require.Equal(t, "modbus_rtu_v1.27:ac_power", rdb.Get(ctx, "device:control:dsp_protocol:PANEL").Val())

	require.NoError(t, p.handleInfo(ctx, &RawMessage{SN: "PANEL", Payload: []byte(
		`{"model":"12KU","dsp_protocol":"unknown"}`,
	)}))
	require.Empty(t, p.modbusTelemetryModel(ctx, "PANEL"))
}
