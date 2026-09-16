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

// stripVersionPrefix 去掉设备上报里常见的 V/v 前缀，便于与目录版本对齐。
func stripVersionPrefix(s string) string {
	s = strings.TrimSpace(s)
	if len(s) > 1 && (s[0] == 'V' || s[0] == 'v') {
		// 仅当 V 后跟数字时剥离，避免误伤普通词
		if s[1] >= '0' && s[1] <= '9' {
			return s[1:]
		}
	}
	return s
}

// parseVersionSegment 解析点分段中的前导数字（支持 "10"、"10-beta" 中的 10）。
func parseVersionSegment(seg string) (int, bool) {
	seg = strings.TrimSpace(seg)
	if seg == "" {
		return 0, false
	}
	end := 0
	for end < len(seg) && seg[end] >= '0' && seg[end] <= '9' {
		end++
	}
	if end == 0 {
		return 0, false
	}
	var n int
	fmt.Sscanf(seg[:end], "%d", &n)
	return n, true
}

func isPureNumericVersion(s string) bool {
	if s == "" {
		return false
	}
	for _, part := range strings.Split(s, ".") {
		if _, ok := parseVersionSegment(part); !ok {
			return false
		}
		if strings.TrimLeft(part, "0123456789") != "" &&
			!strings.ContainsAny(strings.TrimLeft(part, "0123456789"), "-+_") {
			// 段内数字后仍有非分隔字符，视为非纯数字（如 "1a"）
			rest := strings.TrimLeft(part, "0123456789")
			if rest != "" && rest[0] != '-' && rest[0] != '+' && rest[0] != '_' {
				return false
			}
		}
	}
	return true
}

// CompareModuleVersion 比较版本字符串。返回 -1/0/1。
// 会剥离 V/v 前缀；点分段按数字比较，缺段按 0 补齐（1.5 == 1.5.0）。
// 无法解析为数字的段回退字符串比较（保留目录外版本可比较）。
func CompareModuleVersion(a, b string) int {
	a = stripVersionPrefix(a)
	b = stripVersionPrefix(b)
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
	numericOnly := isPureNumericVersion(a) && isPureNumericVersion(b)
	for i := 0; i < n; i++ {
		var va, vb int
		if i < len(pa) {
			if v, ok := parseVersionSegment(pa[i]); ok {
				va = v
			} else if !numericOnly {
				// 非纯数字版本：保留原行为（解析失败按 0）
			}
		}
		if i < len(pb) {
			if v, ok := parseVersionSegment(pb[i]); ok {
				vb = v
			}
		}
		if va != vb {
			if va < vb {
				return -1
			}
			return 1
		}
	}
	// 纯数字且数值等价（1.5 vs 1.5.0）视为相同，避免尾零误判“可升级”
	if numericOnly {
		return 0
	}
	// 数值相同则回退字符串比较，保证全序（如 v2.3-beta）
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
