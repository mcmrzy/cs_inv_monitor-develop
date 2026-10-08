package repository

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
	"inv-device-server/internal/telemetry"
)

func TestSampleRowPreservesBMSSummary(t *testing.T) {
	s := &telemetry.Sample{RawEnvelope: []byte(`{"v":3}`), BMSSummary: map[string]any{"current": -1.23, "raw_bytes": make([]int, 100)}}
	raw, err := json.Marshal(sampleRow(s))
	require.NoError(t, err)
	var row map[string]any
	require.NoError(t, json.Unmarshal(raw, &row))
	bms := row["bms_summary"].(map[string]any)
	require.Equal(t, -1.23, bms["current"])
	require.Len(t, bms["raw_bytes"], 100)
}
