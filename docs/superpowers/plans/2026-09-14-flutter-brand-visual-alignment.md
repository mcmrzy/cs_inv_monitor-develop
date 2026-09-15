# Flutter App Brand Visual Alignment Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the off-brand generated artwork with the existing Xiaoshuo mascot family, restore all affected controls to the App blue theme, and reinstate the approved removal of App update checks.

**Architecture:** Treat the existing `CsergyAssets.xiaoshuo*` constants as the single brand-illustration source. Update only page-to-asset mappings and onboarding theme tokens, remove redundant generated files/constants/asset registrations, and lock the mapping with widget tests.

**Tech Stack:** Flutter, Dart, flutter_test, existing `AppColor`/`AppColors` tokens and Xiaoshuo PNG assets.

---

## Chunk 1: Brand asset mapping

### Task 1: Make current tests describe the approved mapping

**Files:**
- Modify: `inv_app/test/features/onboarding/presentation/pages/onboarding_page_test.dart`
- Modify: `inv_app/test/features/dashboard/presentation/pages/dashboard_overview_page_test.dart`
- Create: `inv_app/test/features/ota/presentation/pages/local_upgrade_page_test.dart`
- Modify: `inv_app/test/features/device/presentation/widgets/wifi_provision_widgets_test.dart`
- Modify: `inv_app/test/features/profile/presentation/pages/about_page_test.dart`
- Modify: `inv_app/test/assets/asset_integrity_test.dart`

- [ ] Replace assertions for the six generated paths with the approved `CsergyAssets.xiaoshuo*` mappings.
- [ ] Add a focused `LocalUpgradePage` widget harness with mocked discovery repositories and assert its empty-state `Image` uses `CsergyAssets.xiaoshuoOtaGuide`.
- [ ] Add/retain an About assertion proving no Xiaoshuo or person image is rendered.
- [ ] Run the focused tests and confirm they fail against the current bindings.

### Task 2: Replace bindings and restore theme tokens

**Files:**
- Modify: `inv_app/lib/features/onboarding/presentation/pages/onboarding_page.dart`
- Modify: `inv_app/lib/core/widgets/network_failure_panel.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/local_upgrade_page.dart`
- Modify: `inv_app/lib/features/device/presentation/widgets/wifi_provision_widgets.dart`
- Modify: `inv_app/lib/core/theme/csergy_assets.dart`
- Modify: `inv_app/pubspec.yaml`
- Delete: `inv_app/assets/images/onboarding/onboarding_energy_overview.png`
- Delete: `inv_app/assets/images/onboarding/onboarding_status_alerts.png`
- Delete: `inv_app/assets/images/onboarding/onboarding_local_service.png`
- Delete: `inv_app/assets/images/states/network_connection_failed.png`
- Delete: `inv_app/assets/images/states/local_upgrade_connection.png`
- Delete: `inv_app/assets/images/provisioning/provisioning_companion_bottom.png`

- [ ] Map onboarding to station/reminder/Wi-Fi Xiaoshuo assets.
- [ ] Replace hard-coded teal and orange onboarding accents with `AppColor.primary(context)` and primary-blue derived opacity.
- [ ] Map network failure to `xiaoshuoOffline`, local upgrade to `xiaoshuoOtaGuide`, and provisioning footer to `xiaoshuoWifiGuide`.
- [ ] Remove generated asset constants and directory registrations, then delete the redundant PNGs.
- [ ] Run focused tests until green.

### Task 3: Restore the approved no-App-update state

**Files:**
- Modify: `inv_app/lib/core/router/shell/main_shell.dart`
- Modify: `inv_app/lib/features/profile/presentation/pages/about_page.dart`
- Modify: `inv_app/lib/core/services/service_locator.dart`
- Modify: `inv_app/android/app/src/main/AndroidManifest.xml`
- Modify: `inv_app/pubspec.yaml`
- Delete: `inv_app/lib/core/services/app_update_service.dart`
- Delete: `inv_app/lib/core/services/app_update_flow.dart`
- Delete: `inv_app/test/core/services/app_update_service_test.dart`
- Modify: `inv_app/test/features/profile/presentation/pages/about_page_test.dart`

- [ ] Add a failing About assertion that no check-update row is rendered. Verify MainShell removal through the residual source search below, analyzer, and full test suite because this repository has no isolated MainShell widget harness.
- [ ] Remove the shell auto-check, About update action/service dependency, and service-locator registration while retaining real package version display through `PackageInfo`.
- [ ] Delete the App update service/flow and their obsolete service test.
- [ ] Remove `open_filex` and `REQUEST_INSTALL_PACKAGES`; retain `package_info_plus` for About version display and retain `path_provider` for firmware downloads.
- [ ] Search App sources for `/ota/app/check`, `AppUpdateService`, `AppUpdateFlow`, APK installation calls and update UI; expected result is no matches outside historical documentation.
- [ ] Run the existing About and notification focused tests until green; cover MainShell and service-locator changes with residual source search, Flutter analyze, and the full suite.

## Chunk 2: Verification

### Task 4: Verify layout and regressions

**Files:**
- Review all files changed in Tasks 1–3.

- [ ] Run asset integrity, onboarding, dashboard, local OTA, provisioning and About tests.
- [ ] Run Flutter analyze and separate pre-existing info findings from new errors.
- [ ] Run the full Flutter test suite.
- [ ] Review `git diff --ignore-cr-at-eol` and ensure feature logic from `20478293e` is unchanged.
- [ ] Include the no-App-update residual search in final diff review and confirm the deletions did not remove device-firmware update or offline firmware-cache behavior.
- [ ] Report browser/device visual proof separately if no real-device run is available.
