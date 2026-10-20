package handler

import (
	"encoding/json"
	"fmt"
	"strings"
)

const updateCommandResultSQL = `
	WITH updated_log AS (
		UPDATE device_cmd_logs SET status=$2,result=$3,message=$4,data=$5::jsonb
		WHERE task_id=$1 AND device_sn=$6 AND status=ANY($7::text[])
		RETURNING task_id
	), updated_command AS (
		UPDATE device_commands SET status=$2,result_code=COALESCE(NULLIF($8,''),result_code),
			result_message=$4,response_data=COALESCE($5::jsonb,'[]'::jsonb),
			acknowledged_at=CASE WHEN $9 THEN COALESCE(acknowledged_at,NOW()) ELSE acknowledged_at END,
			completed_at=CASE WHEN $10 THEN NOW() ELSE completed_at END
		WHERE task_id::text=$1 AND device_sn=$6 AND status=ANY($7::text[])
			AND EXISTS(SELECT 1 FROM updated_log)
		RETURNING task_id
	)
	SELECT COUNT(*) FROM updated_log`

// commandResultStatus keeps transport acceptance and submission distinct from
// confirmed device application. Legacy OK responses without stage stay supported.
func commandResultStatus(stage, result string, success bool, resultCode *int) (string, error) {
	stage = strings.ToLower(strings.TrimSpace(stage))
	result = strings.ToLower(strings.TrimSpace(result))
	// A conflicting reuse is a different request. The original task may still
	// be running and must remain eligible for its genuine submission result.
	if result == "idempotency_conflict" {
		return "ignored", nil
	}
	if stage == "failed" || (resultCode != nil && *resultCode != 0) || (result != "" && result != "ok" && result != "success") {
		return "failed", nil
	}
	switch stage {
	case "acknowledged", "executing", "submitted":
		return stage, nil
	case "", "applied", "completed":
		if success || result == "ok" || result == "success" {
			return "success", nil
		}
		return "failed", nil
	default:
		return "", fmt.Errorf("unsupported command stage: %s", stage)
	}
}

// Predecessors are applied in SQL while the row is locked by UPDATE, so delayed
// ACKs and duplicate QoS 1 delivery cannot regress or overwrite a final result.
func commandResultPredecessors(status, stage string) []string {
	states := []string{"pending", "queued", "sent"}
	if status != "acknowledged" {
		states = append(states, "acknowledged")
	}
	if status == "submitted" || status == "success" || status == "failed" {
		states = append(states, "executing")
	}
	stage = strings.ToLower(strings.TrimSpace(stage))
	if status == "success" && (stage == "applied" || stage == "completed") {
		states = append(states, "submitted")
	}
	return states
}

func commandResultTerminal(status string) bool {
	return status == "success" || status == "failed" || status == "submitted"
}

func mergeCommandStageData(data json.RawMessage, stage string, submittedArgs json.RawMessage, desiredRevision *uint64) []byte {
	if stage == "" && len(submittedArgs) == 0 && desiredRevision == nil {
		return data
	}
	merged := map[string]json.RawMessage{}
	if len(data) > 0 && string(data) != "null" {
		if json.Unmarshal(data, &merged) != nil || merged == nil {
			merged = map[string]json.RawMessage{"result_data": data}
		}
	}
	if merged == nil {
		merged = map[string]json.RawMessage{}
	}
	if stage != "" {
		merged["stage"], _ = json.Marshal(stage)
	}
	if len(submittedArgs) > 0 {
		merged["submitted_args"] = submittedArgs
	}
	if desiredRevision != nil {
		merged["desired_revision"], _ = json.Marshal(*desiredRevision)
	}
	result, _ := json.Marshal(merged)
	return result
}
