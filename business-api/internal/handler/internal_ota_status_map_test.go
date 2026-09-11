package handler

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

// deviceOTAStates 是固件 ota_state_name() 的完整词表
// （esp32c3_l10_idf/main/ota/ota_service.c），设备上线时原样透传给 API。
// 设备端新增状态时这里必须先红一次，避免再出现"设备报了、后台不认"的静默卡住。
var deviceOTAStates = []string{
	"idle", "accepted", "downloading", "receiving", "verifying",
	"installing", "cancelling", "cancelled", "rebooting",
	"succeeded", "failed", "rolled_back",
}

// 设备上报 succeeded 却一直显示「升级中」的回归用例：
// 旧实现只认 done/completed，succeeded 落进 default 被忽略，记录永远停在 upgrading。
func TestMapDeviceOTAStatus_设备词表全覆盖(t *testing.T) {
	for _, state := range deviceOTAStates {
		dbStatus, known := mapDeviceOTAStatus(state)
		if state == "idle" {
			assert.False(t, known, "idle 不应产生状态更新")
			continue
		}
		assert.True(t, known, "设备状态 %q 未映射，会被静默忽略", state)
		assert.NotEmpty(t, dbStatus, "设备状态 %q 映射为空", state)
	}
}

func TestMapDeviceOTAStatus_映射结果(t *testing.T) {
	cases := map[string]string{
		"accepted":    "upgrading",
		"downloading": "upgrading",
		"receiving":   "upgrading",
		"verifying":   "upgrading",
		"installing":  "upgrading",
		"rebooting":   "upgrading",
		"succeeded":   "success",
		"done":        "success",
		"completed":   "success",
		"failed":      "failed",
		"rolled_back": "failed",
		"cancelling":  "cancelled",
		"cancelled":   "cancelled",
	}
	for deviceState, want := range cases {
		got, known := mapDeviceOTAStatus(deviceState)
		assert.True(t, known, "设备状态 %q 应被识别", deviceState)
		assert.Equal(t, want, got, "设备状态 %q", deviceState)
	}
}

// 大小写/空白容错：不同固件线可能写成 Success 或带空格，不应再静默忽略。
func TestMapDeviceOTAStatus_大小写与空白容错(t *testing.T) {
	for _, input := range []string{"SUCCEEDED", "Success", " succeeded "} {
		got, known := mapDeviceOTAStatus(input)
		assert.True(t, known, "输入 %q 应被识别", input)
		assert.Equal(t, "success", got, "输入 %q", input)
	}
}

func TestMapDeviceOTAStatus_未知状态忽略(t *testing.T) {
	for _, input := range []string{"", "idle", "unknown_state", "booting"} {
		_, known := mapDeviceOTAStatus(input)
		assert.False(t, known, "输入 %q 应保持忽略以免覆盖有效状态", input)
	}
}
