# Monitoring And App Recovery Status

Status as of 2026-10-10. Implementation, local verification, deployment and hardware acceptance are separate claims.

## User Checklist

| Request | Implementation | Remaining acceptance |
| --- | --- | --- |
| ARM CMD08 BMS upload/storage/display | Firmware, API, Web and App support added | Real connected BMS end-to-end verification |
| Remote App realtime/history zero | Nested/flat telemetry normalization, null-vs-zero, stale response protection | Authenticated SN H1ZZX0013900002H comparison with Web |
| App history | Raw/hourly paging and timezone-aware charts; remembered grouped fields, seven common defaults | Phone usability |
| Cumulative PV energy | Device sends energy.total_pv; server retains latest/historical counter and daily-energy floor without summing absolute reports | Actual device counter/history quality; unavailable earlier generation cannot be reconstructed |
| Parent/admin overview | Live organization/descendant scopes and isolation applied to App/Web | Real organization account acceptance |
| Cards and rated power | Identity/readings/timestamps and W/kW corrected; BMS child of inverter | Phone/device snapshot |
| Debug after shutdown | Interrupted-session recovery, retryable idempotent stop and late ACK protection | Physical power-off/on and stop/restart |
| Storage layout/BMS position | Overview/cells/diagnostics, station child entry and energy-flow owner chooser | Phone visual and navigation acceptance |
| Remote OTA action and phase percentages | Cloud action independent of downloaded firmware; stage_progress distinct from overall_progress | Deploy compatible API/communication/firmware and compare actual device logs |
| Web history clutter/header | Grouped searchable fields, presets/order/preferences, sticky headers/time column, null formatting | Online telemetry acceptance |
| Web refresh/automatic update | Query polling/focus/reconnect and related refresh paths audited across main monitoring/list/detail pages | Online sustained polling and changing data |
| Device entry/PIN | Approved four source paths; current v2 INFO cloud PIN flow, station propagation and owned selection | Actual phone radio/PIN/cloud response |
| Concurrent owned-device addition | API atomic unassigned/current-owner check; HTTP 409; explicit rebind preserved | Deploy new API before relying on App only_unassigned flag |
| Station action icons | Flat, colored, aligned icons | Physical phone |
| WiFi enabled without association | Native route binding no longer waits for future network; bounded scan/cancel guards | Android permissions/OEM behavior |
| Read system-saved WiFi password | Not implemented: unavailable to an ordinary Android App | Possible separate user-authorized QR or App-stored credentials design |

## Local Verification

- All four Go services: build, unit tests and vet passed.
- Full Business API repository and handler TimescaleDB integration suites passed. New real concurrent-assignment and HTTP 409/explicit-rebind tests passed; asynchronous audit confirmed before fixture teardown.
- Temporary loopback test container codex-station-assignment-pg stopped after verification; no production database used.
- Flutter full suite: 969 passed; 30 optional real-font BMS cases skipped in this run, covered by the prior separate 53-pass BMS run.
- Final focused history suite: 13 passed, including actual App themes, 320px, 1.5x text, Chinese/English and light/dark screenshots, field persistence/cancel, charts, paging and zero SOC.
- Flutter analyze: no errors/warnings; 1158 info notices. Not a clean-lint claim.
- Web: 543 tests/65 files passed; build:check passed; lint 0 errors/92 existing warnings.
- ESP-IDF build passed; 17/17 host tests passed; esptool validates version/checksum and image hash.
- APK version/ABI and APK v2 signing verified.

## Artifacts

- App acceptance APK: inv_app/release/inv_app_v1.1.7_build35_20261010.apk
- APK SHA256: 013410b100bfa94d7dabdfe3efeed0b71f7b756cc698ce9260a79480220625a6
- APK uses existing Android Debug certificate, not production-store signing.
- Firmware package: out/releases/cs_inv_l10_v1.0.19_release.zip
- ZIP SHA256: 678cdf758a8b6f7bd4a526c636a5a7706c3ffbe2a6029d711fedbf2328d3b84b
- Authoritative firmware source: D:/CS_INV_WIFI/esp32c3_l10_idf, current dirty daily workspace; only ESP firmware included.
- Firmware app SHA256: 3c20095ecd6d04767277d63f17da98ee77c36db417e693d0cb2895dbae9c42ff
- No upload, installation, hardware flash or Git tag performed.

## Remote And Rollout Boundary

Fresh GitHub checks confirm remote main d0517aff8e8428f7497007ad3f1cf5f95f1b09a7:
CI 37910590616, documentation 37910590651, production CD 37911967990 all completed successfully.
The documented deploy executed and reused previous images for the documentation-only commit; skipped image-build jobs are not claimed as executed.
Earlier production log warned that /opt/inv-mqtt/data-backup restoration was incomplete. This is not proof of data loss or a successful restore; it remains an operational follow-up.

At the initial verification checkpoint, the App device-entry/BMS/WiFi/history, Web refresh/history and atomic-assignment changes were local and uncommitted. On 2026-10-10 the user authorized a scoped commit and production deployment. The earlier successful runs above do not cover this new batch; its CI and actual production CD must be verified independently. Unrelated workspace edits, generated outputs and firmware binaries are excluded from the source publication.

## Telemetry Audit Boundary

The subsequent read-only audit used the user-confirmed ARM App(10) source, not the older external driver copy. The following findings have NOT been repaired by this publication:

- Heartbeat V3 omits the individual PV power mappings and keeps PV current under Buck-specific names rather than the generic history columns.
- Several legacy history columns differ from the stored Boost temperature, warning and output-energy fields.
- A nested BMS summary is not a scalar history value; rendering it as `--` does not establish that the payload is absent.
- The specified ARM App(10) collector has no CMD08 dispatcher. The source path is not proof that a later ARM binary installed on hardware has the same behavior.
- ARM daily-archive callers save the counters but do not call the accumulator/reset function; charging and discharging energy also use the same Pbat source.
- CMD08 decoder quantities and layout-zero field suppression still reflect the earlier protocol assumptions rather than the updated October layout document.

Do not present deploying this batch as fixing these newly diagnosed telemetry/ARM issues. No ARM or ESP firmware is automatically installed by the server/Web deployment.

Deploy the updated API before relying on only_unassigned=true, since older servers ignore unknown request fields. Use migration 127 and compatible communication/client/firmware versions for independent OTA stage progress.

Ordinary target-Q+ apps cannot obtain system-configured networks through getConfiguredNetworks, and returned legacy fields exclude the password: https://developer.android.com/reference/android/net/wifi/WifiManager#getConfiguredNetworks()
