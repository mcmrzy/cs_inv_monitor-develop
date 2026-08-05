package telemetry

import (
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// V2.1 文档 9.1 完整示例：config 语义键值对（工程单位）。
const validReportedConfigV2 = `{"v":2,"t":1783676800,"data":{
  "rev": 1783676800,
  "params": {
    "set_battery_type": 1,
    "set_max_charge_current": 50,
    "set_soc_cutoff": 20,
    "set_soc_back_utl": 40
  }
}}`

func TestParseReportedConfigV2Valid(t *testing.T) {
	cfg, err := ParseReportedConfigV2([]byte(validReportedConfigV2))
	require.NoError(t, err)
	require.Equal(t, uint16(2), cfg.ProtocolVersion)
	require.Equal(t, int64(1783676800), cfg.EventTime.Unix())
	require.Equal(t, uint64(1783676800), cfg.Revision)
	require.Equal(t, 4, len(cfg.Values))
	require.Equal(t, float64(1), cfg.Values["set_battery_type"])
	require.Equal(t, float64(50), cfg.Values["set_max_charge_current"])
}

func TestParseReportedConfigV2RejectsWrongVersion(t *testing.T) {
	payload := []byte(`{"v":1,"t":1,"data":{"rev":1,"params":{}}}`)
	_, err := ParseReportedConfigV2(payload)
	require.True(t, errors.Is(err, ErrUnsupportedVersion))
}

func TestParseReportedConfigV2RequiresRev(t *testing.T) {
	payload := []byte(`{"v":2,"t":1783676800,"data":{"params":{"set_battery_type":1}}}`)
	_, err := ParseReportedConfigV2(payload)
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

func TestParseReportedConfigV2RequiresTimestamp(t *testing.T) {
	payload := []byte(`{"v":2,"t":0,"data":{"rev":1,"params":{}}}`)
	_, err := ParseReportedConfigV2(payload)
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

func TestParseReportedConfigV2RejectsNonNumericParam(t *testing.T) {
	payload := []byte(`{"v":2,"t":1,"data":{"rev":1,"params":{"set_battery_type":"LiFePO4"}}}`)
	_, err := ParseReportedConfigV2(payload)
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

func TestParseReportedConfigV2EventTimeUTC(t *testing.T) {
	cfg, err := ParseReportedConfigV2([]byte(`{"v":2,"t":1783676800,"data":{"rev":1,"params":{}}}`))
	require.NoError(t, err)
	require.Equal(t, time.Unix(1783676800, 0).UTC(), cfg.EventTime)
}
