package service

import (
	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
	"testing"
)

func TestTaskProgressKeepsActivePhaseSeparateFromOverall(t *testing.T) {
	phase, overall := 0, 70
	got := aggregateDeviceTaskOTAStatus("SN", 42, []model.DeviceUpgrade{
		{Status: "success", TargetChip: "arm", Progress: 100},
		{Status: "upgrading", TargetChip: "dsp", Stage: "installing", Progress: 70, StageProgress: &phase, OverallProgress: &overall},
		{Status: "pending", TargetChip: "esp"},
	})
	require.Equal(t, "upgrading", got.Status)
	require.Equal(t, "installing", got.Stage)
	require.Equal(t, "dsp", got.TargetChip)
	require.Equal(t, &phase, got.StageProgress)
	require.Equal(t, 56, got.Progress)
	require.Equal(t, 56, *got.OverallProgress)
}

func TestTaskPhase100DoesNotComplete(t *testing.T) {
	phase := 100
	got := aggregateDeviceTaskOTAStatus("SN", 42, []model.DeviceUpgrade{
		{Status: "upgrading", Stage: "verifying", Progress: 100, StageProgress: &phase},
	})
	require.Equal(t, "upgrading", got.Status)
	require.Nil(t, got.OverallProgress)
}
