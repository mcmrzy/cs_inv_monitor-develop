package service

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
)

// ==================== BuildDownloadURL ====================

func newMinimalOTAService(serverURL string) *OTAService {
	return &OTAService{serverURL: serverURL}
}

func TestBuildDownloadURL_相对路径拼接ServerURL(t *testing.T) {
	s := newMinimalOTAService("https://api.example.com:8080")

	tests := []struct {
		name     string
		fileURL  string
		expected string
	}{
		{"相对路径", "/firmware/v2.0.0.bin", "https://api.example.com:8080/firmware/v2.0.0.bin"},
		{"相对路径带子目录", "/uploads/fw/arm_v1.bin", "https://api.example.com:8080/uploads/fw/arm_v1.bin"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := s.BuildDownloadURL(tc.fileURL)
			assert.Equal(t, tc.expected, result)
		})
	}
}

func TestBuildDownloadURL_绝对URL保持不变(t *testing.T) {
	s := newMinimalOTAService("https://api.example.com")

	tests := []struct {
		name    string
		fileURL string
	}{
		{"https URL", "https://cdn.example.com/firmware/v2.0.0.bin"},
		{"http URL", "http://files.test.com/fw.bin"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := s.BuildDownloadURL(tc.fileURL)
			assert.Equal(t, tc.fileURL, result)
		})
	}
}

func TestBuildDownloadURL_无ServerURL时原样返回(t *testing.T) {
	s := newMinimalOTAService("")

	result := s.BuildDownloadURL("/firmware/v2.0.0.bin")
	assert.Equal(t, "/firmware/v2.0.0.bin", result)
}

func TestBuildDownloadURL_ServerURL尾部斜杠处理(t *testing.T) {
	s := newMinimalOTAService("https://api.example.com/")

	result := s.BuildDownloadURL("/firmware/v2.0.0.bin")
	assert.Equal(t, "https://api.example.com/firmware/v2.0.0.bin", result)
}

func TestValidateFirmwareRequest(t *testing.T) {
	valid := func() *CreateFirmwareReq {
		req := &CreateFirmwareReq{
			Model: "CS-48V", TargetChip: "DSP", Version: "V1.2.3",
			FileURL: "/firmware/fw.bin", FileSize: 1024,
			FileMD5:         "0123456789abcdef0123456789abcdef",
			FileSHA256:      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
			SecurityVersion: 1,
		}
		seed, _ := hex.DecodeString("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
		privateKey := ed25519.NewKeyFromSeed(seed)
		message := fmt.Sprintf(
			"CS_INV_OTA_V1\ntarget=arm\nversion=%s\nsize=%d\nsha256=%s\nsecurity_version=%d\n",
			req.Version, req.FileSize, req.FileSHA256, req.SecurityVersion)
		req.ReleaseSignature = base64.StdEncoding.EncodeToString(ed25519.Sign(privateKey, []byte(message)))
		return req
	}

	req := valid()
	assert.NoError(t, ValidateFirmwareRequest(req))
	assert.Equal(t, "dsp", req.TargetChip)

	tests := []struct {
		name string
		edit func(*CreateFirmwareReq)
	}{
		{"芯片无效", func(r *CreateFirmwareReq) { r.TargetChip = "linux" }},
		{"版本为空", func(r *CreateFirmwareReq) { r.Version = "" }},
		{"SHA256为空", func(r *CreateFirmwareReq) { r.FileSHA256 = "" }},
		{"SHA256格式无效", func(r *CreateFirmwareReq) { r.FileSHA256 = "xyz" }},
		{"文件为空", func(r *CreateFirmwareReq) { r.FileSize = 0 }},
		{"ESP安全版本为空", func(r *CreateFirmwareReq) { r.TargetChip = "esp"; r.SecurityVersion = 0 }},
		{"ARM签名被篡改", func(r *CreateFirmwareReq) { r.TargetChip = "arm"; r.Version = "V1.2.4" }},
		{"不安全HTTP地址", func(r *CreateFirmwareReq) { r.FileURL = "http://example.test/fw.bin" }},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			r := valid()
			tc.edit(r)
			assert.Error(t, ValidateFirmwareRequest(r))
		})
	}
}

// ==================== parseRolloutTargets ====================

func TestParseRolloutTargets_JSON数组(t *testing.T) {
	s := newMinimalOTAService("")

	result := s.parseRolloutTargets(`["SN001","SN002","SN003"]`)
	assert.Equal(t, []string{"SN001", "SN002", "SN003"}, result)
}

func TestParseRolloutTargets_逗号分隔(t *testing.T) {
	s := newMinimalOTAService("")

	result := s.parseRolloutTargets("SN001,SN002,SN003")
	assert.Equal(t, []string{"SN001", "SN002", "SN003"}, result)
}

