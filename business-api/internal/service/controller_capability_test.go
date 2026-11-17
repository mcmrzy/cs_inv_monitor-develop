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

func TestModbusSystemSettingsRequireExplicitReadbackCapability(t *testing.T) {
	ctx := context.Background()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	s := &DeviceService{cache: rdb}
	const key = "device:control:dsp_protocol:SYSTEM-SN"
	for _, protocol := range []string{modbusBatteryProtocol, modbusSystemProtocol, modbusBatteryProtocol} {
		mr.Set(key, protocol)
		minimum := modbusBatteryMinFirmware
		caps, err := s.restrictControllerCapabilities(ctx, "SYSTEM-SN", []repository.CommandCapability{
			{CommandCode: "set_modbus_inverter_mute", IsEnabled: true},
			{CommandCode: "set_modbus_auto_frequency", IsEnabled: false},
			{CommandCode: "set_soc_cutoff", MinFirmware: &minimum, IsEnabled: true},
			{CommandCode: "ac_on", IsEnabled: true},
		})
		ready := protocol == modbusSystemProtocol
		if err != nil || caps[0].IsEnabled != ready || caps[1].IsEnabled || !caps[2].IsEnabled || !caps[3].IsEnabled {
			t.Fatalf("unexpected capabilities for %q: %#v, %v", protocol, caps, err)
		}
		if err := s.checkControllerCommand(ctx, "SYSTEM-SN", "set_modbus_inverter_mute"); (err == nil) != ready {
			t.Fatalf("unexpected dispatch decision for %q: %v", protocol, err)
		}
	}
}
