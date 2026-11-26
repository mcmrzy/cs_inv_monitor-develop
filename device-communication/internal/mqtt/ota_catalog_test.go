package mqtt

import "testing"

func TestCatalogDispatchPreservesOTA(t *testing.T) {
	c := &Client{}
	calls := 0
	c.SetPanelQueryHandler(func(sn string, payload []byte) bool { calls++; return sn == "MB00001122334455" })
	query := []byte(`{"v":1,"data":{"type":"catalog.query"}}`)
	topic := "cs_inv/MB00001122334455/ota/status"
	if !c.dispatchPanelRPC(topic, query, false) || calls != 1 {
		t.Fatal("query was not routed")
	}
	if !c.dispatchPanelRPC(topic, query, true) || calls != 1 {
		t.Fatal("retained query was executed")
	}
	if c.dispatchPanelRPC(topic, []byte(`{"v":1,"data":{"type":"weather.query"}}`), false) || calls != 1 {
		t.Fatal("a non-catalog request was intercepted")
	}
	for _, other := range []string{"cs_inv/MB00001122334455/ota/cmd", "cs_inv/MB00001122334455/status", "bad"} {
		if c.dispatchPanelRPC(other, query, false) {
			t.Fatalf("wrong topic consumed: %s", other)
		}
	}
	if c.dispatchPanelRPC(topic, []byte(`{"state":"downloading","progress":30}`), false) {
		t.Fatal("ordinary OTA status was intercepted")
	}
	if !c.dispatchPanelRPC("cs_inv/MB00001122334455/ota/cmd", []byte(`{"action":"catalog"}`), false) {
		t.Fatal("catalog response would refresh device heartbeat")
	}
	if c.dispatchPanelRPC("cs_inv/MB00001122334455/ota/cmd", []byte(`{"action":"start"}`), false) {
		t.Fatal("ordinary OTA command was intercepted")
	}
}
