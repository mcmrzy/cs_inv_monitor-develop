package service

import (
	"fmt"
	"sort"
	"strings"

	"inv-api-server/internal/model"
)

// NormalizeFirmwareTarget 归一化芯片目标为小写内部标识
func NormalizeFirmwareTarget(target string) (string, error) {
	t := strings.ToLower(strings.TrimSpace(target))
	switch t {
	case model.TargetChipARM, model.TargetChipESP, model.TargetChipDSP, model.TargetChipBMS:
		return t, nil
	default:
		return "", fmt.Errorf("unknown firmware target: %q", target)
	}
}

// OrderFirmwareTargets 将目标芯片按稳定顺序排列，ESP 永远最后
func OrderFirmwareTargets(targets []string) []string {
	rank := map[string]int{
		model.TargetChipBMS: 0,
		model.TargetChipARM: 1,
		model.TargetChipDSP: 2,
		model.TargetChipESP: 3,
	}
	out := make([]string, 0, len(targets))
	seen := make(map[string]struct{}, len(targets))
	for _, raw := range targets {
		t, err := NormalizeFirmwareTarget(raw)
		if err != nil {
			continue
		}
		if _, ok := seen[t]; ok {
			continue
		}
		seen[t] = struct{}{}
		out = append(out, t)
	}
	sort.SliceStable(out, func(i, j int) bool {
		return rank[out[i]] < rank[out[j]]
	})
	return out
}

// CurrentModuleVersion 从设备信息读取指定模块当前版本
func CurrentModuleVersion(deviceModel, arm, esp, dsp, bms, target string) (string, error) {
	t, err := NormalizeFirmwareTarget(target)
	if err != nil {
		return "", err
	}
	_ = deviceModel
	switch t {
	case model.TargetChipARM:
		return strings.TrimSpace(arm), nil
	case model.TargetChipESP:
		return strings.TrimSpace(esp), nil
	case model.TargetChipDSP:
		return strings.TrimSpace(dsp), nil
	case model.TargetChipBMS:
		return strings.TrimSpace(bms), nil
	default:
		return "", fmt.Errorf("unknown firmware target: %q", target)
	}
}

// CompareModuleVersion 比较版本字符串。返回 -1/0/1。
// 仅支持点分数字版本；无法解析时按字符串比较（已上报目录外版本仍可比较）。
func CompareModuleVersion(a, b string) int {
	a = strings.TrimSpace(a)
	b = strings.TrimSpace(b)
	if a == b {
		return 0
	}
	if a == "" {
		return -1
	}
	if b == "" {
		return 1
	}
	pa := strings.Split(a, ".")
	pb := strings.Split(b, ".")
	n := len(pa)
	if len(pb) > n {
		n = len(pb)
	}
	for i := 0; i < n; i++ {
		var va, vb int
		if i < len(pa) {
			fmt.Sscanf(pa[i], "%d", &va)
		}
		if i < len(pb) {
			fmt.Sscanf(pb[i], "%d", &vb)
		}
		if va != vb {
			if va < vb {
				return -1
			}
			return 1
		}
	}
	// 数值相同则回退字符串比较，保证全序
	return strings.Compare(a, b)
}

// VersionState 根据当前版本与最新发布版本计算状态
func VersionState(currentVersion, latestVersion string) (state string, updateAvailable bool) {
	current := strings.TrimSpace(currentVersion)
	latest := strings.TrimSpace(latestVersion)
	if current == "" {
		return "unreported", false
	}
	if latest == "" {
		return "current", false
	}
	if CompareModuleVersion(current, latest) < 0 {
		return "outdated", true
	}
	if CompareModuleVersion(current, latest) > 0 {
		return "different", true
	}
	return "current", false
}

// FirmwareModuleOverview 组装单模块概览
func FirmwareSupportedChannels(target string) []string {
	t, err := NormalizeFirmwareTarget(target)
	if err != nil {
		return []string{}
	}
	if t == model.TargetChipARM || t == model.TargetChipESP {
		return []string{"remote", "ble", "wifi_ap"}
	}
	return []string{"remote"}
}

func FirmwareModuleOverview(target, currentVersion string, deviceOnline bool, latestFirmware *model.Firmware) model.FirmwareModuleOverview {
	t, err := NormalizeFirmwareTarget(target)
	if err != nil {
		t = strings.ToLower(strings.TrimSpace(target))
	}
	ov := model.FirmwareModuleOverview{
		Target:            t,
		CurrentVersion:    strings.TrimSpace(currentVersion),
		Supported:         latestFirmware != nil || strings.TrimSpace(currentVersion) != "",
		Connected:         strings.TrimSpace(currentVersion) != "",
		SupportedChannels: FirmwareSupportedChannels(t),
	}
	if latestFirmware != nil {
		ov.LatestFirmwareID = latestFirmware.ID
		ov.LatestVersion = latestFirmware.Version
		ov.Changelog = latestFirmware.Changelog
		ov.PublishedAt = latestFirmware.PublishedAt
		ov.RolloutPercent = latestFirmware.RolloutPercent
		ov.RolloutType = latestFirmware.RolloutType
	}
	ov.VersionState, ov.UpdateAvailable = VersionState(ov.CurrentVersion, ov.LatestVersion)
	ov.Eligible = deviceOnline && ov.Supported && ov.Connected
	return ov
}
