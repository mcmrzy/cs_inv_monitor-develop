package mqtt

import "testing"

func TestControlPayloadPreservesExpiry(t *testing.T) {
	c := &Client{}
	payload := c.buildMqttPayload(&DeviceCommand{CmdType: "set_control", RawPayload: []byte(`{"task_id":"p0","expires_at":1800000000,"args":[80]}`)})
	if payload["expires_at"] != float64(1800000000) {
		t.Fatalf("expires_at lost: %#v", payload)
	}
}
