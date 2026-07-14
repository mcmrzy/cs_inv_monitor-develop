package handler

import (
	"os"
	"runtime"
	"runtime/debug"
	"strconv"
	"strings"
)

func readSystemCPUUsage() float64 {
	data, err := os.ReadFile("/proc/loadavg")
	if err != nil {
		return 0
	}
	fields := strings.Fields(string(data))
	if len(fields) == 0 {
		return 0
	}
	load, err := strconv.ParseFloat(fields[0], 64)
	if err != nil || runtime.NumCPU() <= 0 {
		return 0
	}
	usage := load / float64(runtime.NumCPU()) * 100
	if usage > 100 {
		return 100
	}
	return usage
}

func applicationVersion() string {
	if version := strings.TrimSpace(os.Getenv("APP_VERSION")); version != "" {
		return version
	}
	if info, ok := debug.ReadBuildInfo(); ok {
		if info.Main.Version != "" && info.Main.Version != "(devel)" {
			return info.Main.Version
		}
		for _, setting := range info.Settings {
			if setting.Key == "vcs.revision" && setting.Value != "" {
				if len(setting.Value) > 12 {
					return setting.Value[:12]
				}
				return setting.Value
			}
		}
	}
	return "development"
}
