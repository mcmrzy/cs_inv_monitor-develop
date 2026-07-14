package telemetry

import (
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

const validHeartbeat = `{"t":1783676930,"v":1,"data":{"ac":[221.5,8.88,1947.9,1967.6,50.08,0.99,31.4,2.5],"bat":[75,96,51.2,25.5,1305.6,78.5,100,152,28.5,25,3.35,3.28,0.07,1,0,0,60,120,54.6,44,26.5,600,546],"pv":[85.3,12.5,1066.3,82.1,11.8,969,0],"sys":[1,0,0,48.5,55.2,32,380,8640,60,94.6,1],"eng":[8.56,1250.3,7.8,1100.5,6.2,980.8,6,950.2,20500,19800,12000,11500],"cells":[[3.32,3.33],[26.5]]}}`

func TestParseHeartbeatV1(t *testing.T) {
	received := time.Unix(1783676935, 0)
	s, err := ParseHeartbeat("H1CNA00135000014", []byte(validHeartbeat), 2, 1, received)
	require.NoError(t, err)
	require.Equal(t, uint32(0), s.Sequence)
	require.Equal(t, 1947.9, *s.AC.ActivePower)
	require.Equal(t, 25.5, *s.Battery.Current)
	require.InDelta(t, 2035.3, *s.PV.TotalPower, 0.0001)
	require.Len(t, s.Cells.Voltages, 2)
	require.Len(t, s.Cells.Temperatures, 1)
	require.Len(t, s.DataHash, 64)
	require.JSONEq(t, validHeartbeat, string(s.RawEnvelope))
	require.Zero(t, s.QualityFlags)
}

func TestParseHeartbeatRejectsArrayLength(t *testing.T) {
	payload := []byte(`{"v":1,"t":1,"data":{"ac":[],"bat":[],"pv":[],"sys":[],"eng":[],"cells":[]}}`)
	_, err := ParseHeartbeat("sn", payload, 16, 4, time.Now())
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

func TestParseHeartbeatRejectsUnknownVersion(t *testing.T) {
	_, err := ParseHeartbeat("sn", []byte(`{"v":2}`), 16, 4, time.Now())
	require.True(t, errors.Is(err, ErrUnsupportedVersion))
}

func TestParseHeartbeatRejectsLegacyFlatEnvelope(t *testing.T) {
	_, err := ParseHeartbeat("sn", []byte(`{"v":1,"t":1,"ac":[]}`), 16, 4, time.Now())
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

func TestParseHeartbeatFallsBackToReceivedAtForInvalidClock(t *testing.T) {
	payload := []byte(`{"t":0,"v":1,"data":{"ac":[0,0,0,0,0,0,0,0],"bat":[0,0,51.2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,51.2,44,25,0,512],"pv":[0,0,0,0,0,0,0],"sys":[0,0,0,25,25,25,0,0,0,0,0],"eng":[0,0,0,0,0,0,0,0,0,0,0,0],"cells":[[3.2],[25]]}}`)
	received := time.Unix(1783676935, 0).UTC()
	s, err := ParseHeartbeat("sn", payload, 1, 1, received)
	require.NoError(t, err)
	require.Equal(t, received, s.EventTime)
	require.NotZero(t, s.QualityFlags&QualityClockInvalid)
}

func TestParseHeartbeatPreservesOutOfRangeValue(t *testing.T) {
	payload := []byte(validHeartbeat)
	for i := 0; i < len(payload)-4; i++ {
		if string(payload[i:i+4]) == "0.99" {
			copy(payload[i:i+4], []byte("9.99"))
			break
		}
	}
	s, err := ParseHeartbeat("sn", payload, 2, 1, time.Unix(1783676935, 0))
	require.NoError(t, err)
	require.Equal(t, 9.99, *s.AC.PowerFactor)
	require.NotZero(t, s.QualityFlags&QualityOutOfRange)
}
