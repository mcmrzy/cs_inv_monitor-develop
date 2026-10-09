# Monitoring Recovery Verification

## Implemented Behavior

- App realtime parses nested cache and flat database column names without silently replacing missing measurements with zero. Accepted snapshots replace old derived fields. Explicit offline wins over a cached device status; faulty online devices (status 2) remain online. Older/undated detail responses cannot overwrite a newer poll.
- App history is available from the realtime page. Raw samples and hourly charts use bounded UTC requests, paging, and the selected device timezone for date bounds, aggregation and display. Half-hour/quarter-hour zones and 23/25-hour DST days are covered.
- Firmware reports `energy.daily_pv` and `energy.total_pv` in telemetry.c. The database stores the latter as `total_pv_energy`. This proves protocol/source support, not that the example production SN currently reports a correct counter.
- Lifetime PV energy uses the maximum valid nonnegative finite latest counter, recorded counter and sum of recorded daily energy per device. Absolute counters are never summed across reports. App uses this server floor and a valid live counter. Energy before available history cannot be reconstructed when all reported lifetime counters are missing/reset.
- App overview and Web dashboard use live validated organization scopes, including descendants and active system administrators. Tests cover sibling/tenant isolation, revocation, expired memberships, SSE revalidation, more than 100 stations and device-level filtering inside a visible station. Read-only station detail/history use the same boundary; write permissions are not broadened.
- Device and associated-device cards show actual identity, rated W/kW, available readings and timestamps. A detected CMD08 battery is a child entry of its inverter, not a new independently owned device. Stale/offline battery entries remain accessible without displaying stale engineering values as live.
- Debug interruption releases occupancy. Stop retries use one persisted command task ID; a delayed start ACK cannot undo stopping. Two fresh post-start samples are required for recovery. Offline debug commands are not queued for a later boot.
- Storage keeps CMD08 diagnostics and provides a redesigned legacy overview with SOC, signed power, cell consistency and alerts before technical details. Missing/reserved work modes and missing MOS flags stay unknown rather than falsely idle/off.
- Firmware resources expose remote upgrade independently of download/local OTA. Confirmation fixes the SN/firmware, device switching is guarded during dispatch, and network retries retain the idempotency key.
- MQTT, device communication, business API, persistence, App detail/history and Web upgrade tables carry nullable `stage_progress` and `overall_progress`. New phases reset to 0; phase 100 is not task success. Legacy reports only show overall progress; no unsupported inverse mapping is applied.
- New firmware weights download at 0-70 for ARM/DSP/BMS and 0-95 for ESP, reserves the remaining overall range for transfer/verification/install, and only reports overall 100 on success. The phase percentage remains the actual independent 0-100 value.
- Web telemetry table headings remain visible during scroll.

## Local Evidence (2026-10-09)

- Four Go services: `go build ./...`, `go test ./...`, `go vet ./...` passed.
- Business API handler/repository PostgreSQL integration suite: 191 top-level tests passed, none failed or skipped. Fixtures create/drop isolated databases on the temporary loopback TimescaleDB container at port 15432. No production database was used.
- Web: 534 tests across 63 files passed; `npm run build:check` passed.
- App: 899 tests passed; 30 optional real-font screenshot cases skipped in the normal full run. Final `flutter analyze --no-pub --no-fatal-infos` passed with no errors/warnings and 1025 info-level style/deprecation notices; this is not a clean-lint claim. The earlier automatic dependency update hit a TLS handshake failure, so verification used the existing resolved dependencies.
- Android debug APK built successfully. This is a test build, not a signed release or a phone installation.
- ESP32 authoritative checkout: `D:/CS_INV_WIFI/esp32c3_l10_idf`; ESP-IDF build and all 17 host tests passed, including separate phase/overall progress. Version remains 1.0.18; no formal release or flash was performed for this batch.
- Actual OTA Web component preview checked at 400px and 1280px: no horizontal document overflow, phase 0/35/100 distinct from overall 70/80/95, and legacy 84 labeled overall. Preview uses fixtures, not production telemetry.
- Actual-component Web history scrolling and real-font legacy App storage/card previews were inspected. The final storage run with Microsoft YaHei enabled passed all 53 tests, including all 30 real-font screenshot cases; the Chinese legacy overview and English 320px/1.8x diagnostics screenshot were inspected again.

Local logs and preview scaffolds live in `.codex_tmp/` and are not production source or intended commit artifacts.

## Build Artifacts

| Artifact | Location | SHA256 |
| --- | --- | --- |
| Android debug APK | `inv_app/build/app/outputs/flutter-apk/app-debug.apk` | `0746554658143e31edab29f077a9b44289ee361e6f77adf2bb726be35ff24cfd` |
| ESP32 build, version unchanged | `D:/CS_INV_WIFI/esp32c3_l10_idf/build/cs_inv_l10_c3.bin` | `6f9af0e1f9f8049ff92cafac03807c75ef52ebe24672a0c8b3b1d80fb83fac6c` |

The debug APK is not a signed production update and may not overlay-install on an existing release-signed App. These build-directory files are reproducible test outputs and may be replaced by later builds.

## Rollout Boundary

1. Apply migration `127_ota_stage_progress.up.sql` before deploying the new Business API queries. Deploy updated device communication and client versions together with the API.
2. Old firmware remains readable but cannot supply an independent phase percentage it never reported. Updated firmware is required to prove the new stage percentage end to end.
3. Check SN H1ZZX0013900002H against authenticated production realtime/history/statistics after deployment; compare nonzero values and timestamps with Web.
4. Install the App on a real phone and verify organization context switching, card/battery navigation, storage readability, debug power-off/on stop/restart and actual remote OTA stages against device logs.
5. No source was committed/pushed, no new remote CI run was triggered, and no production deployment/upload/flashing was done for these monitoring fixes. Pre-existing workspace changes are preserved.
