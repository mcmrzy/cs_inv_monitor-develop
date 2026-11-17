package service

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"inv-api-server/internal/repository"
)

func TestPreparedLegacyCommandCarriesBoundedExpiry(t *testing.T) {
	var got map[string]interface{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&got); err != nil {
			t.Error(err)
		}
		// Stop after observing the transmitted envelope, before notifications.
		w.WriteHeader(http.StatusBadRequest)
	}))
	defer server.Close()
	svc := NewDeviceService(repository.NewDeviceRepository(nil, nil), nil, nil, nil, server.URL, "", nil)
	start := time.Now().Unix()
	_, err := svc.SendPreparedCommand(context.Background(), "SN001", &PreparedCommand{Command: "set_control", TaskID: "p0", Params: map[string]interface{}{"value": 80}})
	if err == nil {
		t.Fatal("test endpoint must reject transmission")
	}
	expiry, ok := got["expires_at"].(float64)
	if !ok || int64(expiry) < start+299 || int64(expiry) > time.Now().Unix()+300 {
		t.Fatalf("legacy command has no bounded expiry: %#v", got)
	}
}

func TestModbusPowerDoesNotQueueAfterDeviceDisconnects(t *testing.T) {
	var got map[string]interface{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&got); err != nil {
			t.Error(err)
		}
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer server.Close()
	mr := miniredis.RunT(t)
	mr.Set("device:control:dsp_protocol:SN001", modbusPowerProtocol)
	cache := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer cache.Close()
	svc := NewDeviceService(repository.NewDeviceRepository(nil, nil), cache, nil, nil, server.URL, "", nil)
	firmware := modbusPowerMinFirmware
	start := time.Now().Unix()
	_, err := svc.SendPreparedCommand(context.Background(), "SN001", &PreparedCommand{
		Command: "ac_off", TaskID: "power-1", Args: []interface{}{}, HasV2Spec: true,
		Caps: &repository.CommandCapability{CommandCode: "ac_off", MinFirmware: &firmware},
	})
	if err == nil || mr.Exists("device:cmd:queue:SN001") {
		t.Fatal("offline Modbus power action must fail without entering the queue")
	}
	expiry, ok := got["expires_at"].(float64)
	if !ok || int64(expiry) < start+29 || int64(expiry) > time.Now().Unix()+30 {
		t.Fatalf("Modbus power command has unexpected expiry: %#v", got)
	}
}
