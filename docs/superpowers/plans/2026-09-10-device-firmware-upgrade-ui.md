# Device Firmware Upgrade UI Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Flutter OTA experience around the user's devices, replace chip abbreviations with functional module names throughout the OTA flow, and provide a device detail page with firmware versions, release notes, and upgrade history.

**Architecture:** Add one shared presentation mapping for firmware modules, keep the existing upgrade state machine, and add focused page-level coordinators for the paginated device hub and device-detail/history data. Extend the existing device-history API response with the matching firmware changelog through a left join; this is an additive response change and requires no migration.

**Tech Stack:** Flutter/Dart, Material 3, flutter_bloc, go_router, Dio, fpdart, Go/Gin, PostgreSQL/pgx

**Design:** `docs/superpowers/specs/2026-09-10-device-firmware-upgrade-ui-design.md`

**Git boundary:** Preserve all unrelated worktree changes. Do not commit or push unless the user explicitly asks.

---

## File Structure

**Create**

- `inv_app/lib/features/ota/presentation/models/firmware_module_presentation.dart` — maps internal chip identifiers to localized user-facing module keys and icon semantics; never returns a raw identifier.
- `inv_app/lib/features/ota/domain/entities/device_firmware_history.dart` — typed history entry and paginated result.
- `inv_app/lib/features/ota/presentation/pages/device_firmware_detail_page.dart` — aggregates device detail and recent history with independent loading/error states.
- `inv_app/lib/features/ota/presentation/pages/device_firmware_history_page.dart` — complete paginated history for one device.
- `inv_app/lib/features/ota/presentation/widgets/device_firmware_history_tile.dart` — shared rendering for recent and full history entries.
- `inv_app/test/features/ota/presentation/models/firmware_module_presentation_test.dart` — module mapping regression.
- `inv_app/test/features/ota/data/repositories/ota_repository_history_test.dart` — history response parsing and failures.
- `inv_app/test/features/ota/presentation/pages/ota_tab_page_test.dart` — hub layout, pagination, navigation, and secondary entries.
- `inv_app/test/features/ota/presentation/pages/device_firmware_detail_page_test.dart` — device fields, firmware cards, partial failures, and online/offline behavior.
- `inv_app/test/features/ota/presentation/pages/device_firmware_history_page_test.dart` — history states and pagination.
- `inv_app/test/features/ota/presentation/ota_visible_copy_contract_test.dart` — guards OTA presentation files against rendering raw chip abbreviations.
- `business-api/internal/repository/ota_history_changelog_postgres_integration_test.go` — exact changelog join and empty normalization.
- `business-api/internal/handler/ota_history_response_test.go` — JSON response contract for the additive history field.

**Modify**

- `business-api/internal/model/models.go` — add an omitted-when-empty transient `Changelog` response field to `DeviceUpgrade`; only device history populates it.
- `business-api/internal/repository/ota_repository.go` — left join firmware metadata in device history.
- `inv_app/lib/features/ota/data/datasources/ota_remote_data_source.dart` — call paginated per-device history endpoint.
- `inv_app/lib/features/ota/domain/repositories/ota_repository.dart` — expose typed device history method.
- `inv_app/lib/features/ota/data/repositories/ota_repository_impl.dart` — parse the API page safely.
- `inv_app/lib/features/ota/presentation/pages/ota_tab_page.dart` — device-first hub and paginated device list.
- `inv_app/lib/features/ota/presentation/pages/ota_page.dart` — use shared functional module labels.
- `inv_app/lib/features/ota/presentation/pages/firmware_list_page.dart` — replace raw chip labels and filenames shown to users.
- `inv_app/lib/features/ota/presentation/pages/firmware_library_page.dart` — replace raw chip labels shown to users.
- `inv_app/lib/features/ota/presentation/pages/upgrade_history_page.dart` — replace raw chip labels and share history presentation helpers where practical.
- `inv_app/lib/features/ota/presentation/pages/local_ota_page.dart` — replace any visible target-chip labels while preserving raw values for protocol calls.
- `inv_app/lib/core/router/app_router.dart` — register device firmware detail and filtered history routes.
- `inv_app/lib/l10n/app_zh.dart`, `inv_app/lib/l10n/app_en.dart` — add all new copy and replace chip-oriented OTA copy.
- `inv_app/lib/l10n/app_localizations.dart` — expose new strongly named getters only where existing pages use getters; otherwise use `str()` consistently.

