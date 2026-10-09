package model

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestDeviceUpgradeChangelogJSONContract(t *testing.T) {
	withLog, err := json.Marshal(DeviceUpgrade{Changelog: "Improve reconnect stability"})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(withLog), `"changelog":"Improve reconnect stability"`) {
		t.Fatalf("expected changelog in response, got %s", withLog)
	}

	withoutLog, err := json.Marshal(DeviceUpgrade{})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(withoutLog), `"changelog"`) {
		t.Fatalf("expected empty changelog to be omitted, got %s", withoutLog)
	}
}

func TestDeviceUpgradePhaseJSONPreservesZeroAndOmitsUnknown(t *testing.T) {
	zero, overall := 0, 70
	data, err := json.Marshal(DeviceUpgrade{Stage: "installing", Progress: 70, StageProgress: &zero, OverallProgress: &overall})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `"stage_progress":0`) || !strings.Contains(string(data), `"overall_progress":70`) {
		t.Fatalf("missing phase contract: %s", data)
	}
	data, err = json.Marshal(DeviceUpgrade{Progress: 84})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), `"stage_progress"`) || strings.Contains(string(data), `"overall_progress"`) {
		t.Fatalf("legacy progress must remain unknown: %s", data)
	}
}
