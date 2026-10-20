package handler

import (
	"encoding/json"
	"testing"
)

func TestCommandResultStages(t *testing.T) {
	zero, failure := 0, -6
	for _, tc := range []struct {
		stage, result string
		success       bool
		code          *int
		want          string
	}{
		{"acknowledged", "OK", true, &zero, "acknowledged"},
		{"executing", "OK", true, &zero, "executing"},
		{"submitted", "OK", true, &zero, "submitted"},
		{"applied", "OK", false, &zero, "success"},
		{"completed", "OK", false, &zero, "success"},
		{"", "OK", false, nil, "success"},
		{"failed", "OK", true, &zero, "failed"},
		{"submitted", "OK", true, &failure, "failed"},
		{"completed", "EXPIRED", true, nil, "failed"},
		{"failed", "IDEMPOTENCY_CONFLICT", false, &failure, "ignored"},
	} {
		t.Run(tc.stage+tc.result, func(t *testing.T) {
			got, err := commandResultStatus(tc.stage, tc.result, tc.success, tc.code)
			if err != nil || got != tc.want {
				t.Fatalf("got %q, %v; want %q", got, err, tc.want)
			}
		})
	}
	if _, err := commandResultStatus("unknown", "OK", true, nil); err == nil {
		t.Fatal("unknown positive stage must not become success")
	}
}

func TestCommandSubmissionEvidenceDoesNotClaimApplication(t *testing.T) {
	rev := uint64(42)
	data := mergeCommandStageData([]byte(`[1,2]`), "submitted", []byte(`[80]`), &rev)
	var got map[string]interface{}
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	if got["stage"] != "submitted" || got["desired_revision"] != float64(42) || got["submitted_args"] == nil || got["result_data"] == nil {
		t.Fatalf("lost submission evidence: %s", data)
	}
	if got["applied_args"] != nil || got["reported_revision"] != nil {
		t.Fatalf("false application evidence: %s", data)
	}
}

func TestCommandResultPredecessors(t *testing.T) {
	for _, next := range []string{"acknowledged", "executing", "submitted", "success", "failed"} {
		for _, previous := range commandResultPredecessors(next, "") {
			if previous == "success" || previous == "failed" || previous == "timeout" || previous == next {
				t.Fatalf("%s can overwrite %s", next, previous)
			}
			if previous == "submitted" && next != "success" && next != "failed" {
				t.Fatalf("%s regresses submitted", next)
			}
		}
	}
	for _, previous := range commandResultPredecessors("failed", "failed") {
		if previous == "submitted" {
			t.Fatal("duplicate conflict can overwrite submission")
		}
	}
	confirmed := false
	for _, previous := range commandResultPredecessors("success", "applied") {
		if previous == "submitted" {
			confirmed = true
		}
	}
	if !confirmed {
		t.Fatal("application confirmation cannot advance submitted")
	}
	if !commandResultTerminal("submitted") || commandResultTerminal("acknowledged") || commandResultTerminal("executing") {
		t.Fatal("submission/acceptance terminal contract broken")
	}
}
