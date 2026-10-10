# App Device Entry and BMS Navigation

## Approved Scope

User approved the following structure on 2026-10-09:

- Add Device: `Add new device` contains scan and manual SN/PIN entry. `Select device` contains nearby discovery and authenticated owned-device selection.
- Preserve the selected station throughout both flows. Existing cloud-owned devices are associated with a station, not rebound or reassigned to a different owner.
- BMS remains a child of its inverter. Station energy flow opens the matching storage page; multiple battery sources require a chooser.
- Storage uses Overview, Cells and Diagnostics. History stays cloud-only and preserves the station/device timezone.
- Station long-press actions use equally sized, flat, differently colored icons with aligned text.

## Bug Boundaries

- Nearby PIN connection: compare actual current firmware INFO/AUTH contract with App binding. Server PIN and ownership validation remain mandatory. Do not treat a local `bound` flag as proof of cloud ownership.
- WiFi scanning: scanning does not require association. Route selection must not wait indefinitely for a future WiFi network or later rebind after cancellation. Scanning, cancellation and mode-switch state must be bounded and reset.
- Saved system WiFi passwords are not available to an ordinary App. No privileged extraction or plaintext credential storage is introduced. User-approved App credential retention and WiFi sharing QR are separate future features.

## Existing Batch, Not New Scope

Realtime payload normalization, paginated history, lifetime energy fallback, hierarchical overview authorization, richer device cards, debug interruption recovery, remote firmware selection and independent OTA phase percentages are already in the previous monitoring batch. See `2026-10-09-monitoring-recovery-verification.md`.

The device reports `energy.total_pv`; the server must retain historical-counter/daily-energy fallback, not add repeated absolute counters. A correct production counter for SN H1ZZX0013900002H still needs authenticated verification after deployment.

## Acceptance

- Focused regression tests reproduce the protocol and unassociated WiFi failure paths.
- Owned-device selection tests verify station association, failures, paging and ownership filtering.
- BMS navigation tests cover absent/one/multiple battery sources and timezone propagation.
- Station sheet and BMS widgets fit 320px and large-font layouts; inspect actual widget screenshots.
- Run complete Flutter analysis and tests, then build an Android APK.
- Physical-phone PIN, permissions, WiFi association and production telemetry remain distinct acceptance gates. Local tests/build do not establish hardware or deployment success.

## CI/CD Continuation

Main CI for `8bdb021a8` passed. CD run `37909623792` is tracked separately.
Documentation deployment was blocked by Pages not being enabled and a broken publish tree. Pages workflow mode was enabled for the public repository; `d0517aff8` repairs relative redirects, colocates Swagger/OpenAPI and replaces placeholder SRI with verified hashes.
Latest runs: CI `37910590616`, documentation `37910590651`. Do not mark queued, running or skipped deployment as successful.
