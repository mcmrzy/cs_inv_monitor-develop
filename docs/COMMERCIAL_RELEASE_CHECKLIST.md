# Commercial Release Checklist

This project must not be promoted to a commercial production release only
because CI is green. Complete the checks below for each release candidate.

## Security and secrets

- Rotate every credential that has ever appeared in the repository history:
  database passwords, Redis passwords, JWT secrets, internal service keys, MQTT
  credentials, email credentials, JPush credentials, SSH passwords, Jenkins
  passwords, and signing keys.
- Keep production secrets out of Git. Use GitHub Actions secrets, a cloud secret
  manager, or the production host's protected environment files.
- Confirm `deploy/.env` and `deploy/.env.prod` are absent from commits.
- Run `govulncheck ./...` for every Go module with Go 1.26.5 or newer.
- Run `npm audit --omit=dev` for the admin frontend.

## Backend and deployment

- Build container images from immutable Git SHAs, not floating local state.
- Pin production base images to explicit versions or digests before customer
  delivery.
- Verify `docker compose -f deploy/docker-compose.prod.yml --env-file
  deploy/.env.prod config --quiet` on the release host.
- Confirm nginx terminates TLS and the API gateway is not publicly exposed over
  plain HTTP.
- Provision certificates before first nginx start and automate renewal.
- Back up PostgreSQL before applying migrations in production.
- Keep the previous `IMAGE_TAG` available for rollback.

## Android release

- Use `.github/workflows/release-android.yml` for commercial Android builds.
- Store the release keystore only in a secure secret store. The workflow expects
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  and `ANDROID_KEY_PASSWORD`.
- Release to Google Play as a signed `.aab`, not an unsigned APK.
- For Google Play distribution, remove or justify `REQUEST_INSTALL_PACKAGES`.
  APK self-update is suitable for controlled enterprise distribution, but it is
  a Play policy risk.
- Verify Git LFS assets are materialized with `git lfs pull` before building.
- Increment `version` in `inv_app/pubspec.yaml` for every store submission.

## iOS release

- Set the Apple `DEVELOPMENT_TEAM` and provisioning profile in Xcode or CI.
- Confirm the bundle identifier is registered in Apple Developer.
- Archive on macOS and upload through TestFlight before production App Store
  release.
- Verify ATS/local-network behavior on real devices if local inverter setup
  still requires HTTP to a device IP.

## Legal and compliance

- Add the project `LICENSE` approved for commercial distribution.
- Produce an SBOM for every release candidate and archive it with the build.
- Review third-party licenses, including frontend map dependencies, with legal.
- Keep a customer-facing NOTICE/third-party attribution file when required.

## Acceptance testing

- Run Go unit tests for all modules.
- Run frontend tests and `npm run build:check`.
- Run Flutter analyze and tests.
- Run integration tests with `TEST_REQUIRE_SERVICES=true`.
- Test MQTT telemetry persistence with a real or production-equivalent device
  service, not just broker publish/subscribe.
- Perform staging smoke tests against the same domain, TLS, and image tag that
  will be promoted.
