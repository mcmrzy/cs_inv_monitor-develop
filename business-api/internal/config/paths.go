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

// ProductSecret returns the device PIN derivation secret (PRODUCT_SECRET env).
// It must match the firmware compile-time constant and factory nameplate
// tools (CS_INV_L10_2026_SECRET, see ble_ct_pin.c / nameplate_gen.py).
// The backend holds the secret only to validate PINs on cloud binding;
// the App never receives it (design doc §8).
func ProductSecret() string {
	return os.Getenv("PRODUCT_SECRET")
}
