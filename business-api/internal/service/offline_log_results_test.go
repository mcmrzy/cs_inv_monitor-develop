package service

import (
	"testing"

	"inv-api-server/internal/model"
)

func TestOfflineLogResultsInInputOrderRejectsMismatchedAuthorizedOutcomes(t *testing.T) {
	_, err := offlineLogResultsInInputOrder(
		2,
		[]int{0, 1},
		nil,
		[]model.OfflineLogResult{{LogID: "first", Status: model.OfflineLogAccepted}},
	)
	if err == nil {
		t.Fatal("expected mismatched authorized outcomes to fail")
	}
}

func TestOfflineLogResultsInInputOrderPreservesRequestOrder(t *testing.T) {
	results, err := offlineLogResultsInInputOrder(
		3,
		[]int{0, 2},
		map[int]model.OfflineLogResult{
			1: {LogID: "rejected", Status: model.OfflineLogRejected, Reason: "device_access_denied"},
		},
		[]model.OfflineLogResult{
			{LogID: "accepted", Status: model.OfflineLogAccepted},
			{LogID: "duplicate", Status: model.OfflineLogDuplicate},
		},
	)
	if err != nil {
		t.Fatalf("merge results: %v", err)
	}
	if results[0].LogID != "accepted" || results[1].LogID != "rejected" || results[2].LogID != "duplicate" {
		t.Fatalf("results = %+v, want accepted/rejected/duplicate in request order", results)
	}
}
