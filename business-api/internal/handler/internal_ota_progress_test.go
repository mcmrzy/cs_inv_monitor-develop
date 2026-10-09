package handler

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestOTAProgressContract(t *testing.T) {
	for _, tc := range []struct {
		body    string
		stage   string
		phase   *int
		overall *int
	}{
		{`{"status":"installing","progress":70,"stage":"installing","stage_progress":0,"overall_progress":70}`, "installing", intPtr(0), intPtr(70)},
		{`{"status":"installing","progress":84}`, "installing", nil, nil},
		{`{"status":"verifying","progress":100,"stage_progress":100}`, "verifying", intPtr(100), nil},
	} {
		var req internalOTAStatusRequest
		require.NoError(t, json.Unmarshal([]byte(tc.body), &req))
		require.NoError(t, req.normalizeProgress())
		require.Equal(t, tc.stage, req.Stage)
		require.Equal(t, tc.phase, req.StageProgress)
		require.Equal(t, tc.overall, req.OverallProgress)
		status, _ := mapDeviceOTAStatus(req.Status)
		require.Equal(t, "upgrading", status)
	}
}

func TestOTAProgressRejectsInvalidPercent(t *testing.T) {
	for _, body := range []string{
		`{"stage_progress":-1}`, `{"stage_progress":101}`,
		`{"overall_progress":-1}`, `{"overall_progress":101}`,
		`{"progress":101}`, `{"stage":"bogus","stage_progress":30}`,
	} {
		var req internalOTAStatusRequest
		require.NoError(t, json.Unmarshal([]byte(body), &req))
		require.Error(t, req.normalizeProgress(), body)
	}
}

func intPtr(n int) *int { return &n }
