package handler

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"strings"
	"testing"
)

func TestLegacyAlarmIngressIsNotCompiled(t *testing.T) {
	file, err := parser.ParseFile(token.NewFileSet(), "internal_handler.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok {
			continue
		}
		switch fn.Name.Name {
		case "DeviceAlarm", "writeAlarmEvent", "captureAlarmSnapshot":
			t.Fatalf("legacy alarm write entry is still compiled: %s", fn.Name.Name)
		}
	}
}

func TestAlarmEventPrecedesMutableProjectionInOneTransaction(t *testing.T) {
	source, err := os.ReadFile("protocol_ingest_v1.go")
	if err != nil {
		t.Fatal(err)
	}
	all := string(source)
	start := strings.Index(all, "func (s *postgresProtocolV1Store) IngestAlarm")
	end := strings.Index(all, "func (s *postgresProtocolV1Store) IngestParallel")
	if start < 0 || end <= start {
		t.Fatal("alarm ingest transaction not found")
	}
	segment := all[start:end]
	positions := []struct {
		name string
		text string
	}{
		{"transaction begin", "s.db.Begin(ctx)"},
		{"immutable event", "INSERT INTO device_alarm_events"},
		{"event snapshot", "insertAlarmSnapshot(ctx, tx"},
		{"mutable projection", "UPDATE alarms SET"},
	}
	last := -1
	for _, item := range positions {
		position := strings.Index(segment, item.text)
		if position < 0 {
			t.Fatalf("%s step is missing", item.name)
		}
		if position <= last {
			t.Fatalf("%s does not follow the previous transaction step", item.name)
		}
		last = position
	}
	finalCommit := strings.LastIndex(segment, "tx.Commit(ctx)")
	if finalCommit <= last {
		t.Fatal("mutable projection is not committed with its event")
	}
	if !strings.Contains(segment, "ON CONFLICT(device_sn,source,code,state,event_time) DO NOTHING") {
		t.Fatal("immutable event idempotency barrier is missing")
	}
}
