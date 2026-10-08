# ARM CMD08 BMS integration

Firmware source: `D:/CS_INV_WIFI/esp32c3_l10_idf`. ARM responds to command
`0x08` with the packed, little-endian, 100-byte `BattSumDef`. The collector
uses the existing encrypted PPP/CRC32 transport and polls with params `(0,0)`.

## MQTT and API

The existing `cs_inv/{sn}/heartbeat` V3 envelope retains `data.run` and adds:

```json
{"bms_summary":{"layout":0,"bytes":[100],"age_ms":3000}}
```

`bytes` above abbreviates an array of exactly 100 integers, each in 0..255.
`age_ms` is the monotonic time since the valid ARM response, not since publish.
Missing `bms_summary` is valid for old firmware. Layout 0 is the provided
2026-10 CMD08 layout; different versions/lengths are rejected.

The device server decodes values once, storing the full normalized
`bms_summary` JSONB and original envelope in `device_telemetry_3min`.
`GET /devices/by-sn/:sn/realtime` exposes `realtime.bms_summary`. Raw telemetry
history also includes the snapshot. Inverter/DSP battery metrics retain their
existing source; CMD08 is a separate BMS snapshot.

| Data offset | API field | Conversion |
|---|---|---|
| 0 | battery_count | u8 |
| 1 | voltage | u16 / 100 V |
| 3 | current | s32 / 100 A; positive charge, negative discharge |
| 7, 9 | soc, soh | u16 / 10 percent; provisional per supplied table |
| 11, 13 | capacity_remain, capacity_full | u16 / 1000 Ah |
| 15 | capacity_design | u32 / 1000 Ah |
| 19, 21, 23 | warning_flag, protection_flag, status_fault_flag | separate u16 bitmaps |
| 25 | balance_status | u16 bitmap |
| 27..58 | cell_voltages | 16 u16 mV; zero cell = null |
| 59..66 | cell_temperatures | 4 nulls; ARM currently does not populate |
| 67 | cycle_count | u16 cycles |
| 69, 71 | max_cell_voltage, min_cell_voltage | u16 mV |
| 73, 75 | max_cell_temp, min_cell_temp | null; ARM currently does not populate |
| 77, 79, 81 | mos_temp, pcb_temp, env_temp | s16 / 10 Celsius |
| 83, 84 | battery_mode, battery_status | raw u8 enums |
| 85, 89 | total_chg_capacity_raw, total_dsg_capacity_raw | raw u32; unit unconfirmed |
| 93 | chg_request_current_raw | raw u16; unit unconfirmed |
| 95 | chg_request_voltage_raw | raw s16; unit unconfirmed |
| 97 | system_mode | raw u8 enum |
| 98 | charging_voltage | null; ARM currently does not populate |

All 100 original bytes are available as `raw_bytes`; `soc_raw` and `soh_raw`
are also explicit. Confirm SOC/SOH scaling and the four uncertain quantities
against the BMS specification or a captured device packet before finalizing
units. Firmware performs no unit conversion.

`bms_online=0` when battery_count is zero, SOC raw is the ARM disconnect
sentinel 255, or response age exceeds 120000 ms. Measurements are null when
offline; original bytes and bitmaps remain available for diagnostics. The
API also evaluates `expires_at` against current UTC. It expires 210 seconds
after `reported_at`, the trusted server receive time (the normal 180-second
heartbeat interval plus a 30-second delivery margin). This is distinct from ARM
response age: a healthy collector
does not become offline between normal heartbeats. A stopped collector or
expired Redis cache cannot leave an old snapshot marked online. Optional BMS
lookup failure preserves available inverter realtime data.
`updated_at` estimates capture time by subtracting ARM response age from the
server receive time. Original device time remains in the raw envelope. Latest
BMS selection uses server receive time so device clock corrections cannot
replace a fresh BMS report with an older snapshot or expire it immediately.

## Rollout and verification

Apply migration `126_arm_cmd08_bms_summary.up.sql` before starting the new
services. Deploy services before the ESP update because old strict V3
parsers reject unknown `data.bms_summary`. Older firmware remains valid.
Install the updated App to expose CMD08 fields on the storage page.

Local validation covers protocol parsing (signed values, byte boundaries,
missing group, offline sentinel and stale snapshots), PostgreSQL migration,
durable realtime retrieval without Redis and complete raw history, plus
Flutter model/widget checks and firmware build/host protocol checks.
Hardware UART/RS485, MQTT end-to-end and physical phone acceptance still
require a real ARM with CMD08 support. No flashing or production deployment
is implied by local validation.

## Monitoring interfaces

The approved design is recorded in
`docs/superpowers/specs/2026-10-08-bms-monitor-design.md`. Both production clients
use overview, selectable cell analysis and layered diagnostics rather than a
flat field list. Warning, protection and actual fault bits are decoded separately;
charge/discharge and MOS operation bits are not faults. Relative maximum/minimum
cell colors are not invented safety thresholds. Cell spread is derived from
available cells; the reported extrema remain available in diagnostics.

CMD08 takes precedence when its group exists, even if it is stale or unknown.
Only a missing CMD08 group falls back to the legacy `bms` protocol. Inverter-side
battery values are not substituted for missing BMS measurements. Client timers
and resume/focus handling advance expiration even after a failed refresh.
Diagnostic labels explicitly distinguish retained historical data from live
measurements. Unconfirmed units/enums are raw, and SOC/SOH conversion is marked
provisional. All 100 bytes remain inspectable.

The isolated local Web review uses the actual production component:
`http://127.0.0.1:5177/bms-component-review.html`. Its adapter uses simulated
fixtures only, makes no real device requests, and is excluded from production
build inputs. Real-page browser regression is in
`inv-admin-frontend/bms-production.verify.mjs`. Flutter screenshots are generated
from production widgets, not from the HTML design prototype.

This update covers the cloud MQTT/API monitoring path. It does not extend BLE
direct BMS telemetry or establish physical phone/ARM/BMS acceptance.
