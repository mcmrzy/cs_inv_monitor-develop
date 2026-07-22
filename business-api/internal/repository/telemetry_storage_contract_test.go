package repository

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

func TestRepositoryDoesNotReintroduceDeadLegacyTelemetryMethods(t *testing.T) {
	source, err := os.ReadFile("repositories.go")
	if err != nil {
		t.Fatal(err)
	}
	legacyMethod := regexp.MustCompile(`(?m)^func \([^\n]+\) [A-Za-z0-9_]+Legacy\(`)
	if names := legacyMethod.FindAll(source, -1); len(names) != 0 {
		t.Fatalf("dead legacy repository methods were reintroduced: %q", names)
	}

	// The only deliberate compatibility-view read is the dynamic legacy history
	// response in GetTelemetryData. Realtime, overview and statistics must use
	// the canonical wide/aggregate tables directly.
	if count := strings.Count(string(source), "v_device_telemetry_compat"); count != 1 {
		t.Fatalf("compatibility-view read count = %d, want exactly 1", count)
	}
}

func TestDeviceStatisticsUsesMonthlyAggregateWithDailyFallback(t *testing.T) {
	source, err := os.ReadFile("telemetry_v2_repository.go")
	if err != nil {
		t.Fatal(err)
	}
	text := string(source)
	for _, required := range []string{
		"FROM device_energy_month",
		"SUM(pv_energy) FILTER (WHERE stat_date >= $3::date)",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("device statistics monthly fallback contract is missing %q", required)
		}
	}
}
