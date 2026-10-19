package repository

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestBMSSummaryFreshness(t *testing.T) {
	now := time.Now().UTC()
	for _, age := range []time.Duration{time.Second, 150 * time.Second, 211 * time.Second} {
		s := map[string]interface{}{"updated_at": now.Add(-age).Format(time.RFC3339Nano), "expires_at": now.Add(210*time.Second - age).Format(time.RFC3339Nano), "bms_online": 1, "soc": 88.0}
		markBMSSummaryFreshness(s, now)
		if age > 210*time.Second {
			require.Equal(t, 0, s["bms_online"])
			require.Nil(t, s["soc"])
		} else {
			require.Equal(t, 1, s["bms_online"])
			require.Equal(t, 88.0, s["soc"])
		}
	}
}

func TestBMSSummaryFreshnessPreservesReportedLink(t *testing.T) {
	now := time.Now().UTC()
	for _, reported := range []int{0, 1} {
		s := map[string]interface{}{"bms_online": reported, "expires_at": now.Add(-time.Second).Format(time.RFC3339Nano), "soc": 88.0}
		markBMSSummaryFreshness(s, now)
		markBMSSummaryFreshness(s, now)
		require.Equal(t, reported, s["reported_bms_online"], "expiry must not become evidence of a disconnected BMS")
		require.Equal(t, 0, s["bms_online"], "legacy consumers must continue rejecting stale readings")
		require.Nil(t, s["soc"])
	}
}
