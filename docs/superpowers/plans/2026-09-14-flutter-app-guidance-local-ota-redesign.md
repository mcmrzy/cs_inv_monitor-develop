# Flutter App Guidance and Local OTA Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved “静谧能源” redesign across onboarding, local OTA, network failure, About, and WiFi provisioning while removing App update checks and preserving OTA safety.

**Architecture:** Introduce page-specific illustration assets and small focused widgets instead of overwriting shared Xiaoshuo assets. Normalize all local-upgrade entry points to BLE/AP, keep offline firmware caching, persist firmware model metadata, validate it against connected-device information before upload, and remove the obsolete App-update service including its link preflight.

**Tech Stack:** Flutter, Dart, flutter_bloc, go_router, flutter_test, existing `AppColor` theme tokens, PNG/WebP assets.

---

## Chunk 1: Assets and onboarding

### Task 1: Add page-specific illustration assets

**Files:**
- Create: `inv_app/assets/images/onboarding/onboarding_energy_overview.png`
- Create: `inv_app/assets/images/onboarding/onboarding_status_alerts.png`
- Create: `inv_app/assets/images/onboarding/onboarding_local_service.png`
- Create: `inv_app/assets/images/states/network_connection_failed.png`
- Create: `inv_app/assets/images/states/local_upgrade_connection.png`
- Create: `inv_app/assets/images/provisioning/provisioning_companion_bottom.png`
- Modify: `inv_app/pubspec.yaml`
- Modify: `inv_app/lib/core/theme/csergy_assets.dart`
- Test: `inv_app/test/assets/asset_integrity_test.dart`

- [ ] Generate each transparent asset separately using the approved quiet-energy prompt family. Use a 1536×1024 working canvas, keep the subject inside the central 80% safe area, export optimized PNG with transparent background, and target ≤700 KB per file.
- [ ] Inspect dimensions, alpha presence, edge pixels and composition against light and dark backgrounds; then visually check the target screen crops.
- [ ] Register the three new subdirectories in `pubspec.yaml` and add constants without replacing shared Xiaoshuo files.
- [ ] Modify the existing asset-integrity test with failing decode/dimension/alpha assertions, run it red, then register assets and run green.

### Task 2: Rebuild first-run onboarding

**Files:**
- Modify: `inv_app/lib/features/onboarding/presentation/pages/onboarding_page.dart`
- Modify: `inv_app/lib/features/onboarding/data/onboarding_storage.dart`
- Test: `inv_app/test/features/onboarding/presentation/pages/onboarding_page_test.dart`
- Test: `inv_app/test/features/onboarding/data/onboarding_storage_test.dart`

- [ ] Write failing storage tests for unseen/same-version/new-version/read-write failure behavior.
- [ ] Write failing widget tests for three slides, skip/final CTA, stable footer height, and target routing.
- [ ] Run targeted tests and confirm failures are caused by missing behavior.
- [ ] Implement resilient storage completion and responsive fixed-footer layout.
- [ ] Replace slide content and use onboarding-only assets.
- [ ] Leave new Chinese/English strings for the single localization consolidation task.
- [ ] Run targeted tests until green.

## Chunk 2: Local OTA behavior and page

### Task 3: Normalize local-upgrade channels and access

**Files:**
- Modify: `inv_app/lib/features/ota/presentation/pages/local_ota_channel_select_page.dart`
- Modify: `inv_app/lib/features/device/presentation/pages/device_control_sections.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/ota_page.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/firmware_list_page.dart`
- Modify: `inv_app/lib/features/ota/presentation/widgets/device_picker_list.dart`
- Modify: `inv_app/lib/core/router/app_router.dart`
- Modify: `inv_app/lib/core/router/guards/auth_guard.dart`
- Delete: `inv_app/lib/features/ota/config/device_local_capabilities.dart` after verifying zero callers.
- Test: `inv_app/test/features/ota/presentation/pages/local_ota_channel_select_page_test.dart`
- Test: `inv_app/test/core/router/guards/auth_guard_test.dart`

