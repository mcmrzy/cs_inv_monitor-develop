//go:build integration

package service

import (
	"context"
	"os"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"inv-api-server/internal/repository"
)

func TestDirectCapabilitiesBySNDoNotAdvertiseOrExecuteAC(t *testing.T) {
	ctx := context.Background()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://testuser:testpass@localhost:15432/postgres?sslmode=disable"
	}
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	cfg.MaxConns = 1
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	_, err = pool.Exec(ctx, `CREATE TEMP TABLE devices(sn text,model_id bigint,model text,deleted_at timestamptz);
	CREATE TEMP TABLE device_models(id bigint,model_code text,lifecycle_status text);
	CREATE TEMP TABLE device_model_commands(model_id bigint,command_code text,display_name_key text,parameter_schema jsonb DEFAULT '{"args":[]}',response_schema jsonb DEFAULT '{}',timeout_seconds integer DEFAULT 30,risk_level integer DEFAULT 2,requires_online boolean DEFAULT true,is_enabled boolean DEFAULT true,config_domain text,permission_code text,operation_kind text,requires_stopped boolean,requires_bms_online boolean,confirmation_mode text,ttl_seconds integer,cooldown_seconds integer,ui_schema jsonb,min_firmware text);
	INSERT INTO devices VALUES('DIRECT-SN',1,'CS-L10-6K2',NULL),('LEGACY-SN',1,'CS-L10-6K2',NULL);
	INSERT INTO devices VALUES('PANEL-SN',2,'6KU',NULL);
	INSERT INTO device_models VALUES(1,'CS-L10-6K2','active'),(2,'6KU','active');
	INSERT INTO device_model_commands(model_id,command_code,min_firmware)
	VALUES(2,'ac_on','0.4.47-modbus-full'),(2,'ac_off','0.4.47-modbus-full');
	INSERT INTO device_model_commands(model_id,command_code,min_firmware,parameter_schema)
	VALUES(2,'set_soc_cutoff','0.4.53-modbus-full','{"args":[{"key":"value","type":"integer","enum":[0,20,25]}]}');
	INSERT INTO device_model_commands(model_id,command_code)VALUES(1,'ac_on'),(1,'ac_off'),(1,'set_output_priority');`)
	if err != nil {
		t.Fatal(err)
	}
	mr := miniredis.RunT(t)
	mr.Set("device:control:dsp_protocol:DIRECT-SN", directDSPProtocol)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	s := NewDeviceService(repository.NewDeviceRepository(pool, nil), rdb, repository.NewModelRepository(pool, nil), nil, "http://unused", "", pool)
	for _, sn := range []string{"DIRECT-SN", "LEGACY-SN"} {
		caps, err := s.GetControlCapabilitiesBySN(ctx, sn)
		if err != nil {
			t.Fatal(err)
		}
		if len(caps) != 3 {
			t.Fatalf("missing actual model capabilities for %s: %#v", sn, caps)
		}
		for _, cap := range caps {
			if isACOutputCommand(cap.CommandCode) && cap.IsEnabled != (sn == "LEGACY-SN") {
				t.Fatalf("bad AC advertisement for %s: %#v", sn, cap)
			}
		}
	}
	if _, err = s.ValidateAndPrepareCommand(ctx, 1, "DIRECT-SN", "ac_on", nil, true); err == nil {
		t.Fatal("direct AC passed real command validator")
	}
	if _, err = s.SendCommand(ctx, "DIRECT-SN", "ac_off", nil); err == nil {
		t.Fatal("legacy sender bypassed direct capability restriction")
	}

	// Unknown or older Modbus firmware must keep both commands disabled.
	s.preconditionChecker = nil
	for _, protocol := range []string{"", modbusDSPProtocol, modbusPowerProtocol, modbusBatteryProtocol} {
		if protocol != "" {
			mr.Set("device:control:dsp_protocol:PANEL-SN", protocol)
		}
		caps, err := s.GetControlCapabilitiesBySN(ctx, "PANEL-SN")
		if err != nil || len(caps) != 3 {
			t.Fatalf("missing 6KU command capabilities: %#v, %v", caps, err)
		}
		for _, cap := range caps {
			ready := supportsModbusPower(protocol)
			var params map[string]interface{}
			if cap.CommandCode == "set_soc_cutoff" {
				ready = protocol == modbusBatteryProtocol
				params = map[string]interface{}{"value": 0}
			}
			if cap.IsEnabled != ready {
				t.Fatalf("incorrect Modbus power advertisement for %q: %#v", protocol, cap)
			}
			prepared, err := s.ValidateAndPrepareCommand(ctx, 1, "PANEL-SN", cap.CommandCode, params, true)
			if !ready {
				if err == nil {
					t.Fatalf("accepted %s without firmware capability", cap.CommandCode)
				}
			} else {
				wantArgs := len(params)
				if err != nil || !prepared.HasV2Spec || prepared.Args == nil || len(prepared.Args) != wantArgs {
					t.Fatalf("unexpected MQTT action for %s: %#v, %v", cap.CommandCode, prepared, err)
				}
			}
		}
	}

}
