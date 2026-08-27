# Web 注册与验证码登录流程 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让未注册手机号在登录发码阶段立即被拦截，并让 Web 注册成功后直接进入系统。

**Architecture:** 后端在现有 `/auth/send-code` 入口基于手机号注册状态阻断登录发码；前端复用现有 `authStore.login`、用户映射和 dashboard 路由消费注册接口已返回的登录响应。无需新增 API、数据库表或 token 机制。

**Tech Stack:** Go + Gin + Redis-backed SMS service；React + TypeScript + Ant Design + Zustand + Vitest/MSW。

---

## Chunk 1: Regression tests

### Task 1: Add Web behavior tests

**Files:**
- Modify: `inv-admin-frontend/src/pages/login/LoginPage.test.tsx`

- [ ] **Step 1: Make the captcha test double complete successfully**

Expose a deterministic test-only captcha action so the send-code test can pass the existing slider gate without depending on the visual component.

- [ ] **Step 2: Write the failing unregistered-phone test**

Mock `/api/v1/auth/send-code` with business code `4001`, enter an unregistered phone in code-login mode, complete the captcha, click “发送验证码”, and assert the localized phone-not-registered message is shown.

- [ ] **Step 3: Write the failing phone-registration auto-login test**

Mock `/api/v1/auth/register` with a successful `LoginResponse`, submit the registration form, and assert `useAuthStore` becomes authenticated and the dashboard navigation is requested.

- [ ] **Step 4: Run the focused tests and confirm RED**

Run: `cd inv-admin-frontend && npx vitest run src/pages/login/LoginPage.test.tsx`

Expected: the new tests fail because the current frontend either waits for manual login or does not provide the unregistered-phone behavior.

## Chunk 2: Implement root-cause fixes

### Task 2: Block login-code delivery for unknown phone numbers

**Files:**
- Modify: `business-api/internal/handler/auth_handler.go:467-482`

- [ ] **Step 1: Add the login registration-state branch**

After the existing phone lookup and before `smsService.SendCode`, return business code `4001` when `req.Type == "login"` and `existingUser == nil`. Keep registration and password-reset branches unchanged.

- [ ] **Step 2: Run relevant Go handler tests**

Run: `cd business-api && go test ./internal/handler/...`

Expected: PASS.

### Task 3: Consume registration login responses in Web

**Files:**
- Modify: `inv-admin-frontend/src/pages/login/index.tsx:70-90,270-299`

- [ ] **Step 1: Add localized phone-not-registered text**

Add Chinese and English strings and use them for business code `4001` returned by phone login-code delivery.

- [ ] **Step 2: Add a shared registration-response login helper**

Parse `data`/top-level response compatibility, validate `data.user`, call `login(...)` with snake_case/camelCase token variants and mapped user, show success, then navigate to `/dashboard` with replacement history.

- [ ] **Step 3: Use the helper for phone and email registration**

Replace the current “success then setActiveTab('login')” behavior. Keep error handling and loading cleanup unchanged.

- [ ] **Step 4: Make the phone-code send path use the explicit text**

When login SMS send returns business code `4001`, show the phone-not-registered message and do not start the countdown.

- [ ] **Step 5: Run the focused tests and confirm GREEN**

Run: `cd inv-admin-frontend && npx vitest run src/pages/login/LoginPage.test.tsx`

Expected: all LoginPage tests pass, including the new regression tests.

## Chunk 3: Verification and review

### Task 4: Verify behavior and regression surface

- [ ] **Step 1: Run Web type-check and build**

Run: `cd inv-admin-frontend && npm run build:check`

- [ ] **Step 2: Run backend build and tests**

Run: `make build-api && make test-go`

- [ ] **Step 3: Review the final diff**

Run: `git diff --check && git diff -- business-api/internal/handler/auth_handler.go inv-admin-frontend/src/pages/login/index.tsx inv-admin-frontend/src/pages/login/LoginPage.test.tsx`

Confirm only the requested auth flow and its tests/docs changed; no schema, secret, dump, or generated files are included.