- [ ] Write failing tests proving BLE and AP are visible for known and unknown models.
- [ ] Write failing route tests for authenticated, local-mode, and guest access.
- [ ] Remove model-based channel hiding and capability badges; route device-control, OTA, firmware-list, and legacy `/local-ota` entry points through the same two-channel choice flow.
- [ ] Add explicit local-upgrade routes to the allowed direct-connection path set.
- [ ] Add route-level tests proving `/local-ota`, device control, OTA page, and firmware list never silently default to WiFi.
- [ ] Run targeted tests until green.

### Task 4: Persist firmware model metadata and enforce pre-upload compatibility

**Files:**
- Modify: `inv_app/lib/core/services/firmware_download_service.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/local_ota_page.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/ota_page.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/firmware_list_page.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/firmware_library_page.dart`
- Test: `inv_app/test/core/services/firmware_download_service_test.dart`
- Test: `inv_app/test/features/ota/presentation/pages/local_ota_page_test.dart`

- [ ] Write failing serialization/download tests proving firmware `model` and service-provided `file_size` survive into `DownloadedFirmwareInfo`, storage JSON, and every download call site. Pass the model from each page's existing source: device-update response, `deviceModel`, or upgrade-package `model`; make `local_ota_page.dart` also pass `_firmwareMeta['file_size']`.
- [ ] Write failing BLE/AP tests for matching model, unknown device model, mismatched model, and legacy cache missing model.
- [ ] After connection and before upload, call `LocalCommunicationRepository.getDeviceInfo()` and strictly compare the real device model with firmware compatibility metadata.
- [ ] Fail closed with an actionable re-download message when firmware model metadata or device model is absent; do not reuse connection-channel capability rules for compatibility.
- [ ] Keep current size/SHA/signature/security-version validation and verify a fully described cached firmware still works without internet.

### Task 5: Redesign the local-upgrade scanner page

**Files:**
- Modify: `inv_app/lib/features/ota/presentation/pages/local_upgrade_page.dart`
- Test: `inv_app/test/features/ota/presentation/pages/local_upgrade_page_test.dart`

- [ ] Write failing widget tests for both channels, scanning/loading/empty/device states, and 320px layout.
- [ ] Implement the quiet-energy header, channel selector, dedicated local-upgrade illustration, and device result cards.
- [ ] Preserve existing discovery/connect/navigation behavior.
- [ ] Leave new Chinese/English strings for the single localization consolidation task.
- [ ] Run targeted tests until green.

## Chunk 3: About, App update removal, and network failure

### Task 6: Rebuild About and remove all App update triggers

**Files:**
- Modify: `inv_app/lib/features/profile/presentation/pages/about_page.dart`
- Modify: `inv_app/lib/core/router/shell/main_shell.dart`
- Modify: `inv_app/lib/features/notification/presentation/bloc/notification_bloc.dart`
- Modify: `inv_app/lib/features/notification/presentation/pages/notification_center_page.dart`
- Modify: `inv_app/lib/core/services/jpush_service.dart`
- Modify: `inv_app/lib/core/services/service_locator.dart`
- Delete: `inv_app/lib/core/services/app_update_service.dart`
- Modify: `inv_app/pubspec.yaml`
- Modify: `inv_app/android/app/src/main/AndroidManifest.xml`
- Test: `inv_app/test/features/profile/presentation/pages/about_page_test.dart`
- Test: `inv_app/test/core/router/shell/main_shell_test.dart`
- Test: `inv_app/test/features/notification/presentation/bloc/notification_bloc_test.dart`
- Delete: App-update-service-only tests after replacement behavior is covered.

- [ ] Write failing tests proving About contains no character/check-update entry and keeps legal links/version.
- [ ] Change notification tests to require zero `/ota/app/check` calls during load and refresh.
- [ ] Add a shell test proving startup does not schedule update checking.
- [ ] Remove update state, dialogs, download/install UI, automatic triggers, and generated App-update notifications. Preserve the persisted `SystemNotificationType` numeric index contract with a legacy placeholder or explicit migration, filter legacy App-update records after decoding, and test that other historical notification types keep their meaning.
- [ ] Explicitly ignore incoming `app_update` pushes with no navigation and test that they do not fall through to the default `/alarms` route.
- [ ] Implement the non-character energy-brand Hero and product positioning section.
- [ ] Delete `AppUpdateService` and remove zero-caller registration/imports; remove `open_filex` and `REQUEST_INSTALL_PACKAGES` only if a repository-wide search confirms they are App-update-only.
- [ ] Add a repository assertion that App code contains no `/ota/app/check`, `AppUpdateService`, APK installer call, or App check-update UI while device-firmware update strings remain.
- [ ] Run targeted tests until green.

