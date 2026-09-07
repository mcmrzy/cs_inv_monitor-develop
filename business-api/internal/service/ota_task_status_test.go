package service

import (
	"testing"

	"inv-api-server/internal/model"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAggregateDeviceTaskOTAStatusDoesNotCompleteBeforeAllChipsSucceed(t *testing.T) {
	taskID := int64(42)
	status := aggregateDeviceTaskOTAStatus("SN-001", taskID, []model.DeviceUpgrade{
		{DeviceSN: "SN-001", TaskID: &taskID, TargetChip: "arm", Status: "success", Progress: 100},
		{DeviceSN: "SN-001", TaskID: &taskID, TargetChip: "esp", Status: "pending", Progress: 0},
	})

	require.NotNil(t, status)
	assert.Equal(t, "upgrading", status.Status)
	assert.Equal(t, 50, status.Progress)
	assert.Len(t, status.Items, 2)
}

func TestAggregateDeviceTaskOTAStatusCompletesOnlyWhenAllChipsSucceed(t *testing.T) {
	taskID := int64(43)
	status := aggregateDeviceTaskOTAStatus("SN-001", taskID, []model.DeviceUpgrade{
		{DeviceSN: "SN-001", TaskID: &taskID, TargetChip: "arm", Status: "success", Progress: 100},
		{DeviceSN: "SN-001", TaskID: &taskID, TargetChip: "esp", Status: "success", Progress: 100},
	})

	require.NotNil(t, status)
	assert.Equal(t, "success", status.Status)
	assert.Equal(t, 100, status.Progress)
}

func TestAggregateDeviceTaskOTAStatusPropagatesFailure(t *testing.T) {
	taskID := int64(44)
	status := aggregateDeviceTaskOTAStatus("SN-001", taskID, []model.DeviceUpgrade{
		{DeviceSN: "SN-001", TaskID: &taskID, TargetChip: "arm", Status: "success", Progress: 100},
		{DeviceSN: "SN-001", TaskID: &taskID, TargetChip: "esp", Status: "failed", Progress: 30, ErrorMessage: "checksum mismatch"},
	})

	require.NotNil(t, status)
	assert.Equal(t, "failed", status.Status)
	assert.Equal(t, "checksum mismatch", status.ErrorMessage)
}