---

## Chunk 1: Shared Language and History Contract

### Task 1: Add the firmware module presentation mapping

**Files:**
- Create: `inv_app/test/features/ota/presentation/models/firmware_module_presentation_test.dart`
- Create: `inv_app/lib/features/ota/presentation/models/firmware_module_presentation.dart`
- Modify: `inv_app/lib/l10n/app_zh.dart`
- Modify: `inv_app/lib/l10n/app_en.dart`

- [ ] **Step 1: Write the failing mapping tests**

Test a pure API with this intended behavior:

```dart
expect(FirmwareModulePresentation.fromTarget('esp').labelKey,
    'firmware_module_communication');
expect(FirmwareModulePresentation.fromTarget('ARM').labelKey,
    'firmware_module_system_control');
expect(FirmwareModulePresentation.fromTarget('dsp').labelKey,
    'firmware_module_power_control');
expect(FirmwareModulePresentation.fromTarget('bms').labelKey,
    'firmware_module_battery_management');
expect(FirmwareModulePresentation.fromTarget('vendor_x').labelKey,
    'firmware_module_generic');
expect(FirmwareModulePresentation.fromTarget('vendor_x').rawTarget,
    'vendor_x');
```

Also assert `displayLabel(l10n)` returns 通信采集 / 系统主控 / 功率控制 / 电池管理 / 设备组件 in Chinese and never contains `ESP`, `ARM`, `DSP`, or `BMS`; repeat the no-abbreviation assertion for English.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
cd inv_app && flutter test test/features/ota/presentation/models/firmware_module_presentation_test.dart
```

Expected: FAIL because the presentation model and localization keys do not exist.

- [ ] **Step 3: Implement the minimal immutable mapping**

Create an enum-backed or const value object with:

```dart
enum FirmwareModuleKind { communication, systemControl, powerControl, batteryManagement, generic }

final class FirmwareModulePresentation {
  final FirmwareModuleKind kind;
  final String rawTarget; // retained for requests only
  String get labelKey;
  String get descriptionKey;
  IconData get icon;
  static FirmwareModulePresentation fromTarget(String? value);
  static FirmwareModulePresentation fromFirmwareField(String field);
  String displayLabel(AppLocalizations l10n) => l10n.str(labelKey);
}
```

Normalize input with `trim().toLowerCase()`. Known internal values map to the four named modules; all other values map to `generic`. Do not expose a method that uppercases or returns the raw target for display.

Add paired zh/en keys only for module names, module descriptions, generic fallback, and “version not reported.” Page-specific copy is added and tested with the pages that consume it in Chunks 2 and 3.

- [ ] **Step 4: Run the focused test and confirm GREEN**

Run the command from Step 2. Expected: PASS with zero failures.

- [ ] **Step 5: Format and review the scoped diff**

Run:

```bash
cd inv_app && dart format lib/features/ota/presentation/models/firmware_module_presentation.dart test/features/ota/presentation/models/firmware_module_presentation_test.dart
git diff --check -- inv_app/lib/features/ota/presentation/models/firmware_module_presentation.dart inv_app/lib/l10n/app_zh.dart inv_app/lib/l10n/app_en.dart inv_app/test/features/ota/presentation/models/firmware_module_presentation_test.dart
```

Expected: formatter exit 0 and no whitespace errors. Leave changes uncommitted.

### Task 2: Add changelog to the device-history contract

**Files:**
- Create: `business-api/internal/repository/ota_history_changelog_postgres_integration_test.go`
- Create: `business-api/internal/handler/ota_history_response_test.go`
- Modify: `business-api/internal/model/models.go`
- Modify: `business-api/internal/repository/ota_repository.go`

- [ ] **Step 1: Write the failing PostgreSQL integration test**

Seed three valid `device_upgrades` rows for one device:

1. a row whose `firmware_id` resolves to a firmware with `changelog = 'Improve reconnect stability'`;
2. a row whose firmware has an empty changelog;
3. a row whose firmware exists but is no longer published (`status = 0`) and has a historical changelog.

Call `GetDeviceUpgradeHistory(ctx, sn, 1, 20)` and assert all three results remain present and return respectively the real text, `""`, and the historical text. Assert the count remains three and ordering stays `updated_at DESC`. The production foreign key prevents a truly missing firmware row, so unmatched-left-join behavior is defensive SQL rather than a fixture that weakens constraints.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
cd business-api && go test -tags=integration ./internal/repository -run TestGetDeviceUpgradeHistoryIncludesChangelog -count=1 -v
```

