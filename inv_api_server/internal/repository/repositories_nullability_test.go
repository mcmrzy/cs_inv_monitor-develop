package repository

import (
	"strings"
	"testing"
)

// These fixtures mirror nullable columns in the production schema. List
// repositories scan them into non-nullable model fields, so the SELECT clause
// is the compatibility boundary that must turn database NULL into a scalar.
func TestStationListSelectColumnsNormalizesNullableFixture(t *testing.T) {
	nullFixture := map[string]string{
		"province":    "coalesce(province, '')",
		"city":        "coalesce(city, '')",
		"district":    "coalesce(district, '')",
		"address":     "coalesce(address, '')",
		"capacity":    "coalesce(capacity, 0)",
		"panel_count": "coalesce(panel_count, 0)",
		"latitude":    "coalesce(latitude, 0)",
		"longitude":   "coalesce(longitude, 0)",
		"timezone":    "coalesce(timezone, 'asia/shanghai')",
	}

	selectSQL := strings.ToLower(stationListSelectColumns)
	for field, expression := range nullFixture {
		if !strings.Contains(selectSQL, expression) {
			t.Errorf("nullable station fixture field %q is not normalized by %q", field, expression)
		}
	}
}

func TestDeviceListSelectColumnsNormalizesNullableFixture(t *testing.T) {
	nullFixture := map[string]string{
		"model":           "coalesce(d.model, '')",
		"manufacturer":    "coalesce(d.manufacturer,'')",
		"firmware_arm":    "coalesce(d.firmware_arm,'')",
		"firmware_esp":    "coalesce(d.firmware_esp,'')",
		"firmware_dsp":    "coalesce(d.firmware_dsp,'')",
		"firmware_bms":    "coalesce(d.firmware_bms,'')",
		"main_version":    "coalesce(d.main_version,'')",
		"device_type":     "coalesce(d.device_type,'')",
		"rated_power":     "coalesce(d.rated_power,0)",
		"rated_voltage":   "coalesce(d.rated_voltage,0)",
		"rated_freq":      "coalesce(d.rated_freq,0)",
		"battery_voltage": "coalesce(d.battery_voltage,0)",
		"battery_type":    "coalesce(d.battery_type,'')",
		"cell_count":      "coalesce(d.cell_count,0)",
		"timezone":        "coalesce(d.timezone,'asia/shanghai')",
		"current_power":   "coalesce(rd.total_active_power, 0)",
		"daily_energy":    "coalesce(rd.daily_energy, 0)",
		"station_name":    "coalesce(s.name, '')",
	}

	selectSQL := strings.ToLower(deviceListSelectColumns)
	for field, expression := range nullFixture {
		if !strings.Contains(selectSQL, expression) {
			t.Errorf("nullable device fixture field %q is not normalized by %q", field, expression)
		}
	}
}
