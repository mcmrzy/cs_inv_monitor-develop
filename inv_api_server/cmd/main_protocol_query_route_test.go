package main

import (
	"os"
	"strings"
	"testing"
)

func TestAlarmEventDetailAuthenticatedRouteContract(t *testing.T) {
	source, err := os.ReadFile("main.go")
	if err != nil {
		t.Fatal(err)
	}
	const route = `auth.GET("/alarm-events/:id", internalHandler.GetAlarmEventDetail)`
	if !strings.Contains(string(source), route) {
		t.Fatalf("authenticated alarm-event detail route is missing: %s", route)
	}
}

func TestInternalAlarmRouteUsesOnlyTransactionalV1Ingress(t *testing.T) {
	source, err := os.ReadFile("main.go")
	if err != nil {
		t.Fatal(err)
	}
	mainSource := string(source)
	const route = `internal.POST("/device-alarm", internalHandler.IngestAlarmV1)`
	if !strings.Contains(mainSource, route) {
		t.Fatalf("transactional V1 alarm route is missing: %s", route)
	}
	if strings.Contains(mainSource, "internalHandler.DeviceAlarm") {
		t.Fatal("legacy best-effort alarm ingress must not be routed")
	}
}