Expected: FAIL because `DeviceUpgrade` and the query do not return changelog. If the integration database is unavailable, record that boundary, but still keep the test as the contract.

- [ ] **Step 3: Write the failing JSON response contract test**

Use Gin test mode and `httptest.NewRecorder()` to serialize the same envelope used by `GetDeviceOTAHistory`:

```go
response.Success(c, gin.H{
    "items": []model.DeviceUpgrade{{Changelog: "Improve reconnect stability"}},
    "total": 1,
})
```

Decode the body and assert `data.items[0].changelog` equals the text. Serialize an empty changelog and assert it is omitted consistently because the model field uses `omitempty`; the Flutter parser must normalize a missing field to `""`.

Run:

```bash
cd business-api && go test ./internal/handler -run TestDeviceOTAHistoryResponseIncludesChangelog -count=1 -v
```

Expected: FAIL because the field does not exist.

- [ ] **Step 4: Implement the additive response field and left join**

Add to `DeviceUpgrade`:

```go
Changelog string `json:"changelog,omitempty"`
```

This shared model addition is intentionally safe for other endpoints: they do not populate the field, and `omitempty` keeps their JSON unchanged. Device-level history is the only query that fills it.

Change only the device history query to select:

```sql
COALESCE(f.changelog, '')
FROM device_upgrades du
LEFT JOIN firmware_versions f ON f.id = du.firmware_id
WHERE du.device_sn = $1
ORDER BY du.updated_at DESC
```

Qualify all selected `device_upgrades` columns with `du.` and scan `Changelog` in the matching position. Keep the count query and response format unchanged. Do not filter on firmware status: a past upgrade keeps its release note even if that firmware is no longer published.

- [ ] **Step 5: Run the focused tests and regressions**

Run:

```bash
cd business-api && go test -tags=integration ./internal/repository -run TestGetDeviceUpgradeHistoryIncludesChangelog -count=1 -v
cd business-api && go test ./internal/handler -run TestDeviceOTAHistoryResponseIncludesChangelog -count=1 -v
cd business-api && go test ./internal/repository ./internal/service ./internal/handler
```

Expected: available commands exit 0. Do not claim the integration test passed if its database is unavailable.

- [ ] **Step 6: Format and inspect**

Run:

```bash
gofmt -w business-api/internal/model/models.go business-api/internal/repository/ota_repository.go business-api/internal/repository/ota_history_changelog_postgres_integration_test.go business-api/internal/handler/ota_history_response_test.go
git -c core.whitespace=cr-at-eol diff --check -- business-api/internal/model/models.go business-api/internal/repository/ota_repository.go business-api/internal/repository/ota_history_changelog_postgres_integration_test.go business-api/internal/handler/ota_history_response_test.go
```

Expected: no formatting or whitespace errors. Leave changes uncommitted.

---

## Chunk 2: Typed Data and Device-First Hub

### Task 3: Add a typed device firmware history repository API

**Files:**
- Create: `inv_app/lib/features/ota/domain/entities/device_firmware_history.dart`
- Create: `inv_app/test/features/ota/data/repositories/ota_repository_history_test.dart`
- Modify: `inv_app/lib/features/ota/data/datasources/ota_remote_data_source.dart`
- Modify: `inv_app/lib/features/ota/domain/repositories/ota_repository.dart`
- Modify: `inv_app/lib/features/ota/data/repositories/ota_repository_impl.dart`

- [ ] **Step 1: Write parsing and error tests first**

Using a Dio mock adapter or mocked datasource, cover:

