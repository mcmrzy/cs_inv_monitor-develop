package config

import "os"

// FirmwareDataDir returns the firmware storage directory.
// It reads the FIRMWARE_DATA_DIR environment variable,
// falling back to the default /data/firmware path.
func FirmwareDataDir() string {
	if dir := os.Getenv("FIRMWARE_DATA_DIR"); dir != "" {
		return dir
	}
	return "/data/firmware"
}
