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
