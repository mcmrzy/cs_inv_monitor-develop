# App OTA Device Scope Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make App OTA authorization honor system-admin and organization-subtree device management without adding a Flutter ownership check.

**Architecture:** Keep authorization on the Go backend and replace OTA's direct-ownership predicate with one management-scope query. Reuse `v_user_hierarchy` and explicit device sharing, then route every device-scoped App OTA handler through one common guard. Per the approved product rule, hierarchical device visibility is management authority; Flutter does not reconstruct ownership or add a second authorization decision.

**Tech Stack:** Go, pgx/PostgreSQL, existing integration-test database harness, Flutter client unchanged

---

## Chunk 1: Regression and minimal backend fix

### Task 1: Define the OTA management-scope regression

**Files:**
- Create: `business-api/internal/repository/ota_device_access_postgres_integration_test.go`
- Reference: `business-api/internal/repository/command_lifecycle_postgres_integration_test.go`
- Reference: `database/schema.sql`

- [ ] **Step 1: Write a failing PostgreSQL integration test**

Seed a complete manufacturer → agent → distributor → installer → customer organization chain, their memberships, a system administrator, an unrelated user, and devices owned by the customer. Let the existing organization triggers generate closure rows; do not insert protected closure rows directly. Assert that `CheckDeviceOwnership` allows the system administrator, agent across all lower levels, distributor, installer, direct owner, and explicit share while denying the unrelated user and a deleted device.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
cd business-api && go test -tags=integration ./internal/repository -run TestCheckDeviceOwnershipUsesManagementScope -count=1 -v
```

Expected: the system-administrator and ancestor-manager cases fail under the direct-ownership implementation.

### Task 2: Replace direct ownership with management scope

**Files:**
- Modify: `business-api/internal/repository/ota_repository.go`
- Test: `business-api/internal/repository/ota_device_access_postgres_integration_test.go`

- [ ] **Step 1: Implement one fail-closed `SELECT EXISTS` predicate**

The predicate must require a non-deleted device and allow access when the actor is an active system administrator, appears as an ancestor of the device owner in `v_user_hierarchy`, or has an explicit `user_device_rel` entry.

- [ ] **Step 2: Run the focused test and confirm GREEN**

Run the focused integration command above. Expected: all scope cases pass.

### Task 3: Apply one guard to every device-scoped App OTA route

**Files:**
- Modify: `business-api/internal/handler/ota_handler.go`
- Create or modify: `business-api/internal/handler/ota_device_scope_test.go`

- [ ] **Step 1: Write failing handler/source-contract tests**

Prove an endpoint that currently lacks the check (for example per-device history) is guarded before service work, and assert the named device-scoped handlers route through the common helper.

- [ ] **Step 2: Run the focused tests and confirm RED**

```bash
cd business-api && go test ./internal/handler -run 'TestOTADeviceScope' -count=1 -v
```

Expected: failure because the common guard does not exist or is not used by all covered handlers.

- [ ] **Step 3: Implement the common handler guard**

The helper reads the authenticated user, calls the management-scope repository boundary, emits the existing 500/403 response on failure, and returns whether the handler may continue. Use it in check-update, trigger, resend, status, per-device history, local-result reporting, package install, package-progress, device package list, and available-package list. Keep the trigger service's repository check as defense in depth. Leave the separately `ota:control`-gated rollback routes unchanged.

- [ ] **Step 4: Run the focused test and confirm GREEN**

Run the handler command above. Expected: all focused tests pass.

- [ ] **Step 5: Format and run final scoped regressions**

```bash
gofmt -w business-api/internal/repository/ota_repository.go business-api/internal/repository/ota_device_access_postgres_integration_test.go business-api/internal/handler/ota_handler.go business-api/internal/handler/ota_device_scope_test.go
cd business-api && go test ./internal/repository ./internal/service ./internal/handler
cd business-api && go vet ./internal/repository ./internal/service ./internal/handler
```

Expected: exit code 0 for every available check. If the integration database is unavailable, report the integration test as unexecuted rather than passed.

- [ ] **Step 6: Review the scoped diff**

Confirm the Flutter App is unchanged, no migration was added, and unrelated worktree changes were preserved. Do not commit unless the user explicitly requests it.
