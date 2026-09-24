# L10 BLE Binary OTA Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transfer local OTA firmware through bounded binary BLE writes with 1 KB cumulative acknowledgements, then release a matching ESP firmware and App build.

**Architecture:** Keep JSON v2 control and status. Add a 10-byte binary data header and raw bytes on the existing OTA data characteristic. The ESP accepts old JSON data during rollout, but the App sends only binary data, sizes writes from negotiated MTU, and checks cumulative accepted offsets every 1024 bytes.

**Tech Stack:** ESP-IDF C/NimBLE/FreeRTOS, Flutter/Dart/flutter_blue_ultra, C host tests, Flutter tests.

---

## Chunk 1: Protocol and firmware

### Task 1: ESP binary data receiver

**Files:**
- Modify: `D:/CS_INV_WIFI/esp32c3_l10_idf/tests/host/test_ble_ota.c`
- Modify: `D:/CS_INV_WIFI/esp32c3_l10_idf/tests/host/test_ota_transfer_policy.c`
- Modify: `D:/CS_INV_WIFI/esp32c3_l10_idf/main/ota/ble_ota.c`
- Modify: `D:/CS_INV_WIFI/esp32c3_l10_idf/main/ota/ota_transfer_policy.c`
- Modify: `D:/CS_INV_WIFI/esp32c3_l10_idf/components/ble_ct/ble_ct.c` (advertise `ota_binary_v1` capability in INFO)

- [ ] **Step 1:** Add a byte-length-aware host `write_attr_bytes` helper (the existing helper uses `strlen` and cannot test embedded NUL). Add a host test with 24-hex transfer ID, magic/version, 32-bit token and offset, and up to 496 raw bytes. Step the fake queue consumer between writes so the third frame is not artificially queue-full. Assert accepted offset advances exactly by payload length and status notification is deferred until the first 1024-byte boundary (or end of file).
- [ ] **Step 2:** Run the host `test_ble_ota` target; verify the new test fails because current code parses only JSON.
- [ ] **Step 3:** Add binary dispatch only to the OTA data characteristic. Validate magic/version, connection, token, exact offset, remaining file length, and queue capacity before mutation. Keep existing JSON path intact. Use an approximately 1 KB total queue allocation and enlarge the local worker buffer for the binary fragment. Notify on 1024-byte boundaries and final byte. Add `ota_binary_v1` to INFO and verify the INFO JSON stays within its existing 512-byte buffer.
- [ ] **Step 4:** Run the host tests; verify binary and legacy JSON data both pass. Add rejection tests for wrong token, duplicate offset, malformed and oversize frames, queue full, final partial batch, and timeout floor; run again. Ensure read/query status remains available inside a batch.
- [ ] **Step 5:** Build ESP-IDF firmware and inspect binary size/partition fit and stack/heap diagnostics. Preserve the existing 1.0.11 artifact.

## Chunk 2: App sender

### Task 2: MTU-bounded binary writes

**Files:**
- Modify: `inv_app/lib/core/services/ble/ble_adapter.dart`
- Modify: `inv_app/lib/core/services/ble/ble_device_manager.dart`
- Modify: `inv_app/lib/features/ota/data/datasources/ble_communication_service.dart`
- Modify: `inv_app/test/ble/ble_ota_transport_test.dart`

- [ ] **Step 1:** Write a Flutter test expecting data writes to be binary and no more than `min(509, mtu-3)` bytes, including the 10-byte header. For MTU 512, expect payloads of at most 496 bytes. For a 1024-byte fixture expect cumulative confirmation at 1024, not after every physical write. Assert the lease exposes raw-byte normal writes rather than JSON long writes.
- [ ] **Step 2:** Run this test and verify failure on the existing JSON sender.
- [ ] **Step 3:** Expose current negotiated MTU from the BLE adapter/session. Replace the App's version-gated JSON data loop with binary encoding and write-with-response. Add optional native write/read timeouts in the BLE adapter and use about 5 seconds for binary writes/direct status reads; never stack two default 15-second plugin waits. Keep OTA lease and JSON control/status. Do not add an old-data-format fallback. Fail fast below MTU 256 or when ESP INFO lacks `ota_binary_v1`, with a clear prior-upgrade route.
- [ ] **Step 4:** Test ambiguous write, ATT 9 queue-full, and ACK timeout: directly read status tied to the active transfer ID and resume at the exact accepted offset, never resend an accepted range. Test definite ATT refusal, low-MTU rejection, final short batch, 1200-second request, and whole-file SHA behavior. At MTU 256, use status read polling if a full notification cannot fit. Enforce and test a recovery deadline below the firmware's 30-second idle escape (about 20 seconds without accepted-offset progress).
- [ ] **Step 5:** Run targeted Flutter tests, `flutter analyze --no-pub --no-fatal-infos`, and a release APK build.

## Chunk 3: Integration and release

### Task 3: Version, diagnostics, and delivery

**Files:**
- Modify: `D:/CS_INV_WIFI/esp32c3_l10_idf/version.txt`
- Modify as needed: `D:/CS_INV_WIFI/esp32c3_l10_idf/main/ota/ota_service.c`
- Release metadata: `D:/CS_INV_WIFI/esp32c3_l10_idf/release.ps1` is a local packaging tool only; backend draft/publish routes are in `business-api/cmd/main.go` and `business-api/internal/handler/ota_independent_handler.go`

- [ ] **Step 1:** Add a regression test that local BLE queue waits are not mislabeled as HTTP upstream idle; run RED then fix diagnostics. Add a firmware host test proving `ota.ctrl.timeout_seconds` honors a valid value but never falls below 600 seconds; make the App request at least 1200 seconds.
- [ ] **Step 2:** Version the new ESP as 1.0.12 after code/build checks. Verify generated image and partition fit. Do not alter 1.0.11 binary.
- [ ] **Step 3:** Review both repository diffs for unrelated dirty changes and run scoped checks. Build App APK and record paths/hashes.
- [ ] **Step 4:** On real hardware, install ESP 1.0.12 by cloud or serial first, then test a roughly 1.2 MB App BLE transfer. Record phone model, MTU, elapsed time, accepted offsets, final SHA/version, free heap and worker stack. If no device is available, explicitly label this gate unverified and do not claim a successful speedup.
- [ ] **Step 5:** Inspect authenticated backend draft creation and `POST /ota/firmware/:id/publish` workflow, authorized production destination, rollout policy, and existing 1.0.11 rollback target. `release.ps1` alone does not upload or list a release. Publish 1.0.12 only after available gates are recorded; attach version, image hash, firmware ID, scope, and rollback instructions. Do not touch production secrets in source control.
