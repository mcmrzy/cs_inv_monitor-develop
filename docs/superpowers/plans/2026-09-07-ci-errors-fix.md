# CI Errors Fix Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the frontend coverage and API documentation GitHub Actions jobs complete successfully with valid generated artifacts.

**Architecture:** Keep the repair inside the existing GitHub Actions and documentation pipeline. Correct CLI option namespaces and package selection at their source, repair the invalid OpenAPI schemas, and keep local documentation tooling aligned with CI.

**Tech Stack:** GitHub Actions YAML, Vitest 4 coverage, OpenAPI 3, Redocly CLI, openapi-to-postmanv2, PowerShell.

---

## Chunk 1: Workflow blockers

### Task 1: Correct Vitest coverage reporters

**Files:**
- Modify: `.github/workflows/ci.yml`

- [x] Replace `--reporter=text --reporter=json-summary` with `--coverage.reporter=text --coverage.reporter=json-summary`.
- [x] Verify Node 24 is active and run `npm ci` in an isolated clean copy of `inv-admin-frontend`.
- [x] Run `npm run test:coverage -- --coverage.reporter=text --coverage.reporter=json-summary` from `inv-admin-frontend`.
- [x] Require 36 test files and 311 tests to pass and `coverage/coverage-summary.json` to exist.

### Task 2: Repair Postman collection generation

**Files:**
- Modify: `.github/workflows/api-docs-validation.yml`

- [x] Replace `npm install -g openapi-to-postman` with `npm install -g openapi-to-postmanv2@6.3.3`.
- [x] Add `mkdir -p docs/postman` before invoking `openapi2postmanv2`.
- [x] Generate a collection in an isolated temporary copy and require a non-empty JSON artifact.

## Chunk 2: OpenAPI correctness and local parity

### Task 3: Fix invalid response schemas

**Files:**
- Modify: `docs/openapi.yaml`
- Modify: `.github/workflows/api-docs-validation.yml`

- [x] Move each `message` property in `RemoveMemberResponse`, `ActivateResponse`, and `DeactivateResponse` to the same indentation level as `success` and `data`.
- [x] Remove `continue-on-error: true` and its stale advisory comment from bundled-spec validation.
- [x] Bundle and lint the specification; require no Redocly errors.

### Task 4: Synchronize local documentation tooling

**Files:**
- Modify: `docs/validate-api-docs.ps1`
- Modify: `docs/README-API-DOCS.md`

- [x] Use `openapi-to-postmanv2@6.3.3` in the PowerShell install/check flow and README command.
- [x] Add `mkdir -p docs/postman` to the README command sequence for clean checkouts.
- [x] Keep the existing `openapi2postmanv2` executable and output directory behavior.

### Task 5: Review and hand off

**Files:**
- Review only: all files listed above

- [x] Inspect a path-scoped `git diff --ignore-cr-at-eol` and confirm no unrelated files changed.
- [x] Report commands, exit codes, remaining warnings, and the fact that GitHub CI requires a later push/rerun for remote proof.
- [x] Do not stage, commit, or push unless the user asks.
