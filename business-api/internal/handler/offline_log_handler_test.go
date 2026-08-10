package handler

import (
	"testing"
	"time"

	"inv-api-server/internal/model"
)

func TestValidOfflineLog(t *testing.T) {
	base := model.OfflineOpLog{
		LogID:    "9f8e7d6c-5b4a-4321-9876-fedcba098765",
		DeviceSN: "H1CNA6K20001",
		Action:   "set_power",
		Params:   map[string]interface{}{"power_w": float64(3000)},
		Result:   "ok",
		Channel:  "ble",
		OpTime:   time.Now(),
	}

	if !validOfflineLog(base) {
		t.Fatal("valid log rejected")
	}

	cases := []struct {
		name   string
		mutate func(*model.OfflineOpLog)
	}{
		{"empty log_id", func(l *model.OfflineOpLog) { l.LogID = "" }},
		{"bad log_id", func(l *model.OfflineOpLog) { l.LogID = "not a uuid!" }},
		{"empty sn", func(l *model.OfflineOpLog) { l.DeviceSN = "" }},
		{"unknown action", func(l *model.OfflineOpLog) { l.Action = "rm_rf" }},
		{"bad channel", func(l *model.OfflineOpLog) { l.Channel = "wifi" }},
		{"zero op_time", func(l *model.OfflineOpLog) { l.OpTime = time.Time{} }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			log := base
			tc.mutate(&log)
			if validOfflineLog(log) {
				t.Fatalf("%s: expected invalid", tc.name)
			}
		})
	}
}