### Task 7: Introduce a network-specific failure panel

**Files:**
- Create: `inv_app/lib/core/widgets/network_failure_panel.dart`
- Modify: `inv_app/lib/features/dashboard/presentation/pages/dashboard_overview_page.dart`
- Modify: `inv_app/lib/features/dashboard/presentation/bloc/dashboard_bloc.dart`
- Modify: `inv_app/lib/features/dashboard/presentation/bloc/dashboard_state.dart`
- Test: `inv_app/test/core/widgets/network_failure_panel_test.dart`
- Test: `inv_app/test/features/dashboard/presentation/pages/dashboard_overview_page_test.dart`

- [ ] Write failing tests for network-unavailable/no-cache, network-unavailable/with-cache, online request failure, retry, and semantic labeling.
- [ ] Implement the focused panel using `AppColor` tokens.
- [ ] Route only genuine network-unavailable/no-cache state to it; keep cached Dashboard plus its existing offline banner when cache exists, and retain generic request errors and device-offline visuals elsewhere.
- [ ] Run targeted tests until green.

## Chunk 4: Provisioning and final verification

### Task 8: Move the provisioning character below all content

**Files:**
- Modify: `inv_app/lib/features/device/presentation/pages/wifi_config_sections.dart`
- Modify: `inv_app/lib/features/device/presentation/pages/wifi_config_page.dart`
- Test: `inv_app/test/features/device/presentation/pages/wifi_config_page_test.dart`
- Test: `inv_app/test/features/device/presentation/widgets/wifi_provision_widgets_test.dart`

- [ ] Write failing tests proving the new asset appears once and after both AP/BLE business sections.
- [ ] Remove duplicated branch-level character images.
- [ ] Add one responsive bottom illustration with `BoxFit.contain` and correct semantics.
- [ ] Verify keyboard, narrow width, text scale 2.0, and both themes.

### Task 9: Consolidate localization strings

**Files:**
- Modify: `inv_app/lib/l10n/app_zh.dart`
- Modify: `inv_app/lib/l10n/app_en.dart`
- Modify callers changed in Tasks 2, 5, 6, 7, and 8 only as needed for final key names.
- Test: existing localization and affected widget tests.

- [ ] Collect all new/removed copy after page behavior has stabilized, so only one task owns the localization maps.
- [ ] Keep Chinese and English keys aligned and remove only App-version-update copy; preserve device-firmware update copy.
- [ ] Run localization and affected widget tests until green.

### Task 10: Integrated verification and cleanup

**Files:**
- Review all files changed in Tasks 1–9.

- [ ] Run focused Flutter tests for every changed feature.
- [ ] Run `make analyze-app`.
- [ ] Run `make test-app`.
- [ ] Run asset size/alpha inspection and verify no shared Xiaoshuo asset was overwritten.
- [ ] Run widget harnesses at 320×568, 375×812, 430×932, landscape, text scale 2.0, and light/dark themes.
- [ ] Exercise the real-device matrix BLE/AP × matching/unknown/mismatched model × online download/offline cache; report any unavailable hardware cases as outstanding rather than treating widget tests as device proof.
- [ ] Review `git diff --ignore-cr-at-eol` for scope and existing-change preservation.
- [ ] Perform a minimal simplify pass for duplicate page shells, colors, and strings.
- [ ] Report static/widget proof separately from real-device and browser proof.

## Multi-agent execution order

- Task 1 owns asset files, `pubspec.yaml` asset registration, and `CsergyAssets`; visual page tasks begin only after it lands.
- Tasks 2, 5, 7, and 8 may then proceed on non-overlapping page files, without touching localization maps.
- Task 3 completes before Task 4 because they share `ota_page.dart` and `firmware_list_page.dart` and because channel routing must stabilize before compatibility validation.
- Task 6 starts after Task 1, then owns the later `pubspec.yaml` dependency cleanup.
- Task 9 is the only owner of `app_zh.dart` and `app_en.dart` and runs after all page behavior tasks.
- Task 10 is the final integration, simplify, and verification pass.
