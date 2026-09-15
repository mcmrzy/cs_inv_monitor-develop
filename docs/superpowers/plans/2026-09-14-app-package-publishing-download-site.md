# App Package Publishing and Download Site Implementation Plan

> **For agentic workers:** Follow TDD and preserve unrelated worktree changes. Do not commit or push unless the user explicitly asks.

**Goal:** Complete and production-verify automatic APK/firmware metadata publishing and the public App download page.

**Architecture:** Reuse the committed backend parser, upload endpoints, storage volume, React page, and restricted download-domain Nginx virtual host. Close the remaining stale-metadata cache bug, validate all involved modules, then deploy only the affected services and configuration.

**Tech Stack:** Go/Gin/PostgreSQL, React/TypeScript/Ant Design, Nginx, Docker Compose.

---

### Task 1: Audit the committed publishing flow

**Files:**
- Inspect: `business-api/pkg/apkmeta/`
- Inspect: `business-api/internal/handler/ota_handler.go`
- Inspect: `database/migrations/113_add_app_version_apk_metadata.up.sql`
- Inspect: `inv-admin-frontend/src/pages/ota/index.tsx`

- [ ] Confirm APK metadata, hashing, storage, response, and cleanup behavior.
- [ ] Confirm firmware size/SHA-256 and version detection behavior.
- [ ] Run focused backend and admin tests.

### Task 2: Prevent stale download metadata

**Files:**
- Modify: `inv-admin-frontend/src/pages/download/DownloadPage.test.tsx`
- Modify: `inv-admin-frontend/src/pages/download/index.tsx`

- [ ] Add a failing test where the same-origin ESA alias returns an older version than the canonical API.
- [ ] Make the canonical API the primary source and preserve the alias as fallback.
- [ ] Run focused tests and type-check.

### Task 3: Validate the download-domain topology

**Files:**
- Verify: `deploy/nginx-proxy.conf`
- Verify: `deploy/docker-compose.prod.yml`
- Verify: `deploy/.env.prod.example`

- [ ] Confirm `/` redirects to `/download` and `/firmware/` remains a binary route.
- [ ] Confirm `DOWNLOAD_URL` and `APP_DOWNLOAD_URL` have separate responsibilities.
- [ ] Run production Compose validation.

### Task 4: Full verification and production delivery

- [ ] Run Go test, vet, and build checks.
- [ ] Run web tests, type-check, and production build.
- [ ] Back up production configuration before any change.
- [ ] Deploy only the affected API, gateway, web, and Nginx surfaces when their artifacts differ.
- [ ] Verify container health, latest-release metadata, download-page rendering, APK URL, `Content-Length`, SHA-256 metadata, and Range behavior.
- [ ] Report any physical-device or CDN-cache limitation explicitly.
