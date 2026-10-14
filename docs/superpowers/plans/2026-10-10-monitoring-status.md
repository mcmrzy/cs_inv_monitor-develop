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
- Flutter final full suite: 972 passed; 30 optional real-font BMS cases skipped in this run, covered by a separate 53-pass real-font BMS run.
- Final focused history suite: 13 passed, including actual App themes, 320px, 1.5x text, Chinese/English and light/dark screenshots, field persistence/cancel, charts, paging and zero SOC.
- Flutter analyze: no errors/warnings; 1161 info notices; --no-fatal-infos passed. Not a clean-lint claim.
- Web final main: 548 tests/66 files passed; build:check passed. Production BMS UI checked at 1440px, 390px and 320px with nonblank canvas checks and populated zero/negative temperatures. BMS history labels retain localized names and engineering units without model metadata.
- New TimescaleDB regressions cover raw/hourly mapping repair and migration 128 field visibility. App regressions cover populated CMD08 measurements and station cards at 320px/1.8x text scale.
- ESP-IDF build passed; 17/17 host tests passed; esptool validates version/checksum and image hash.
- APK version/ABI and APK v2 signing verified.

## Artifacts

- App acceptance APK: inv_app/release/inv_app_v1.1.8_build36_20261010.apk
- APK SHA256: 5489c7760e0dfe91ec7e8ca0e041970e5b37e7365257e9102a31d38b5f54644b
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

The source audit used the user-confirmed ARM App(10) source, not the older external driver copy. The user subsequently requested all non-ARM fixes. This additional repair batch includes:

- Heartbeat V3 now uses the extended realtime cache, individual PV power/current and confirmed MOS/output-energy aliases. Existing historical reports receive equivalent raw/hourly read projections without rewriting compressed telemetry.
- Runtime seconds are exposed as hours, full warning values as alarm codes, and output energy as load energy. Migration 128 restores only the seven confirmed L10 model fields, leaving unsupported limits/efficiency/THD hidden.
- CMD08 capacities, signed temperature slots/extrema, MOS/PCB/environment temperatures and charging/reference quantities follow the updated October layout. Old retained BMS bytes receive idempotent read compatibility; expiry still masks live metrics.
- Web/App show populated layout-zero temperatures and charging voltage. History exposes independent BMS scalar measurements and meaningful BMS summary values rather than conflating them with DSP readings. Station card numbers scale within constrained widths.

ARM findings are deliberately excluded and remain unresolved:
- The specified ARM App(10) collector has no CMD08 dispatcher. The source path is not proof that a later ARM binary installed on hardware has the same behavior.
- ARM daily-archive callers save the counters but do not call the accumulator/reset function; charging and discharging energy also use the same Pbat source.

Do not present server/client deployment as repairing the ARM dispatcher or accumulator. No ARM or ESP firmware is automatically installed by the server/Web deployment. Authenticated device comparison and physical phone/radio acceptance remain separate from the local regressions.

Publication checkpoint: main 7e41fb563e6a46aa26cb8e54cf9fae4b2a256bf7 failed Flutter CI 38014772573 because of narrow station-card overflow; CD 38015407771 was skipped, not deployed. The reproducing layout test and fix are included in this repair batch. Its own CI/CD must be verified after pushing.

Next checkpoint: 2dafcf3f9 CI 38017128332 passed all eight non-Flutter jobs, including integration and E2E; Flutter failed because a history test required an untracked local preview font. CD 38017712859 was skipped, not deployed. The follow-up keeps every test assertion and treats that preview font as optional, matching existing font helpers. A committed-files-only App export without the font also reproduced bottom-navigation wrapping at 320px/1.8x scale; one-line constrained labels repair this real layout failure. The acceptance APK was rebuilt with that fix. No CI job or data/layout assertion was disabled.

Deploy the updated API before relying on only_unassigned=true, since older servers ignore unknown request fields. Use migration 127 and compatible communication/client/firmware versions for independent OTA stage progress.

## Resumed Publication Checkpoint (2026-10-10)

Recovered the interrupted chat "新增 ARM 0x08 BMS 命令支持". Its latest scope excludes ARM changes and continues the previously requested server/Web/App repair publication.

- Prepared publication tree: `.codex_tmp/monitoring-main`, commit `69fdc8ba8983ffb1e8e94dd08e331951f68d226d`.
- Published follow-up commits after previous main `2dafcf3f9b51f5a2b8f68a58971577cdbb3016fc`: `d67108189` (localized BMS history labels/units and optional preview font), `69fdc8ba8` (constrained station bottom-navigation labels).
- Fresh verification: all four Go services passed `go build ./...`, `go test ./...`, and `go vet ./...`; Web type checking/production build and 548 tests in 66 files passed.
- Committed-files-only App copy without the local preview font passed 970 non-golden tests; 30 optional real-font tests were skipped. `flutter analyze --no-pub --no-fatal-infos` passed with 1161 info notices and no errors/warnings.
- Existing App APK was independently verified as 1.1.8+36, arm64-v8a, APK Signature Scheme v2. APK and ESP release ZIP SHA256 values still match the Artifacts section above. No artifact rebuild was required because no source changed during this resumed verification.
- GitHub readback confirmed the previous CI failure and skipped CD. Those checkpoints are historical; this resumed repair batch now has its own successful CI and production rollout.
- Automatic approval review initially rejected the main push. The user subsequently explicitly approved it; `git push origin HEAD:main` succeeded and remote readback confirmed `69fdc8ba8983ffb1e8e94dd08e331951f68d226d`. CI run `38021277012` completed successfully: all nine jobs passed, including Flutter tests and the unsigned release APK build, Web, four Go modules, security, integration and E2E.
- Production CD run `38021939676` completed successfully on 2026-10-10 at 12:16 China time. Deployment logs confirm the API, device-communication and frontend containers use image tag `69fdc8ba8983ffb1e8e94dd08e331951f68d226d`; unchanged gateway/bridge images were reused. All nine services were healthy, the internal gateway `/health` probe passed, and Device Server MQTT/Redis readiness passed.
- Public post-deployment probes passed: management homepage and its new `/assets/main-L91zzRmf.js` both returned HTTP 200; unauthenticated `/api/v1/devices` returned the expected HTTP 401. The homepage asset changed from the previous `main-CrWrt2w0.js` and matches the locally verified build.
- The existing uploads/firmware migration warning remains: restoration was not completed and `/opt/inv-mqtt/data-backup` was retained for manual inspection. This successful service deployment is not proof of historical uploaded-file recovery or loss.
- Real BMS reporting, authenticated device-data comparison, phone installation and ARM firmware acceptance remain outside the confirmed deployment checks. ARM source was not changed and no firmware was installed on a device.

Verified workflow links: https://github.com/mcmrzy/cs_inv_monitor-develop/actions/runs/38021277012 (CI), https://github.com/mcmrzy/cs_inv_monitor-develop/actions/runs/38021939676 (production CD).

Ordinary target-Q+ apps cannot obtain system-configured networks through getConfiguredNetworks, and returned legacy fields exclude the password: https://developer.android.com/reference/android/net/wifi/WifiManager#getConfiguredNetworks()