- `data.items`, `total`, `page`, and `page_size` parse into `DeviceFirmwareHistoryPage`;
- missing optional strings normalize to empty strings;
- timestamps parse to nullable `DateTime` values without throwing;
- unknown target/status values are retained internally for presentation mapping;
- malformed `items` returns `ServerFailure` rather than an empty success;
- Dio 403 maps to `ForbiddenFailure`.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
cd inv_app && flutter test test/features/ota/data/repositories/ota_repository_history_test.dart
```

Expected: FAIL because the entity and repository method do not exist.

- [ ] **Step 3: Implement the domain entity and repository boundary**

Expose:

```dart
Future<Either<Failure, DeviceFirmwareHistoryPage>> getDeviceFirmwareHistory(
  String sn, {
  int page = 1,
  int pageSize = 20,
});
```

The datasource must call `/ota/devices/$sn/history` with `page` and `page_size`. Parsing must validate `code == 0`, `data` is a map, and `items` is a list; populate `page/pageSize` from the response when present and otherwise use the request values because the current endpoint returns only `items/total`.

- [ ] **Step 4: Run focused test and existing OTA repository/bloc tests**

Run:

```bash
cd inv_app && flutter test test/features/ota/data/repositories/ota_repository_history_test.dart test/features/ota/presentation/bloc/ota_bloc_test.dart
```

Expected: PASS with zero failures.

- [ ] **Step 5: Format and diff-check**

Run `dart format` on all Task 3 Dart files, followed by `git -c core.whitespace=cr-at-eol diff --check -- <exact Task 3 paths>`. Expected: exit 0.

### Task 4: Rebuild the OTA hub around a paginated device list

**Files:**
- Create: `inv_app/test/features/ota/presentation/pages/ota_tab_page_test.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/ota_tab_page.dart`
- Modify: `inv_app/lib/l10n/app_zh.dart`
- Modify: `inv_app/lib/l10n/app_en.dart`

- [ ] **Step 1: Write failing hub widget tests**

Inject a `DeviceRepository` into `OtaTabPage` for tests, defaulting to `getIt<DeviceRepository>()` in production. Cover:

- title “设备固件升级” and exact returned `total`;
- device display fallback `alias → model → sn`;
- status `1` and `2` render online, status `0` renders offline;
- device rows appear before the secondary tools;
- tapping a device calls `/ota/device/<encoded-sn>`;
- the four secondary entries navigate to `/ota/check-all`, `/local-upgrade`, `/firmware-library`, and `/upgrade-history`;
- scrolling requests page 2 once, appends without duplicates, and stops when loaded count reaches `total`;
- refresh replaces page 1 data;
- empty and first-page failure states retain the near-field upgrade entry.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
cd inv_app && flutter test test/features/ota/presentation/pages/ota_tab_page_test.dart
```

Expected: FAIL because the current page is the four-card hub and has no device repository.

- [ ] **Step 3: Implement minimal page-level pagination state**

Convert `OtaTabPage` to `StatefulWidget`. Keep state fields `_devices`, `_total`, `_page`, `_loadingFirstPage`, `_loadingMore`, and `_error`. Fetch 20 items per page through `DeviceRepository.getList`; deduplicate by `sn`; guard concurrent load-more requests; preserve prior rows on a load-more failure and expose retry at the footer.

Add and consume the paired zh/en keys for the hub title, device count, sections, secondary entries, loading/empty/error states, and load-more retry. Render the approved hierarchy:

1. accurate `total` summary;
2. “我的设备” list;
3. “更多升级功能” two-column cards with the four retained routes.

Use URL-safe route construction with `Uri.encodeComponent(sn)`. Keep raw data keys internal and do not render chip abbreviations.

- [ ] **Step 4: Run focused tests and the existing device picker regression**

Run:

```bash
cd inv_app && flutter test test/features/ota/presentation/pages/ota_tab_page_test.dart test/features/ota/presentation/widgets/device_picker_list_test.dart
```

Expected: PASS with zero failures.

- [ ] **Step 5: Format and diff-check**

Format both Task 4 files and run scoped `git -c core.whitespace=cr-at-eol diff --check`. Expected: exit 0.

---

## Chunk 3: Device Detail, Full History, and OTA-Wide Copy Cleanup

