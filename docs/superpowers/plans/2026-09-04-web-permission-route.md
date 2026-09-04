# Web Permission Route Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent authenticated users from directly rendering Web pages for which they lack the declared permission.

**Architecture:** Keep `ProtectedRoute` as the authentication boundary, add a focused `PermissionRoute` inside it, and centralize ordinary route permissions plus default-route candidates in `routeAccess.ts`. Add a three-state organization access hook and `OrganizationRoute` for `/organizations`. Export a testable `AppRoutes`, make `MainLayout` always render its outlet, and derive ordinary menu visibility from the same route permission map.

**Tech Stack:** React 18, TypeScript, React Router 7, Zustand, Vitest, Testing Library.

---

## Chunk 1: Permission component

### Task 1: Define authorization behavior with tests

**Files:**
- Create: `inv-admin-frontend/src/components/PermissionRoute.test.tsx`
- Create: `inv-admin-frontend/src/components/PermissionRoute.tsx`
- Create: `inv-admin-frontend/src/router/routeAccess.test.ts`
- Create: `inv-admin-frontend/src/router/routeAccess.ts`

- [x] **Step 1: Write failing component tests**

Cover a normal user with one matching permission, a normal user without a match, an empty permission list, and a system administrator without explicit permissions. Render the component inside `MemoryRouter` routes so redirects are asserted through visible unauthorized content.

Add table-driven tests for every approved route mapping and tests proving root selection sends an alerts-only user to `/alerts`, a work-orders-only user to `/work-orders`, a system administrator to `/dashboard`, and a user with no ordinary permissions to `/organizations` for the organization guard's final decision.

- [x] **Step 2: Run the focused test and verify RED**

Run: `npm run test:run -- src/components/PermissionRoute.test.tsx src/router/routeAccess.test.ts`

Expected: test compilation fails because `PermissionRoute` does not exist. If Vitest cannot start because the Rolldown native binding is absent, repair dependencies without deleting user files, then rerun; otherwise record the environment limitation as Partial.

- [x] **Step 3: Implement the minimal component**

Implement the route mapping/default candidate helper, then implement a component with `children` and `permissions` props. Read `user` and `hasAnyPermission` from `authStore`; render children for a system administrator or any permission match, otherwise return `<Navigate to="/unauthorized" replace />`.

- [x] **Step 4: Run the focused test and verify GREEN**

Run: `npm run test:run -- src/components/PermissionRoute.test.tsx src/router/routeAccess.test.ts`

Expected: all four authorization cases pass.

## Chunk 2: Organization access and route integration

### Task 2: Replace the racy organization redirect with an explicit guard

**Files:**
- Create: `inv-admin-frontend/src/hooks/useOrganizationAccess.test.tsx`
- Create: `inv-admin-frontend/src/hooks/useOrganizationAccess.ts`
- Create: `inv-admin-frontend/src/components/OrganizationRoute.test.tsx`
- Create: `inv-admin-frontend/src/components/OrganizationRoute.tsx`

- [x] **Step 1: Write failing organization access tests**

Cover system administrator bypass, query loading without redirect or child mount, a non-customer organization member being allowed, and pure customer/no organization/no role/query failure being denied. Prove the component renders a loading state before the query settles.

- [x] **Step 2: Run the focused organization tests and verify RED**

Run: `npm run test:run -- src/hooks/useOrganizationAccess.test.tsx src/components/OrganizationRoute.test.tsx`

Expected: compilation fails because the hook and guard do not exist, subject to the documented Rolldown environment limitation.

- [x] **Step 3: Implement the minimal shared hook and guard**

Normalize the API's null/single-object/array response, classify organization roles once, and return `loading | allowed | denied`. Render a centered spinner while loading, children only when allowed, and a replace navigation to `/unauthorized` when denied.

- [x] **Step 4: Run the focused organization tests and verify GREEN**

Run the same two test files and require all cases to pass.

### Task 3: Apply permissions to the real route tree

