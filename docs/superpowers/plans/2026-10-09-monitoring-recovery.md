# Monitoring and Recovery Implementation Plan

> **For agentic workers:** Use subagent-driven-development for isolated tasks. Preserve existing work. No automatic commit, push, deployment or device flashing.

**Goal:** Make cloud monitoring, organization overview, device information, debug recovery and OTA usable and consistent across App and Web.

**Architecture:** Keep existing REST contracts and authorization services. Aggregate authorized resources using organization scopes, never role-only expansion. Distinguish reported counters, recorded energy, stage progress and overall progress.

**Tech Stack:** Go/Gin/PostgreSQL, Flutter/Dart, React/TypeScript/Ant Design.

## Task 1: Organization Overview

Files: business-api/internal/handler/dashboard_handler.go, station_handler.go; existing authorization service/repository and scoped resource queries; focused tests.

- [x] Add failing tests for ancestor visibility, sibling isolation, disabled/expired membership, system administrator and more than 100 stations.
- [x] Reuse validated ActorContext and BuildScope for dashboard REST, streaming updates and station summary/list/detail.
- [x] Run focused Go tests, review authorization boundaries and query placeholders.

## Task 2: Energy and Device Information

Files: business-api/internal/repository/telemetry_v2_repository.go, repositories.go; device model/service; inv_app/lib/core/widgets/device_list_view.dart and relevant device/station pages.

- [x] Verify generation versus PV counters and units against decoder/source tests.
- [x] Test reported lifetime, missing/reset counters and recorded-energy fallback without summing absolute reports; wire the server floor into the App.
- [x] Include correct rated_power_w plus existing kW compatibility; enrich list cards with real available identity, state, energy and timestamp.
- [x] Map detected BMS to a battery child of its inverter, inherit access, preserve offline/stale state and avoid fictitious specifications.
- [x] Verify Go and Flutter behavior with absent, zero, stale and actual nonzero values.

## Task 3: Debug Recovery

Files: business-api/internal/service/device_debug_service.go and coordinator, repository/device_debug_repository.go; App device_debug_api.dart and debug page; tests.

- [x] Reproduce interrupted terminal handling, stop retry, lost ACK, expiry and reboot cases.
- [x] Allow restart after interrupted session; make stop idempotent/retryable and bounded; never keep debug active on normal telemetry alone.
- [x] Run focused service and App widget tests.

## Task 4: OTA

Files: existing firmware library/App OTA pages and BLoC; business-api OTA repository/service/handler; device-communication progress handling; authoritative firmware OTA service and MQTT adapter if necessary.

- [x] Add authorized compatible device selection and remote upgrade action to firmware resources, independently of local download state.
- [x] Expose phase percent 0-100 separately from overall percent in App and Web; label legacy weighted reports as overall rather than inventing phase percentages.
- [x] Persist and return stage on task/detail/history APIs; keep completion separate from reaching 100 percent.
- [x] Test transitions, restart/stall detection, legacy/new reports and authorization; build firmware with approved filesystem access, do not flash.

## Task 5: Storage Presentation and Integration

Files: App device_storage_page.dart, bms_summary_view.dart, station detail and shared cards; necessary translations/tests.

- [x] Present SOC, signed power, state, cell consistency and alerts first; retain technical diagnostics and absent/stale states.
- [x] Review preview/screenshots for compact/mobile layouts and long names.
- [x] Run full Go build/test/vet, frontend build/typecheck/tests and Flutter analysis/tests.
- [x] Report source/build evidence separately from production data and hardware acceptance.

## Additional Review Fixes

- [x] Replace accepted realtime snapshots, including derived fields; prefer explicit online booleans and reject stale replies.
- [x] Add App paged raw/hourly history with a single device timezone for date bounds, buckets and display, including 23/25-hour DST days.
- [x] Keep the Web history header sticky while scrolling vertically and horizontally.
- [x] Prevent whole-upgrade progress from reaching 100 during download and then falling to 70 during ARM/DSP/BMS transfer.

Production deployment, physical device power cycling, phone installation and live OTA are not claimed by this plan's completed implementation checks. See the verification report.
