package telemetry

import (
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

const validHeartbeat = `{"v":1,"t":1783676930,"seq":38192,"ac":[221.5,8.88,1947.9,1967.6,50.08,0.99,31.4,2.5],"bat":[75,96,51.2,25.5,1305.6,78.5,100,152,28.5,25,3.35,3.28,0.07,1,0,0,60,120,54.6,44,26.5],"pv":[85.3,12.5,1066.3,92.5,1150,82.1,11.8,969,88.2,1050,2035.3,0],"sys":[1,0,0,48.5,55.2,32,380,8640,60,94.6],"eng":[8.56,1250.3,7.8,1100.5,6.2,980.8,6,950.2],"cells":[[3.32,3.33],[26.5,26.8]]}`

func TestParseHeartbeatV1(t *testing.T) {
	received := time.Unix(1783676935, 0)
	s, err := ParseHeartbeat("H1CNA00135000014", []byte(validHeartbeat), 2, received)
	require.NoError(t, err)
	require.Equal(t, uint32(38192), s.Sequence)
	require.Equal(t, 1947.9, *s.AC.ActivePower)
	require.Equal(t, 25.5, *s.Battery.Current)
	require.Equal(t, 2035.3, *s.PV.TotalPower)
	require.Len(t, s.Cells.Voltages, 2)
	require.Zero(t, s.QualityFlags)
}

func TestParseHeartbeatRejectsArrayLength(t *testing.T) {
	payload := []byte(`{"v":1,"t":1,"seq":1,"ac":[],"bat":[],"pv":[],"sys":[],"eng":[],"cells":[]}`)
	_, err := ParseHeartbeat("sn", payload, 16, time.Now())
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

func TestParseHeartbeatRejectsUnknownVersion(t *testing.T) {
	_, err := ParseHeartbeat("sn", []byte(`{"v":2}`), 16, time.Now())
	require.True(t, errors.Is(err, ErrUnsupportedVersion))
}

func TestParseHeartbeatMarksInvalidFieldOnly(t *testing.T) {
	payload := []byte(validHeartbeat)
	for i := 0; i < len(payload)-4; i++ {
		if string(payload[i:i+4]) == "0.99" {
			copy(payload[i:i+4], []byte("9.99"))
			break
		}
	}
	s, err := ParseHeartbeat("sn", payload, 2, time.Unix(1783676935, 0))
	require.NoError(t, err)
	require.Nil(t, s.AC.PowerFactor)
	require.NotZero(t, s.QualityFlags&QualityOutOfRange)
}
