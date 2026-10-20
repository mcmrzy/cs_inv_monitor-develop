package service

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"inv-device-server/internal/mqtt"
)

func TestCommandStagesDoNotTriggerFalseReadback(t *testing.T) {
	for _, stage := range []string{"acknowledged", "executing", "submitted", "failed", "unknown"} {
		t.Run(stage, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }))
			defer server.Close()
			hub := mqtt.NewHub(nil)
			parser := &ProtocolParser{apiServer: server.URL, httpClient: server.Client(), hub: hub}
			payload, _ := json.Marshal(map[string]interface{}{"task_id": "p0", "cmd": "set_control", "result": "OK", "stage": stage})
			if err := parser.handleCommandResponse(context.Background(), &RawMessage{SN: "SN001", Payload: payload}); err != nil {
				t.Fatal(err)
			}
			select {
			case <-hub.GetCmdChan():
				t.Fatal("unconfirmed stage triggered query_config")
			default:
			}
		})
	}
}

func TestSubmittedEvidenceForwardedWithoutApplicationClaim(t *testing.T) {
	var got map[string]interface{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&got); err != nil {
			t.Error(err)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	parser := &ProtocolParser{apiServer: server.URL, httpClient: server.Client()}
	payload := []byte(`{"task_id":"p0","cmd":"set_control","result":"OK","err":0,"stage":"submitted","submitted_args":[80],"desired_revision":42}`)
	if err := parser.handleCommandResponse(context.Background(), &RawMessage{SN: "SN001", Payload: payload}); err != nil {
		t.Fatal(err)
	}
	if got["desired_revision"] != float64(42) || got["submitted_args"] == nil {
		t.Fatalf("submission evidence lost: %#v", got)
	}
	if got["reported_revision"] != nil || got["applied_args"] != nil {
		t.Fatalf("submission became application evidence: %#v", got)
	}
}