### Task 5: Build the device firmware detail and filtered history pages

**Files:**
- Create: `inv_app/test/features/ota/presentation/pages/device_firmware_detail_page_test.dart`
- Create: `inv_app/test/features/ota/presentation/pages/device_firmware_history_page_test.dart`
- Create: `inv_app/lib/features/ota/presentation/pages/device_firmware_detail_page.dart`
- Create: `inv_app/lib/features/ota/presentation/pages/device_firmware_history_page.dart`
- Create: `inv_app/lib/features/ota/presentation/widgets/device_firmware_history_tile.dart`
- Modify: `inv_app/lib/l10n/app_zh.dart`
- Modify: `inv_app/lib/l10n/app_en.dart`

- [ ] **Step 1: Write failing detail widget tests**

Inject `DeviceRepository` and `OtaRepository` with production defaults from `getIt`. Cover:

- `data.device` renders model, alias fallback, SN, and hardware version;
- `firmware_esp/arm/dsp/bms` render under the four functional labels and no chip abbreviation is present;
- empty versions render “版本未上报”; the BMS card does not claim disconnected or unsupported;
- explicit `online_status.online == false` disables the check button even if `device.status == 1`;
- missing `online_status` falls back to status `1/2` as online;
- tapping the enabled button pushes `/ota/:sn`;
- recent history renders only the first three entries and “查看全部” pushes `/ota/device/:sn/history`;
- detail failure blocks the main content with retry, while history failure keeps device/firmware content and has an independent retry;
- empty history renders the approved empty message.

- [ ] **Step 2: Write failing full-history widget tests**

Cover first-page loading/error/empty, status presentation (including unknown status), module mapping, changelog/error rendering, load-more append and stop-at-total behavior.

- [ ] **Step 3: Run both tests and confirm RED**

Run:

```bash
cd inv_app && flutter test test/features/ota/presentation/pages/device_firmware_detail_page_test.dart test/features/ota/presentation/pages/device_firmware_history_page_test.dart
```

Expected: FAIL because both pages are absent.

- [ ] **Step 4: Implement independent aggregation states**

The detail page starts the detail and recent-history requests concurrently. Store `_detailLoading/_detailError/_detailData` separately from `_historyLoading/_historyError/_historyPage`. Add and consume paired zh/en keys for device information, firmware detail, history, statuses, empty/error actions, and the offline check explanation. Derive online as:

```dart
final onlineMap = payload['online_status'];
final hasExplicitOnline = onlineMap is Map && onlineMap['online'] is bool;
final isOnline = hasExplicitOnline
    ? onlineMap['online'] == true
    : device['status'] == 1 || device['status'] == 2;
```

Build firmware cards from a const list of `(field, presentation)` pairs. Display reported version text only; do not infer update availability. Put status mapping and entry rendering in `device_firmware_history_tile.dart` from the start, and reuse it in the detail and full-history pages.

- [ ] **Step 5: Run focused tests and refactor while green**

Run the Step 3 command. Expected: PASS. If history row rendering is duplicated, extract `device_firmware_history_tile.dart`, rerun tests, and keep behavior unchanged.

- [ ] **Step 6: Format and diff-check**

Format all Task 5 files and run the scoped whitespace check. Expected: exit 0.

### Task 6: Register routes and remove chip abbreviations from the entire OTA flow

**Files:**
- Modify: `inv_app/lib/core/router/app_router.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/ota_page.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/firmware_list_page.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/firmware_library_page.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/upgrade_history_page.dart`
- Modify: `inv_app/lib/features/ota/presentation/pages/local_ota_page.dart`
- Modify: `inv_app/test/features/ota/presentation/pages/ota_page_confirm_test.dart`
- Create: `inv_app/test/core/router/ota_route_contract_test.dart`
- Create: `inv_app/test/features/ota/presentation/ota_visible_copy_contract_test.dart`

- [ ] **Step 1: Write failing route and visible-copy regressions**

Add route tests proving `/ota/device/SN-001` builds the detail page, `/ota/device/SN-001/history` builds the filtered history page, and `/ota/SN-001` still builds `OTAPage`.

