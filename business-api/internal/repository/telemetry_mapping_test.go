package repository

import (
	"encoding/binary"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestLegacyCMD08ReadRepairIsIdempotentAndPreservesExpiry(t *testing.T) {
	b := make([]byte, 100)
	b[0] = 1
	for off, value := range map[int]uint16{11: 1250, 13: 2000, 59: 65531, 61: 0, 63: 25, 65: 30, 73: 30, 75: 65531, 77: 35, 79: 26, 81: 20, 93: 123, 95: 560, 98: 560} {
		binary.LittleEndian.PutUint16(b[off:], value)
	}
	bytes := make([]interface{}, 100)
	for i, value := range b {
		bytes[i] = float64(value)
	}
	s := map[string]interface{}{"layout": float64(0), "bms_online": float64(1), "raw_bytes": bytes, "capacity_remain": 1.25, "expires_at": "2026-10-10T00:03:30Z"}
	normalizeLegacyBMSSummary(s)
	require.Equal(t, 125.0, s["capacity_remain"])
	require.Equal(t, 35.0, s["mos_temp"])
	require.Equal(t, []interface{}{float64(-5), float64(0), float64(25), float64(30)}, s["cell_temperatures"])
	require.Equal(t, 56.0, s["charging_voltage"])
	normalizeLegacyBMSSummary(s)
	require.Equal(t, 125.0, s["capacity_remain"])
	require.Equal(t, "2026-10-10T00:03:30Z", s["expires_at"])
	markBMSSummaryFreshness(s, time.Date(2026, 10, 10, 0, 4, 0, 0, time.UTC))
	require.Nil(t, s["charging_voltage"])
	require.Nil(t, s["max_cell_temp"])
}
