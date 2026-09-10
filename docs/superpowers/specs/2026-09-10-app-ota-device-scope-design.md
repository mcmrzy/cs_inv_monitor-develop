# App OTA Device Scope Design

## Problem

The Flutter App calls OTA-specific endpoints that validate only direct device ownership (`devices.user_id` or `user_device_rel`). That rejects system administrators and upstream channel users even when the organization hierarchy grants management of the device. The Web OTA path uses a different endpoint, so its success does not validate the App path.

## Approved behavior

- The App must not decide whether a device is directly owned by the signed-in user.
- The backend remains the authorization authority.
- A system administrator can manage every active device.
- A non-system administrator can manage a device owned by the actor or by a user in the actor's organization subtree, as represented by `v_user_hierarchy`.
- The hierarchy is transitive: an agent manages distributor, installer, and customer descendant devices; a distributor manages installer and customer descendant devices; an installer manages customer descendant devices.
- Explicit `user_device_rel` sharing remains valid.
- Users outside that scope remain denied.
- For this product flow, device visibility within that hierarchy is device management authority. App OTA does not add a second client-side ownership or `ota:control` decision.

## Design

Change the OTA repository's device-access predicate. Keep the existing method temporarily for compatibility, but redefine its result as "device is in the actor's management scope" rather than direct ownership. Use one `SELECT EXISTS` query covering system-administrator status, organization hierarchy, and explicit sharing.

Add one OTA-handler guard helper and call it from every authenticated App OTA endpoint whose request identifies a device SN and is not already classified as a separately permission-gated management operation. Existing guarded routes use the same helper; currently unguarded routes gain it. The covered routes are check-update, trigger, resend, status, per-device history, local-result reporting, package install, package-progress, device package list, and available-package list. The trigger service retains its defense-in-depth repository check. The two rollback routes keep their existing `ota:control` middleware and are outside this bug fix.

No Flutter-side ownership check or hierarchy reconstruction will be added. No database migration is required because `v_user_hierarchy` and the required organization closure already exist.

## Error handling

- Missing/deleted devices return `false` without exposing whether an unrelated SN exists.
- Database failures remain errors and fail closed.
- Out-of-scope access continues to produce the existing forbidden response.

## Verification

Add a PostgreSQL integration regression covering:

- system administrator accessing another user's device;
- installer/upstream user accessing a descendant user's device;
- agent accessing a customer device through distributor and installer levels;
- direct owner access;
- explicitly shared access;
- unrelated user denial;
- deleted device denial.

Add focused handler tests proving an unguarded device-scoped endpoint now denies an out-of-scope actor before reading or mutating OTA data. Confirm all named App routes call the common guard so future additions do not silently diverge.

Run the focused integration test when the test database is available, then run the repository/unit test package and Go formatting/static checks for changed files.
