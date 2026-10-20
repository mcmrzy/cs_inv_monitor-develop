package service

import (
	"encoding/json"
	"testing"
	"time"
)

func TestCommandResultIdentityComesFromMqttRoute(t *testing.T) {
	data, err := normalizeCommandResultPayload("ROUTE-SN", []byte(`{"sn":"FORGED-SN","task_id":"p0","result":"OK"}`))
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]interface{}
	if err = json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	if got["sn"] != "ROUTE-SN" {
		t.Fatalf("payload replaced trusted route identity: %s", data)
	}
}

func TestQueuedCommandExpiresAtBoundary(t *testing.T) {
	raw, _ := json.Marshal(map[string]interface{}{"command": "set_control", "task_id": "expired-boundary", "expires_at": time.Now().Unix()})
	if _, err := decodePendingCommand("SN001", raw); err == nil {
		t.Fatal("command accepted at its expires_at second")
	}
}
