package model

import (
	"errors"
	"regexp"
	"sort"
	"strings"
)

var (
	ErrHardwareVersionUnknown      = errors.New("设备硬件版本未确认，无法升级")
	ErrHardwareIncompatible        = errors.New("固件与设备型号或硬件版本不兼容")
	ErrFirmwareHardwareUnspecified = errors.New("固件未设置适用硬件版本")
	ErrFirmwareHardwareImmutable   = errors.New("已发布固件的适用硬件范围不可修改")
)

type DeviceHardwareVersion struct {
	Model       string `json:"model"`
	Version     string `json:"version"`
	Description string `json:"description"`
}

var hardwareVersionPattern = regexp.MustCompile(`^[A-Z0-9][A-Z0-9._-]{0,49}$`)

// NormalizeHardwareVersion preserves meaningful prefixes; aliases are never guessed.
func NormalizeHardwareVersion(version string) string {
	return strings.ToUpper(strings.TrimSpace(version))
}

func NormalizeHardwareVersions(versions []string) ([]string, error) {
	if len(versions) == 0 || len(versions) > 64 {
		return nil, ErrFirmwareHardwareUnspecified
	}
	set := make(map[string]bool, len(versions))
	for _, raw := range versions {
		v := NormalizeHardwareVersion(raw)
		if !hardwareVersionPattern.MatchString(v) {
			return nil, errors.New("硬件版本格式无效，使用字母、数字、点、下划线或短横线")
		}
		set[v] = true
	}
	out := make([]string, 0, len(set))
	for v := range set {
		out = append(out, v)
	}
	sort.Strings(out)
	return out, nil
}

func CheckFirmwareHardware(fw *Firmware, deviceModel, hardwareVersion string) error {
	if NormalizeHardwareVersion(hardwareVersion) == "" {
		return ErrHardwareVersionUnknown
	}
	if fw == nil || fw.Model != deviceModel {
		return ErrHardwareIncompatible
	}
	if len(fw.HardwareVersions) == 0 {
		return ErrFirmwareHardwareUnspecified
	}
	for _, version := range fw.HardwareVersions {
		if NormalizeHardwareVersion(version) == NormalizeHardwareVersion(hardwareVersion) {
			return nil
		}
	}
	return ErrHardwareIncompatible
}