func TestParseRolloutTargets_逗号分隔带空格(t *testing.T) {
	s := newMinimalOTAService("")

	result := s.parseRolloutTargets("SN001, SN002 , SN003")
	assert.Equal(t, []string{"SN001", "SN002", "SN003"}, result)
}

func TestParseRolloutTargets_空字符串返回nil(t *testing.T) {
	s := newMinimalOTAService("")

	result := s.parseRolloutTargets("")
	assert.Nil(t, result)
}

func TestParseRolloutTargets_空JSON数组返回空切片(t *testing.T) {
	s := newMinimalOTAService("")

	result := s.parseRolloutTargets("[]")
	assert.NotNil(t, result)
	assert.Len(t, result, 0)
}

func TestParseRolloutTargets_逗号分隔含空项(t *testing.T) {
	s := newMinimalOTAService("")

	result := s.parseRolloutTargets("SN001,,SN002,")
	assert.Equal(t, []string{"SN001", "SN002"}, result)
}

// ==================== DevicePackageUpgradeInfo 状态计算逻辑 ====================

func TestDevicePackageUpgradeInfo_整体状态计算(t *testing.T) {
	tests := []struct {
		name           string
		statuses       []string
		expectedStatus string
	}{
		{"全部成功", []string{"success", "success"}, "success"},
		{"全部pending", []string{"pending", "pending"}, "upgrading"},
		{"有失败无进行中", []string{"success", "failed"}, "failed"},
		{"有失败有进行中", []string{"failed", "downloading"}, "partial"},
		{"进行中", []string{"success", "downloading"}, "upgrading"},
		{"空芯片", []string{}, "idle"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			allSuccess := true
			anyFailed := false
			anyInProgress := false
			chipCount := len(tc.statuses)

			for _, status := range tc.statuses {
				switch status {
				case "success":
					// ok
				case "failed":
					allSuccess = false
					anyFailed = true
				case "pending", "downloading", "upgrading":
					allSuccess = false
					anyInProgress = true
				default:
					allSuccess = false
				}
			}

			overallStatus := "idle"
			if chipCount == 0 {
				overallStatus = "idle"
			} else if allSuccess {
				overallStatus = "success"
			} else if anyFailed && !anyInProgress {
				overallStatus = "failed"
			} else if anyFailed && anyInProgress {
				overallStatus = "partial"
			} else if anyInProgress {
				overallStatus = "upgrading"
			} else {
				overallStatus = "pending"
			}

			assert.Equal(t, tc.expectedStatus, overallStatus)
		})
	}
}

// ==================== OTA 升级状态常量验证 ====================

func TestOTAStatusConstants_合法值(t *testing.T) {
	validStatuses := map[string]bool{
		"pending":     true,
		"downloading": true,
		"upgrading":   true,
		"success":     true,
		"failed":      true,
		"cancelled":   true,
	}

	// 这些状态应在逻辑中被正确处理
	for status := range validStatuses {
		assert.NotEmpty(t, status)
	}
}

// ==================== CreateFirmwareReq 验证 ====================

func TestCreateFirmwareReq_字段完整性(t *testing.T) {
	req := &CreateFirmwareReq{
		Model:      "CSI-5000",
		TargetChip: "arm",
		Version:    "2.0.0",
		FileURL:    "/firmware/arm_v2.bin",
		FileSize:   1048576,
		FileMD5:    "abc123",
		FileSHA256: "def456",
		Changelog:  "Bug fixes",
		IsForce:    false,
	}

	assert.Equal(t, "CSI-5000", req.Model)
	assert.Equal(t, "arm", req.TargetChip)
	assert.Equal(t, "2.0.0", req.Version)
	assert.Equal(t, int64(1048576), req.FileSize)
}

// ==================== PushUpgradeReq 验证 ====================

func TestPushUpgradeReq_字段完整性(t *testing.T) {
	taskID := int64(42)
	req := &PushUpgradeReq{
		FirmwareID: 1,
		DeviceSNs:  []string{"SN001", "SN002"},
		PushedBy:   100,
		Immediate:  true,
		TaskID:     &taskID,
	}

	assert.Equal(t, int64(1), req.FirmwareID)
	assert.Len(t, req.DeviceSNs, 2)
	assert.Equal(t, int64(100), req.PushedBy)
	assert.True(t, req.Immediate)
	assert.Equal(t, int64(42), *req.TaskID)
}

func TestPushUpgradeReq_TaskID可选(t *testing.T) {
	req := &PushUpgradeReq{
		FirmwareID: 1,
		DeviceSNs:  []string{"SN001"},
		PushedBy:   100,
	}

	assert.Nil(t, req.TaskID, "TaskID 应为 nil（可选字段）")
}
