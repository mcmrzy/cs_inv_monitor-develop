# CD Rollback Recovery Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the production ingress recoverable when a backend readiness check fails and make CD rollback restore both configuration and images.

**Architecture:** Separate container liveness from external MQTT readiness, remove strict healthy gating from the public ingress chain, and make the SSH deployment preserve and restore the previous server-side deploy bundle. Add a static regression guard that validates all of these properties together.

**Tech Stack:** GitHub Actions YAML, Docker Compose, Bash, Docker Desktop.

---

## Chunk 1: Regression guard and deployment repair

### Task 1: Add failing CD recovery assertions

**Files:**
- Modify: `deploy/validate-production-compose.sh`

- [x] Add assertions for the device liveness probe, non-blocking ingress dependencies, server-side configuration backup/restore, and failure diagnostics.
- [x] Run `bash deploy/validate-production-compose.sh` and require it to fail on the current workflow/Compose files.

### Task 2: Separate liveness from readiness

**Files:**
- Modify: `deploy/docker-compose.prod.yml`
- Modify: `deploy/nginx-proxy.conf`

- [x] Change the device container probe from `/health` to `/metrics`.
- [x] Add a local-only Nginx `/livez` endpoint and use it for the container liveness probe.
- [x] Remove API gateway backend startup dependencies and keep frontend/Nginx dependencies non-blocking so ingress can boot independently.
- [x] Re-run the regression guard and confirm only workflow recovery assertions still fail.

### Task 3: Make rollback configuration-aware and diagnostic

**Files:**
- Modify: `.github/workflows/cd.yml`

- [x] Stage and validate the candidate bundle, preserve the current deployment bundle, then update bind-mount sources in place and restore them if synchronization fails.
- [x] Add a reusable failure diagnostic function with Compose status, Health state, and bounded logs.
- [x] Route unexpected deployment errors and health failures through one rollback function that restores the previous bundle and image tag, then validates and reloads Nginx.
- [x] Report MQTT readiness separately without blocking public ingress recovery.
- [x] Serialize production deployments with a non-cancelling concurrency group.
- [x] Re-run the regression guard and require success.

## Chunk 2: Verification and release

### Task 4: Validate the production configuration

**Files:**
- Test: `.github/workflows/cd.yml`
- Test: `deploy/docker-compose.prod.yml`
- Test: `deploy/validate-production-compose.sh`

- [x] Run Bash syntax validation and the production topology/recovery guard.
- [x] Parse the workflow and Compose YAML files.
- [x] Render the production Compose file with the existing local non-secret environment file using Docker Compose.
- [x] Review a path-scoped diff and confirm unrelated worktree changes are excluded.

### Task 5: Release and observe

**Files:**
- Commit only the six scoped implementation/design files.

- [ ] Commit and push the fix to `develop`.
- [ ] Wait for develop CI and API documentation validation.
- [ ] Merge the verified develop commit to `main` and push.
- [ ] Wait for main CI and CD, then probe the real production domains.
