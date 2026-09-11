# Device Firmware Upgrade Visual Polish Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the OTA hub with a project-specific transparent illustration, move the device update action into the bottom of the scroll content, and preserve truthful online and pagination states.

**Architecture:** Keep the existing OTA repositories, routes, and page state. Add one centralized art asset, refine only the two new OTA pages, and encode the button placement and online precedence in widget tests. The HTML companion mirrors the Flutter composition but remains a non-production preview.

**Tech Stack:** Flutter/Dart, Material 3, Flutter widget tests, PNG with alpha, local HTML/CSS preview

---

## Chunk 1: Behavior and asset contract

### Task 1: Lock button placement and online precedence with tests

**Files:**
- Modify: `inv_app/test/features/ota/presentation/pages/device_firmware_pages_test.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/device_firmware_detail_page.dart`
- Modify: `inv_app/lib/l10n/app_zh.dart`
- Modify: `inv_app/lib/l10n/app_en.dart`

- [ ] **Step 0: Record the deferred About-page baseline**

Run scoped `git status --short` and `git diff --` checks for `inv_app/lib/features/profile/presentation/pages/about_page.dart` and all existing `inv_app/assets/character/xiaoshuo/` files. Save the result in the execution notes for comparison at completion.

- [ ] **Step 1: Write failing widget assertions**

Add tests that set the test surface to 390×844, build a device with `status: 1` and explicit `online_status.online: false`, then verify the offline hint is visible and the “检查固件更新” `FilledButton` has a null callback. Assert the detail scaffold has no `bottomNavigationBar`, scroll to the bottom, verify the button is visible, and use `find.ancestor` to assert its ancestor includes the detail `ListView`.

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
cd inv_app && flutter test --no-pub test/features/ota/presentation/pages/device_firmware_pages_test.dart
```

Expected: FAIL because current online calculation overwrites explicit false and the button is in `bottomNavigationBar`.

- [ ] **Step 3: Implement explicit realtime-state precedence**

Track whether `online_status.online` was present separately from the database status. Compute online as the realtime boolean when present; otherwise fall back to `status == 1 || status == 2`.

- [ ] **Step 4: Move the action into normal document flow**

Remove the scaffold `bottomNavigationBar`. After the firmware history content, add the offline hint when required, then a full-width `FilledButton.icon` as the final `ListView` child. Keep the existing `/ota/:sn` navigation.

- [ ] **Step 5: Run the focused test**

Expected: all page tests pass at 390×844 without overflow.

### Task 2: Add and validate the OTA illustration

**Files:**
- Modify: `inv_app/test/features/ota/presentation/pages/device_firmware_pages_test.dart`

- [x] **Step 1: Reject invalid generated variants**

Two built-in generated candidates were checked and rejected because both were RGB files that painted a checkerboard instead of encoding alpha transparency. Neither candidate is copied into the project.

- [x] **Step 2: Select the existing release asset**

Reuse `CsergyAssets.xiaoshuoOtaGuide`, which already points to the 1536×1024 OTA illustration. Validate the hydrated Git LFS file contains PNG transparency information and visually inspect it on the light hero background. Keep `errorBuilder` so source-only/LFS-pointer test environments render a safe fallback icon.

- [x] **Step 3: Preserve asset boundaries**

Do not add, copy, overwrite, or re-cut any character image in this task. The separate About-page cutout issue remains deferred.

- [x] **Step 4: Use the centralized asset**

Reference `CsergyAssets.xiaoshuoOtaGuide` from the OTA hub. Do not embed a raw path in the page.

- [ ] **Step 5: Extend the widget test**

Assert the hub contains an `Image` using `CsergyAssets.xiaoshuoOtaGuide` and retains all four secondary routes.

## Chunk 2: Visual implementation and verification

### Task 3: Refine the hub and device detail composition

**Files:**
- Modify: `inv_app/lib/features/ota/presentation/pages/ota_tab_page.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/device_firmware_detail_page.dart`
- Modify: `inv_app/lib/l10n/app_zh.dart`
- Modify: `inv_app/lib/l10n/app_en.dart`

- [ ] **Step 1: Replace the dark hub hero**

Build a light brand-tinted hero with copy and API `total` on the left and the transparent illustration on the right. Remove the loaded-page online counter.

- [ ] **Step 2: Reduce card chrome**

Use theme-aware soft surfaces and restrained borders for device cards. Keep name, model, serial number, status, pagination, refresh, errors, and navigation unchanged.

- [ ] **Step 3: Preserve four secondary capabilities**

Keep the 2×2 grid and its four routes. Use user-facing names “检查全部更新、近场连接升级、固件资源、全部更新记录” with concise descriptions.

- [ ] **Step 4: Keep the detail page focused**

Retain the light device summary, two-column metadata, 2×2 firmware module cards, and timeline. Do not add a second character illustration.

- [ ] **Step 5: Format and analyze touched Dart files**

Run targeted `dart format`, then from `inv_app/` run `flutter analyze --no-pub --no-fatal-infos` for the touched files. Expected: no warnings or errors; repository-wide info lints may remain.

### Task 4: Sync preview and complete verification

**Files:**
- Modify outside Git worktree: `.codex/visualizations/2026/09/10/01a08a0c-919e-7ab3-bafa-a1660c1e9c6c/ota-final-flow.html`

- [ ] **Step 1: Update the HTML companion**

Mirror the light illustrated hero in the HTML companion without copying a new bitmap, and place the detail action after the final timeline entry instead of using `position:absolute`.

- [ ] **Step 2: Verify the preview server**

Start `python3 -m http.server 8765 --bind 0.0.0.0` from the visualization directory when no server is active. Request `http://127.0.0.1:8765/ota-final-flow.html` and confirm the new hero, image, and document-flow button are present. If the port cannot be bound, validate the file directly and report that live preview serving was not verified.

- [ ] **Step 3: Run OTA regression tests**

Run:

```bash
cd inv_app && flutter test --no-pub test/features/ota
```

Expected: all OTA tests pass.

- [ ] **Step 4: Review the scoped diff**

Before implementation, record `git status --short` for `inv_app/lib/features/profile/presentation/pages/about_page.dart` and the existing `assets/character/xiaoshuo/` files. After implementation, run the same scoped status and `git diff --` checks, plus `git -c core.whitespace=cr-at-eol diff --check` and `git diff --ignore-cr-at-eol`, proving this work introduced no About-page or existing-character-asset changes.

- [ ] **Step 5: Leave a verified scoped worktree change**

Leave only the new OTA asset, centralized asset declaration, OTA pages, localization, tests, and preview change. Do not stage, commit, or push unless the user explicitly asks for the new polish revision to be committed.