Extend `ota_page_confirm_test.dart` with API fixtures containing every raw target and assert visible text uses the functional module label. Add `ota_visible_copy_contract_test.dart` that scans the named OTA presentation page sources and fails on the known raw-display patterns (`target_chip` followed by `toUpperCase`, literal chip labels passed to visible version rows, and the legacy localization value “待升级芯片”). Do not ban raw identifiers in data/controller code because the protocol still requires them; normalization for SSID/SN matching is also outside this display contract.

- [ ] **Step 2: Run the route and OTA presentation tests and confirm RED**

Run:

```bash
cd inv_app && flutter test test/core/router/ota_route_contract_test.dart test/features/ota
```

Expected: FAIL on absent routes and existing raw chip display.

- [ ] **Step 3: Register routes and replace every visible raw target**

Add imports and routes for `DeviceFirmwareDetailPage(sn: ...)` and `DeviceFirmwareHistoryPage(sn: ...)`. Use `FirmwareModulePresentation.fromTarget(...)` at every display boundary in the named OTA pages. Keep raw targets unchanged for downloads, install requests, filenames used only on disk, and local protocol commands. Update zh/en text from chip-oriented wording to module-oriented wording, for example “待更新模块” / “Modules to Update”.

For unknown targets, render “设备组件” / “Device Component”. Error templates receiving a target must receive the mapped display label rather than the raw target.

- [ ] **Step 4: Run focused and full OTA tests**

Run:

```bash
cd inv_app && flutter test test/core/router/ota_route_contract_test.dart test/features/ota
```

Expected: PASS with zero failures and no raw chip abbreviations in rendered OTA copy.

- [ ] **Step 5: Format and diff-check**

Run `dart format` on all changed Dart files and a scoped CRLF-safe whitespace check. Expected: exit 0.

### Task 7: Final behavior verification

**Files:**
- Review all paths listed above.

- [ ] **Step 1: Run Flutter static analysis**

Run:

```bash
cd inv_app && flutter analyze
```

Expected: exit 0 with no errors. Record pre-existing warnings separately if the command is not clean.

- [ ] **Step 2: Run Flutter OTA and route suites**

Run:

```bash
cd inv_app && flutter test test/features/ota test/core/router
```

Expected: all tests pass.

- [ ] **Step 3: Run Go regression and vet checks**

Run:

```bash
cd business-api && go test ./internal/repository ./internal/service ./internal/handler
cd business-api && go vet ./internal/repository ./internal/service ./internal/handler
```

Expected: all available checks exit 0.

- [ ] **Step 4: Perform a user-flow smoke test**

Run the App against a reachable development backend if available and verify:

1. open “设备固件升级”;
2. paginate/refresh the user's device list;
3. open one online and one offline device;
4. verify device fields and four functional firmware cards;
5. verify recent and full history show the matching changelog;
6. verify online check navigation and offline disabled behavior;
7. enter each retained secondary function and confirm no user-visible chip abbreviations.

If no backend/device runtime is available, report this step as `Partial` rather than passed.

- [ ] **Step 5: Review the final worktree diff**

Run:

```bash
git status --short
git diff --ignore-cr-at-eol -- business-api/internal/model/models.go business-api/internal/repository/ota_repository.go business-api/internal/repository/ota_history_changelog_postgres_integration_test.go inv_app/lib/features/ota inv_app/lib/core/router/app_router.dart inv_app/lib/l10n inv_app/test/features/ota inv_app/test/core/router docs/superpowers/specs/2026-09-10-device-firmware-upgrade-ui-design.md docs/superpowers/plans/2026-09-10-device-firmware-upgrade-ui.md
git -c core.whitespace=cr-at-eol diff --check -- business-api/internal/model/models.go business-api/internal/repository/ota_repository.go business-api/internal/repository/ota_history_changelog_postgres_integration_test.go inv_app/lib/features/ota inv_app/lib/core/router/app_router.dart inv_app/lib/l10n inv_app/test/features/ota inv_app/test/core/router docs/superpowers/specs/2026-09-10-device-firmware-upgrade-ui-design.md docs/superpowers/plans/2026-09-10-device-firmware-upgrade-ui.md
```

Expected: only scoped intended changes are present in the reviewed diff; unrelated worktree changes remain untouched. Do not commit or push.
