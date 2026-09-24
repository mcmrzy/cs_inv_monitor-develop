package handler

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"inv-api-server/internal/model"

	"github.com/stretchr/testify/assert"
)

// TestBuildAppUpgradePackagesPayload 验证 APP 端升级包列表响应：
// 仅保留已发布包，items 携带固件库下载所需的完整元数据。
func TestBuildAppUpgradePackagesPayload(t *testing.T) {
	now := time.Date(2026, 8, 1, 10, 0, 0, 0, time.UTC)
	list := []model.UpgradePackage{
		{
			ID:            1,
			Model:         "CS-INV-6K2",
			MainVersion:   "V1.0.1.20260801",
			UserVersion:   "V1.0.1",
			UserChangelog: "修复夜间误断",
			Changelog:     "internal notes",
			IsPublished:   true,
			IsForce:       true,
			CreatedAt:     now,
			Items: []model.UpgradePackageItem{
				{
					ID:               11,
					PackageID:        1,
					FirmwareID:       101,
					TargetChip:       "dsp",
					FirmwareVersion:  "1.2.1",
					FileURL:          "/firmware/dsp_1.2.1.bin",
					FileSize:         1024,
					FileMD5:          "md5hash",
					FileSHA256:       "sha256hash",
					SecurityVersion:  3,
					ReleaseSignature: "sig-base64",
				},
				{
					ID:              12,
					PackageID:       1,
					FirmwareID:      102,
					TargetChip:      "legacy", // 未知目标：supported_channels 必须省略
					FirmwareVersion: "0.0.1",
					FileURL:         "/firmware/legacy_0.0.1.bin",
					FileSize:        128,
				},
			},
		},
		{
			ID:          2,
			Model:       "CS-INV-6K2",
			MainVersion: "V1.0.2.20260802",
			IsPublished: false, // 未发布：必须被过滤
			CreatedAt:   now,
		},
	}

	buildURL := func(fileURL string) string {
		return "https://cdn.example.com" + fileURL
	}

	payload := buildAppUpgradePackagesPayload(list, buildURL)
	raw, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}

	var decoded struct {
		Packages []struct {
			ID            int64  `json:"id"`
			MainVersion   string `json:"main_version"`
			UserVersion   string `json:"user_version"`
			UserChangelog string `json:"user_changelog"`
			IsForce       bool   `json:"is_force"`
			Model         string `json:"model"`
			Items         []struct {
				TargetChip        string   `json:"target_chip"`
				FirmwareVersion   string   `json:"firmware_version"`
				FirmwareID        int64    `json:"firmware_id"`
				DownloadURL       string   `json:"download_url"`
				FileName          string   `json:"file_name"`
				FileSize          int64    `json:"file_size"`
				FileMD5           string   `json:"file_md5"`
				FileSHA256        string   `json:"file_sha256"`
				SecurityVersion   uint32   `json:"security_version"`
				ReleaseSignature  string   `json:"release_signature"`
				SupportedChannels []string `json:"supported_channels"`
			} `json:"items"`
		} `json:"packages"`
	}
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatalf("unmarshal payload: %v", err)
	}

	if len(decoded.Packages) != 1 {
		t.Fatalf("expected 1 published package, got %d", len(decoded.Packages))
	}
	pkg := decoded.Packages[0]
	if pkg.ID != 1 || pkg.UserVersion != "V1.0.1" || !pkg.IsForce {
		t.Fatalf("package fields mismatch: %+v", pkg)
	}
	if len(pkg.Items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(pkg.Items))
	}
	item := pkg.Items[0]
	if item.FirmwareID != 101 {
		t.Errorf("firmware_id = %d, want 101", item.FirmwareID)
	}
	if !strings.HasPrefix(item.DownloadURL, "https://cdn.example.com/firmware/") {
		t.Errorf("download_url = %q, want CDN-prefixed firmware path", item.DownloadURL)
	}
	if item.FileName != "dsp_1.2.1.bin" {
		t.Errorf("file_name = %q, want dsp_1.2.1.bin", item.FileName)
	}
	if item.FileSize != 1024 || item.FileMD5 != "md5hash" || item.FileSHA256 != "sha256hash" {
		t.Errorf("file metadata mismatch: %+v", item)
	}
	if item.SecurityVersion != 3 || item.ReleaseSignature != "sig-base64" {
		t.Errorf("security metadata mismatch: %+v", item)
	}
	// DSP 走近场升级只允许 BLE：App 预下载按该列表做通道门控
	assert.Equal(t, []string{"remote", "ble"}, item.SupportedChannels)

	// 未知目标必须省略 supported_channels（nil），App 侧维持 ESP/ARM 旧兼容语义
	legacy := pkg.Items[1]
	if legacy.SupportedChannels != nil {
		t.Errorf("unknown target supported_channels = %v, want omitted (nil)", legacy.SupportedChannels)
	}
}

// TestBuildAppUpgradePackagesPayloadEmpty 空列表返回空数组而非 null
func TestBuildAppUpgradePackagesPayloadEmpty(t *testing.T) {
	payload := buildAppUpgradePackagesPayload(nil, func(s string) string { return s })
	raw, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}
	if !strings.Contains(string(raw), `"packages":[]`) {
		t.Fatalf("expected empty packages array, got %s", raw)
	}
}
