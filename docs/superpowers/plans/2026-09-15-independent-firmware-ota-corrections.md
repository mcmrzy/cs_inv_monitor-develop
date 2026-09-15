# Independent Firmware OTA Corrections Implementation Plan

> **For agentic workers:** REQUIRED: Use test-driven development and preserve unrelated worktree changes. Do not commit or push unless the user explicitly asks.

**Goal:** Make device firmware upgrades fully module-independent across the Go API, Flutter App, and React Web UI while retiring all package/main-version write behavior and enforcing device-scoped permissions.

**Architecture:** The backend is the source of truth for authorization, module eligibility, serial task dispatch, rollback resolution, and scoped history. Flutter and Web consume the same independent-firmware resources and task APIs; internal chip identifiers remain transport-only and are never rendered to customers.

**Tech Stack:** Go/Gin/PostgreSQL, Flutter/Dart, React/TypeScript/Vite/Vitest

**Design basis:** The approved device-first OTA specifications in `docs/superpowers/specs/2026-09-10-device-firmware-upgrade-ui-design.md` plus the confirmed review findings from 2026-09-15.

---

## Multi-Session Plan

**Scope:** Fix all confirmed backend, Flutter, and Web OTA correctness, authorization, compatibility, and presentation regressions.

**Out of Scope:** Firmware binary/protocol changes, production deployment, hardware validation, and unrelated About-page image work.

**Shared Constraints:** No customer-facing ESP/ARM/DSP/BMS labels; no new upgrade packages or `main_version` writes; preserve historical package records read-only; use `devices:view` and `devices:control` with real data scope; one active module upgrade per device; ESP remains last in multi-module ordering.

| session_id | role | runtime_agent | goal | depends_on | owned_paths | done_signal |
|---|---|---|---|---|---|---|
| S-BE | implementer | ecc-implementer | Correct backend contracts, persistence, authorization, task lifecycle, and retirement behavior | none | `business-api/**`, `database/migrations/**` | regression tests and targeted Go tests pass |
| S-APP | implementer | ecc-implementer | Correct App navigation, rollback, history, eligibility, local OTA and visible terminology | none | `inv_app/**` | OTA Flutter tests pass |
| S-WEB | implementer | ecc-implementer | Correct Web response shapes, device permissions, history access, deep links and visible terminology | none | `inv-admin-frontend/**` | targeted Vitest and build check pass |
| S-MERGE | reviewer/verifier | ecc-reviewer/ecc-verifier | Review integrated behavior and run repository gates | S-BE,S-APP,S-WEB | none | no open blocking finding and verification evidence recorded |

## Chunk 1: Backend source of truth

### Task 1: Correct independent dispatch and serial lifecycle

**Files:** `business-api/internal/service/ota_independent_service.go`, `business-api/internal/service/ota_service.go`, relevant repository/model files and tests.

- [ ] Add failing tests proving the dispatched URL includes the firmware file path.
- [ ] Add failing tests proving a successful terminal module dispatches exactly the next pending module and failure stops or deterministically advances according to the approved serial policy.
- [ ] Make ordering deterministic and preserve ESP-last.
- [ ] Prevent resend from sending multiple pending modules concurrently.
- [ ] Reject offline, unreported/ineligible, duplicate-active module requests for ordinary users.

### Task 2: Enforce authorization and scoped history

**Files:** `business-api/cmd/main.go`, OTA handlers/services/repositories, authorization helpers and tests.

- [ ] Add failing handler/service tests for `devices:view`, `devices:control`, and restricted `data_scope`.
- [ ] Make device overview/resources/history require view scope and trigger/rollback/local result require control scope.
- [ ] Return aggregate history for every device visible through the caller's effective data scope.
- [ ] Preserve system-admin override only where explicitly approved and require a force reason for unknown current versions.

### Task 3: Retire package/main-version writes safely

**Files:** OTA upload/package/task/local-result handlers, services, repositories, migration 118 follow-up migration if required, and tests.

- [ ] Add failing tests proving firmware upload creates no package and no new `main_version`.
- [ ] Retire every remaining package write/rollback endpoint with real HTTP 410 plus stable `legacy_package_retired` code.
- [ ] Stop in-flight legacy packages after the current module and preserve their history.
- [ ] Remove new `devices.main_version` writes, including local OTA reporting.
- [ ] Remove or adapt obsolete UPSERT conflict targets so migrated databases cannot return 500.
- [ ] Make OTA history immutable from public/admin delete endpoints.
- [ ] Make idempotency unique per user/device/key, return the original task group for identical concurrent requests, and return 409 for changed operation or payload.

## Chunk 2: Flutter customer flow

### Task 4: Keep all customer paths on independent module OTA

**Files:** `inv_app/lib/features/ota/**`, router/localization files, and OTA tests.

- [ ] Add failing navigation tests proving every upgrade CTA opens the independent device/module flow.
- [ ] Remove customer reachability of package/main-version UI while retaining required local firmware behavior.
- [ ] Add a rollback target ID contract; never reuse the completed upgrade's firmware ID as the old target.
- [ ] Make aggregate history work for ordinary users.
- [ ] Gate module upgrade/local upgrade using backend eligibility and channel support.
- [ ] Ensure recovered local module versions are reported to the cloud.
- [ ] Add visible-copy guards so customer OTA surfaces never render internal chip abbreviations.

## Chunk 3: React Web customer flow

### Task 5: Align response, permission, history, routing, and terminology contracts

**Files:** `inv-admin-frontend/src/pages/ota/**`, `src/pages/devices/**`, `src/services/otaApi.ts`, router/access/locales/tests.

- [ ] Add a failing service test using the backend's real firmware-resource array envelope.
- [ ] Use `devices:view` for the customer device tab and `devices:control` for upgrade/rollback.
- [ ] Put scoped aggregate history inside the ordinary-user-visible device firmware area.
- [ ] Preserve `tab=tasks` in batch-OTA deep links.
- [ ] Hide package/main-version columns and labels from active UI while retaining read-only historical compatibility.
- [ ] Replace every direct or fallback chip label with functional names or the generic “设备组件”.

## Merge Review and Verification Gate

- [ ] Confirm no worker changed files outside its owned paths.
- [ ] Confirm backend response shapes match Flutter and Web parsing.
- [ ] Search active user-facing code for raw ESP/ARM/DSP/BMS labels and package/main-version actions.
- [ ] Run Go build/tests/vet for the affected service.
- [ ] Run Flutter analyze and OTA tests.
- [ ] Run Web build check, lint, and OTA/router/service tests.
- [ ] Review the scoped diff for obsolete writes, destructive history operations, and authorization bypasses.

