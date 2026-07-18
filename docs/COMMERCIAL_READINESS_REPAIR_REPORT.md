# Commercial Readiness Repair Report

This report summarizes the commercial-readiness repair work completed for this
repository. It is intended for release review, staging acceptance, and handoff
to operations, security, and mobile release owners.

## Outcome

The project is now suitable for staging and pilot acceptance testing. It is not
yet approved for direct commercial production release until the external
release checklist is complete.

The remaining blockers require operational, legal, or store-account actions:

- Rotate all credentials that have appeared in repository history.
- Provision and renew production TLS certificates.
- Add approved `LICENSE`, third-party NOTICE, and release SBOM artifacts.
- Configure Android signing secrets and iOS Apple Developer signing.
- Confirm Google Play policy handling for APK self-update permissions.
- Run real-device validation for local device provisioning and telemetry.

## Major Repairs

### Security and secrets

- Removed the tracked `deploy/.env` file.
- Replaced historic deployment credentials, private IPs, personal email values,
  and internal secrets with non-usable placeholders.
- Hardened internal service authentication and added tests.
- Kept production secrets in environment files or CI secrets, not committed
  source files.

### Backend and database

- Fixed device binding failures caused by `timezone` becoming `NULL` when a
  device was bound without a valid station row.
- Added migration `058_repair_device_timezone_trigger` and updated the baseline
  schema.
- Tightened gateway RBAC so bind/unbind exceptions do not grant broad device
  create/delete authority.
- Changed API health checks to return `503` when database or Redis dependencies
  are unhealthy.

### Deployment and CI

- Updated CI to use Go `1.26.5`.
- Added reachable Go vulnerability scanning in CI.
- Made CD deploy the same immutable SHA that passed CI.
- Restricted production gateway port `8080` to localhost so public traffic goes
  through nginx/TLS.
- Reworked the integration-test compose stack to be isolated, reproducible, and
  service-gated.
- Verified production compose configuration with a temporary example env file.

### Mobile release

- Removed debug-signing fallback for Android release builds.
- Added Android release workflow that requires signing secrets, builds a signed
  AAB, verifies signing, and uploads the artifact.
- Added `android/key.properties.example` for local signed release builds.
- Replaced sample bundle identifiers with `com.csinv.app` values.
- Disabled verbose Dio request/response logging in release mode.
- Scoped legacy Android storage permissions with `maxSdkVersion`.

### Frontend

- Confirmed production frontend dependencies with `npm audit --omit=dev`.
- Verified frontend tests and production build checks.

## Verification Performed

- Go unit tests passed for:
  - `inv_api_server`
  - `api-gateway`
  - `inv_device_server`
  - `mqtt-kafka-bridge`
- Full integration tests passed with `TEST_REQUIRE_SERVICES=true`.
- API Docker image build passed.
- New API image was recreated in the test compose environment and key E2E flows
  passed.
- Frontend tests passed: 193 tests.
- Frontend `npm run build:check` passed.
- Flutter tests passed: 175 passed, 4 skipped.
- Flutter analyze passed with `--no-fatal-infos`; existing info-level style debt
  remains visible.
- Android release APK build passed with HTTPS API base URL.
- Secret/IP/email placeholder scan passed for the targeted historic values.
- `git diff --check` passed.

## Known Residual Risk

- Some deployment helper scripts are legacy operational scripts. They are
  sanitized, but the supported path should be CI/CD plus documented production
  compose.
- MQTT integration still includes one weak end-to-end persistence assertion. It
  proves broker publish/subscribe and service availability, but production
  acceptance should include real device-server telemetry persistence.
- Flutter dependency and lint debt remains. It does not block compilation today,
  but should be reduced before a long-lived commercial branch.
- Store release still depends on external signing assets and developer accounts.

## Release Gate

Before production release, complete
`docs/COMMERCIAL_RELEASE_CHECKLIST.md` and attach the checklist to the release
candidate. A green CI run alone is not enough for commercial approval.
