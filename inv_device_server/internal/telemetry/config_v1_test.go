package telemetry

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestParseReportedConfig(t *testing.T) {
	cfg, err := ParseReportedConfig([]byte(`{"v":1,"t":1783676932,"rev":42,"inv":[1,6200,6200,6200,200,950,0,0],"bms":[1,1,500,1000,584,430],"parallel":[0,0,0,null]}`))
	require.NoError(t, err)
	require.Equal(t, uint64(42), cfg.Revision)
	require.Equal(t, int64(6200), cfg.Values["power_limit_w"])
	require.Equal(t, true, cfg.Values["ac_enabled"])
}

func TestParseReportedConfigRejectsUnsafeState(t *testing.T) {
	_, err := ParseReportedConfig([]byte(`{"v":1,"t":1,"rev":1,"inv":[1,6200,6200,6200,200,950,1,1],"bms":[1,1,500,1000,584,430],"parallel":[0,0,0,null]}`))
	require.Error(t, err)
}