**Files:**
- Modify: `inv-admin-frontend/src/App.tsx`
- Modify: `inv-admin-frontend/src/layouts/MainLayout.tsx`
- Create: `inv-admin-frontend/src/App.test.tsx`
- Create: `inv-admin-frontend/src/layouts/MainLayout.permission.test.tsx`

- [x] **Step 1: Add failing real-route integration tests**

Render the exported `AppRoutes` with a memory history and assert `/users`, `/big-screen`, `/devices/:sn/detail`, `/organizations`, and legacy `/admin` behavior. Verify an unauthenticated request reaches `/login` before permission evaluation. In a real `MainLayout` route setup, prove an empty-menu user directly visiting `/users` still reaches `/unauthorized`, and a user whose only permission is a formerly omitted menu entry such as `models:view` can render the outlet and see its menu entry.

- [x] **Step 2: Wrap protected business route elements**

Export `AppRoutes`, use `routeAccess.ts` in it, and apply the permission mapping from the approved design. Change `RoleRedirect` to select the first permitted ordinary candidate and fall back to `/organizations`. Wrap `/organizations` in `OrganizationRoute`; keep `/admin` as a redirect into that guarded route.

- [x] **Step 3: Align menu permissions with backend permissions**

Replace the split admin/user menu white lists with one ordinary menu definition whose permissions come from `routeAccess.ts`. This makes `models:view`, `ota:view`, `parallel:view`, `users:view`, and system-page grants visible regardless of a separate role heuristic. Keep the organization entry separately filtered by `useOrganizationAccess`, and keep firmware operation buttons on their more specific create/control/delete permissions.

- [x] **Step 4: Always mount the route outlet**

Remove the organization redirect effect and the `routeConfig.routes.length` condition that replaces `<Outlet />` with `<Empty />`. Always render the outlet so route guards execute even when the menu is empty; unauthorized and organization guards own the resulting state.

- [x] **Step 5: Run the route integration tests and check redirects**

Run: `npm run test:run -- src/App.test.tsx src/layouts/MainLayout.permission.test.tsx`

Confirm `/unauthorized` remains public, `/admin` still redirects to the guarded `/organizations`, and no unauthorized redirect can loop back into a protected page.

### Task 4: Remove stale interface notes

**Files:**
- Modify: `inv-admin-frontend/src/services/userApi.ts`

- [x] **Step 1: Remove the obsolete comments**

Delete the two comments claiming `POST /users` and `DELETE /users/:id` are not implemented. Do not change request paths or payload behavior.

## Chunk 3: Verification

### Task 5: Run focused and project-level checks

**Files:**
- Verify only; no planned production changes.

- [ ] **Step 1: Run focused tests** *(blocked by missing `@rolldown/binding-linux-x64-gnu` native dependency)*

Run: `npm run test:run -- src/components/PermissionRoute.test.tsx src/router/routeAccess.test.ts src/hooks/useOrganizationAccess.test.tsx src/components/OrganizationRoute.test.tsx src/App.test.tsx src/layouts/MainLayout.permission.test.tsx src/components/ProtectedRoute.test.tsx`

- [x] **Step 2: Run TypeScript compilation**

Run: `npx tsc -b --pretty false`

Expected: exit code 0.

- [x] **Step 3: Run scoped lint**

Run: `npx eslint src/components/PermissionRoute.tsx src/components/PermissionRoute.test.tsx src/components/OrganizationRoute.tsx src/components/OrganizationRoute.test.tsx src/hooks/useOrganizationAccess.ts src/hooks/useOrganizationAccess.test.tsx src/router/routeAccess.ts src/router/routeAccess.test.ts src/App.tsx src/App.test.tsx src/layouts/MainLayout.tsx src/layouts/MainLayout.permission.test.tsx src/services/userApi.ts`

Expected: no errors and no newly introduced warnings.

- [x] **Step 4: Inspect the scoped diff**

Confirm only the design, plan, permission component/tests, route wrappers, and stale comments changed. Do not stage or commit without an explicit user request.
