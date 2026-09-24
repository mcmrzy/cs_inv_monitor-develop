# L10 BLE Multi-Module OTA Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable local BLE upgrades of ESP, ARM, DSP, and BMS with accurate capability, capacity, progress, and version reporting.

**Architecture:** Keep the existing BLE v2 transfer and collector IAP install paths. Current firmware omits the optional legacy AUTH characteristic, so App session setup must tolerate its absence. Expand firmware and device capability metadata, fail before streaming when cache is too small, and make App validation and result reporting target-aware.

**Tech Stack:** ESP-IDF C, Go, Flutter/Dart.

**Design:** `docs/superpowers/specs/2026-09-24-l10-ble-multimodule-ota-design.md`

**Workspace caution:** Both `D:\CS_INV_WIFI` and the App repository have extensive unrelated dirty files. Inspect diffs for every touched file; stage only task-specific paths. Do not alter the v1.0.9 or existing 38400-only v1.0.10 release directory. The user confirmed target ARM devices use 38400; this is not a fleet-wide migration claim.

---

## Chunk 1: ESP firmware

### Task 1: BLE targets and device capability

**Files:** `D:\CS_INV_WIFI\esp32c3_l10_idf\main\ota\ble_ota.c`; `D:\CS_INV_WIFI\esp32c3_l10_idf\components\ble_ct\ble_ct.c`; `D:\CS_INV_WIFI\esp32c3_l10_idf\tests\host\test_ble_ota.c`.

- [ ] Add/extend failing host assertions: `ota.ctrl.body.target="bms"` maps to BMS; unknown target remains rejected; INFO `supported_upgrade_modules` contains all four functional names.
- [ ] Run the existing host-test command documented in `tests/host/README.md` or local test script and confirm the new assertions fail.
- [ ] Add `bms` parsing to the BLE target switch and update INFO modules list. Preserve `dsp`/`dsp_controller` support and 512-byte INFO limit; calculate produced length rather than truncating JSON.
- [ ] Re-run host tests. Expect all BLE tests to pass; check `git diff --check` for task paths.

### Task 2: Early cache-space rejection

**Files:** `D:\CS_INV_WIFI\esp32c3_l10_idf\main\ota\arm_ota.c`; `D:\CS_INV_WIFI\esp32c3_l10_idf\main\ota\arm_ota.h`; `D:\CS_INV_WIFI\esp32c3_l10_idf\main\ota\ota_service.c`; `D:\CS_INV_WIFI\esp32c3_l10_idf\main\ota\ota_service.h`; related host tests.

- [ ] Add a failing test for `image_size + 16 KiB` exceeding actual cache capacity; assert the public OTA result is `INSUFFICIENT_STORAGE`, not `ARM_TRANSFER_FAILED` or `FILE_TOO_LARGE`.
- [ ] Add a narrowly-scoped error distinction at the existing `offline_cache_reserve_space` failure and propagate it through `install_collector_iap_session` and BLE `ota.status` without changing cloud IAP behavior.
- [ ] Run host tests and IDF build. Confirm no `ota.data` is required before failure and no app partition is touched.

### Task 3: v1.0.11 artifact

**Files:** `D:\CS_INV_WIFI\esp32c3_l10_idf\version.txt`; generated `D:\CS_INV_WIFI\esp32c3_l10_idf\release\v1.0.11\...`.

- [ ] Confirm v1.0.9/v1.0.10 files and SHA-256 before generating anything; verify `CONFIG_CS_INV_UART_BAUD=38400` in the build configuration, then use `release.ps1` for v1.0.11 with no Git tag.
- [ ] Validate artifact version, size, hash, manifest, partition layout, and unchanged v1.0.9/v1.0.10 hashes. Document that v1.0.11 cannot be pushed to ARM-9600 devices. Record whether upload/publish was actually completed.

## Chunk 2: Backend channel metadata

### Task 4: DSP/BMS BLE capability

**Files:** `business-api/internal/service/ota_module.go`; `business-api/internal/service/ota_module_test.go`.

- [ ] Add table-driven cases asserting ESP/ARM `remote,ble,wifi_ap` and DSP/BMS `remote,ble`; unknown target has no channel. Run `go test ./internal/service -run FirmwareSupportedChannels` and confirm new cases fail.
- [ ] Change only `FirmwareSupportedChannels`; run relevant Go tests, `go build ./...`, and `go vet ./...` in `business-api`.
- [ ] Inspect local-result repository mapping for DSP/BMS; add regression assertions if missing, but avoid schema or API changes.

## Chunk 3: Flutter App

### Task 5: Resource and page gating

**Files:** `inv_app/lib/core/services/firmware_download_service.dart`; `inv_app/lib/features/ota/domain/entities/device_firmware_overview.dart`; `inv_app/lib/features/ota/presentation/pages/local_ota_page.dart`; corresponding tests under `inv_app/test/`.

- [ ] Write failing tests: DSP/BMS resources are BLE-eligible when `supported_channels` contains `ble`, not Wi-Fi-eligible; ESP/ARM legacy behavior remains. Page preflight accepts DSP/BMS only for BLE and blocks unsupported metadata.
- [ ] Implement narrow channel/target checks in the three existing files; do not permit a null channel list to authorize DSP/BMS.
- [ ] Run targeted `flutter test --no-pub` and `flutter analyze --no-pub`.

### Task 6: INFO capability and target-specific result

**Files:** `inv_app/lib/features/ota/data/datasources/ble_communication_service.dart`; `inv_app/lib/features/ota/presentation/controller/local_ota_controller.dart`; `inv_app/lib/features/ota/presentation/models/local_ota_presentation.dart`; `inv_app/test/ble/ble_ota_transport_test.dart`; `inv_app/test/features/ota/presentation/controller/local_ota_controller_test.dart`.

- [ ] Add failing tests for old INFO without BMS, new INFO with BMS, exact `ota.ctrl` wire target, and no ESP-version aliasing into ARM/DSP/BMS.
- [ ] In controller preflight, require BLE INFO target capability for DSP/BMS; map wire target once in BLE transport. Keep the existing session lease, per-chunk ACK, and transfer-ID filtering.
- [ ] Add target-aware progress/result handling: no ARM fallback for DSP/BMS, report only after target `succeeded`, use manifest target version when device supplies no target readback, and label it as target version. Extend polling for slow BMS without affecting ESP reboot handling.
- [ ] Map `INSUFFICIENT_STORAGE` to a localized actionable message; add tests for failed status and no success report. Do not expose internal error strings as customer copy.
- [ ] Run targeted Flutter tests plus `flutter analyze --no-pub`; inspect dirty-file diffs to avoid overwriting pre-existing changes.

## Chunk 4: Cross-stack verification and delivery

### Task 7: Contract checks and release evidence

- [ ] Check the four-module matrix against backend resources, BLE INFO, BLE control target, App preflight, and result-report target.
- [ ] Run ESP host tests/IDF build, Go service tests/build/vet, Flutter tests/analyze, and `git diff --check` in both repositories. Report each result separately.
- [ ] For hardware tests, upgrade a verified ARM-38400 device's ESP to v1.0.11, then BLE-test ESP/ARM/DSP/BMS including old-partition rejection. Without hardware access, mark this pending rather than passing.
- [ ] Publish/deploy only to verified destinations and record firmware ID/version/hash and App build. A local binary is not an uploaded or listed release.
