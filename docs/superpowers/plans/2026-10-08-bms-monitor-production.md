# BMS Monitor Production Implementation Plan

**Goal:** Integrate the approved Web/mobile monitoring design with real CMD08 data.

**Architecture:** The normalized `realtime.bms_summary` is independent from legacy
`bms` and inverter battery metrics. Each client preserves old-protocol fallback,
uses the trusted summary expiration deadline, and separates current engineering
values from historical diagnostics. UI surfaces follow the approved interactive
preview, without copying fixture values or adding a production preview route.

**Tech Stack:** React/Ant Design/ECharts and Flutter/Material/fl_chart.

## Ownership

- Web worker: `inv-admin-frontend/src/pages/device-detail/BmsTab.tsx`, new CMD08
  parser/components/styles/tests nearby, and Web locale files only.
- Mobile worker: `inv_app/lib/features/device/presentation/widgets/bms_summary_view.dart`,
  new focused BMS widgets, storage-page integration, App locale/test files only.
- Coordinator: browser verification harness, protocol documentation, integration
  review, final builds and independent regression validation. No worker overlaps.

## Acceptance

- [x] Real summary: overview, 16 selectable cells, balance markers, grouped
  warning/protection/faults, capacity/temperature and complete diagnostics.
- [x] Unknown/null fields never become zero. Negative current and temperature
  preserved. Layout-0 unpopulated temperatures stay unavailable. Unknown quantity
  units and enums remain raw; SOC/SOH provisional scaling is disclosed.
- [x] Expired/unknown BMS state masks live metrics and clearly labels retained
  historical flags/raw bytes. Refresh failure must not extend old expiration.
- [x] Charge/discharge/MOS operational bits are not classified as faults.
- [x] Legacy protocol behavior and older no-BMS firmware remain functional.
- [x] Web typecheck/build/tests and actual-page Playwright desktop/mobile checks.
- [x] Flutter focused/full tests, modified-file analysis, real-glyph screenshots
  at narrow/wide widths and APK build from final sources.
- [x] No deployment, flashing, release/version bump or automatic commit.

WHEN an online current summary arrives THEN independent BMS values populate the
approved surfaces. WHEN its deadline passes or the group is unknown/offline THEN
current values disappear without losing inspectable historical diagnostics.

## Final Verification

- Four Go modules: `go build ./...`, `go test ./...`, `go vet ./...` passed.
- Firmware CTest: 16/16 passed; final ESP-IDF image confirmed newer than sources.
- Isolated TimescaleDB: compressed-table migration/replay, durable BMS latest
  lookup, all 100 historical bytes, optional-column failure and legacy paging
  regression passed. Temporary container removed; production DB untouched.
- Web: 528 tests across 62 files passed. 43 BMS/legacy-contract tests rerun after
  contrast refinements passed. TypeScript, changed-file ESLint and Vite build
  passed; only existing large-chunk build warnings remain.
- Real-page Playwright: 320/390/1440/1920 widths, all BMS states, cell selection,
  chart pixels, independent BMS freshness and automatic expiration during a
  simulated 503 refresh failure passed. No unexpected browser errors. Small Web
  labels measured 5.17:1 contrast. Isolated actual-component review controls and
  English labels passed; review HTML is not included in `dist`.
- Flutter: 842 full-suite tests passed, 30 opt-in image cases skipped in normal
  regression. All 30 real-glyph image cases were separately executed; 60 targeted
  cases passed. Screenshots cover Chinese/English, 320/360/600 widths, 1.8x text,
  light/dark, cells, diagnostics, expired and alarm states.
- Flutter changed-file analysis: no issues. Full `flutter analyze --no-pub`
  reports 735 informational existing lint items, no errors or warnings, and exits
  nonzero because the baseline is not lint-clean. Unrelated lint left unchanged.
- Independent review P2 unknown-operation and dark-text-contrast findings fixed
  and rechecked; dark foreground contrast 8.32-9.96:1. No open review findings.
- Final local debug APK built successfully after the final full test run.

## Artifacts

Firmware: `D:/CS_INV_WIFI/esp32c3_l10_idf/build/cs_inv_l10_c3.bin`

SHA256: `0102b43c0007447b1a7344ee87da9b1a15deeb2bf8b5d3ea67c1fd61dd129908`

Debug APK: `inv_app/build/app/outputs/flutter-apk/app-debug.apk` (257909461 bytes)

SHA256: `933297fc1d893db8a227b0b5707578f9a667146f4d41b9a68072eee26a9f7bf5`

Web bundle: `inv-admin-frontend/dist/`. Local actual-component review:
`http://127.0.0.1:5177/bms-component-review.html` (simulated API only).

No production release signing, installation, UART/MQTT hardware end-to-end,
physical phone or long-run acceptance is claimed. Apply migration 126 before
services, then update firmware and clients; cloud monitoring only, not BLE direct.
