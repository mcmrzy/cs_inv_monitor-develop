package service

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func TestDirectInfoRetainsControlProtocolEvidence(t *testing.T) {
	cache := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: cache.Addr()})
	defer rdb.Close()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }))
	defer server.Close()
	p := &ProtocolParser{rdb: rdb, apiServer: server.URL, httpClient: server.Client()}
	ctx := context.Background()
	if err := p.handleInfo(ctx, &RawMessage{SN: "DIRECT-SN", Payload: []byte(`{"sn":"FORGED-SN","dsp_protocol":"direct_uart_03_04_25","firmware_arm":null}`)}); err != nil {
		t.Fatal(err)
	}
	key := "device:control:dsp_protocol:DIRECT-SN"
	protocol, err := rdb.Get(ctx, key).Result()
	if err != nil || protocol != "direct_uart_03_04_25" {
		t.Fatalf("direct identity lost: %q %v", protocol, err)
	}
	cache.FastForward(11 * time.Minute)
	if !cache.Exists(key) {
		t.Fatal("known controller protocol expired with telemetry")
	}
	if cache.Exists("device:control:dsp_protocol:FORGED-SN") {
		t.Fatal("payload spoofed control identity")
	}
	if err := p.handleInfo(ctx, &RawMessage{SN: "DIRECT-SN", Payload: []byte(`{"model":"CS-L10-6K2"}`)}); err != nil {
		t.Fatal(err)
	}
	if got, _ := rdb.Get(ctx, key).Result(); got != "direct_uart_03_04_25" {
		t.Fatalf("omitted INFO field erased evidence: %s", got)
	}
	if err := p.handleInfo(ctx, &RawMessage{SN: "DIRECT-SN", Payload: []byte(`{"dsp_protocol":"unknown"}`)}); err != nil {
		t.Fatal(err)
	}
	if got, _ := rdb.Get(ctx, key).Result(); got != "direct_uart_03_04_25" {
		t.Fatal("unrecognized protocol erased known direct restriction")
	}
}
