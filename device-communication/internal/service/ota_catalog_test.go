package service

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type catalogPublisherFake struct {
	sn      string
	payload []byte
	calls   int
}

func (p *catalogPublisherFake) PublishPanelRPC(_ context.Context, sn string, payload []byte) error {
	p.sn = sn
	p.payload = append([]byte(nil), payload...)
	p.calls++
	return nil
}
func catalogTestQuery() CatalogQuery {
	return CatalogQuery{V: 1, Type: "catalog.query", SN: "MB00001122334455", RequestID: "0123456789abcdef", Epoch: 7, Target: "esp"}
}
func TestCatalogInternalBridge(t *testing.T) {
	publisher := &catalogPublisherFake{}
	api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/internal/ota-catalog" || r.Method != "POST" || r.Header.Get("X-Internal-Key") != "test-only-key" {
			t.Error("missing internal authentication or route")
		}
		var q CatalogQuery
		if json.NewDecoder(r.Body).Decode(&q) != nil {
			t.Error("invalid request")
		}
		sn := q.SN
		if q.Index == 1 {
			sn = "MB99991122334455"
		}
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"code": 0, "data": map[string]interface{}{"v": 1, "action": "catalog", "sn": sn, "request_id": q.RequestID, "epoch": q.Epoch, "index": q.Index, "total": 0, "status": "ok"}})
	}))
	defer api.Close()
	s := NewFirmwareCatalogService(api.URL, "test-only-key", publisher)
	q := catalogTestQuery()
	if err := s.respond(context.Background(), q); err != nil || publisher.calls != 1 || publisher.sn != q.SN || !strings.Contains(string(publisher.payload), `"status":"ok"`) {
		_, fetchErr := s.fetch(context.Background(), q)
		t.Fatalf("catalog response missing: publish=%v, fetch=%v, reply=%s", err, fetchErr, publisher.payload)
	}
	q.Index = 1
	if s.respond(context.Background(), q) != nil || !strings.Contains(string(publisher.payload), `"status":"error"`) {
		t.Fatal("wrong-SN backend reply escaped correlation guard")
	}
}
func TestCatalogBoundedAdmission(t *testing.T) {
	q := catalogTestQuery()
	wire, _ := json.Marshal(map[string]interface{}{"v": 1, "data": q})
	if _, err := ParseCatalogQuery(q.SN, wire); err != nil {
		t.Fatal(err)
	}
	if _, err := ParseCatalogQuery("MB99991122334455", wire); err == nil {
		t.Fatal("cross-SN query accepted")
	}
	if _, err := ParseCatalogQuery(q.SN, []byte(strings.Repeat("x", 513))); err == nil {
		t.Fatal("oversized query accepted")
	}
	s := NewFirmwareCatalogService("http://internal", "test-only-key", &catalogPublisherFake{})
	for i := 0; i < 16; i++ {
		if !s.Enqueue(q.SN, wire) {
			t.Fatalf("queue rejected entry %d", i)
		}
	}
	if s.Enqueue(q.SN, wire) {
		t.Fatal("unbounded catalog query queue")
	}
}
func TestCatalogExpiredQueryRepliesWithError(t *testing.T) {
	publisher := &catalogPublisherFake{}
	s := NewFirmwareCatalogService("http://internal", "test-only-key", publisher)
	q := catalogTestQuery()
	q.queuedAt = time.Now().Add(-11 * time.Second)
	if s.respond(context.Background(), q) != nil || !strings.Contains(string(publisher.payload), `"status":"error"`) {
		t.Fatal("stale queued request was not rejected")
	}
}
