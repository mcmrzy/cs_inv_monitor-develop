package service

import (
	"context"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"inv-api-server/internal/repository"
)

func TestExplicitDirectProtocolRestrictsCapabilitiesAndAllWrites(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	ctx := context.Background()
	mr.Set("device:control:dsp_protocol:DIRECT-SN", directDSPProtocol)
	s := &DeviceService{cache: rdb, deviceSrvURL: "http://unused"}
	caps, err := s.restrictControllerCapabilities(ctx, "DIRECT-SN", []repository.CommandCapability{{CommandCode: "ac_on", IsEnabled: true}, {CommandCode: "ac_off", IsEnabled: true}, {CommandCode: "set_output_priority", IsEnabled: true}})
	if err != nil {
		t.Fatal(err)
	}
	if caps[0].IsEnabled || caps[1].IsEnabled || !caps[2].IsEnabled {
		t.Fatalf("wrong direct capabilities: %#v", caps)
	}
	for _, cmd := range []string{"ac_on", "ac_off"} {
		if _, err = s.ValidateAndPrepareCommand(ctx, 1, "DIRECT-SN", cmd, nil, true); err == nil {
			t.Fatalf("validation allowed %s", cmd)
		}
		if _, err = s.SendCommand(ctx, "DIRECT-SN", cmd, nil); err == nil {
			t.Fatalf("send bypass allowed %s", cmd)
		}
		if _, err = s.SendPreparedCommand(ctx, "DIRECT-SN", &PreparedCommand{Command: cmd}); err == nil {
			t.Fatalf("prepared bypass allowed %s", cmd)
		}
	}
	legacy, err := s.restrictControllerCapabilities(ctx, "LEGACY-SN", []repository.CommandCapability{{CommandCode: "ac_on", IsEnabled: true}})
	if err != nil || !legacy[0].IsEnabled {
		t.Fatal("missing direct evidence disabled legacy ARM capability")
	}
	if err = s.checkControllerCommand(ctx, "LEGACY-SN", "ac_on"); err != nil {
		t.Fatalf("legacy command rejected: %v", err)
	}
	mr.Close()
	if err = s.checkControllerCommand(ctx, "DIRECT-SN", "ac_on"); err == nil {
		t.Fatal("Redis outage allowed unverified AC command")
	}
	if _, err = s.restrictControllerCapabilities(ctx, "DIRECT-SN", caps); err == nil {
		t.Fatal("Redis outage advertised usable capability")
	}
}
