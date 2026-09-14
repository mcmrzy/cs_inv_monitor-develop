# App Package Publishing and Download Site Design

## Goal

Provide one reliable Android release flow: an administrator uploads an APK, the backend derives trustworthy metadata and stores the package, and the public download site immediately presents the newest release from `download.jiuxiaoyw.online`.

## Approved behavior

- Android APK is the only directly uploaded App package in this phase.
- The server parses `versionName`, `versionCode`, package name, `minSdk`, and `targetSdk` from the APK manifest.
- The server calculates file size and SHA-256. Operators do not type file metadata or a download URL.
- Operators continue to choose business policy: changelog, forced update, minimum supported App version, and rollout percentage.
- App packages are stored below `/data/firmware/apps/android/` and served through `/firmware/apps/android/...`.
- `APP_DOWNLOAD_URL=https://download.jiuxiaoyw.online` builds human-facing APK links.
- `DOWNLOAD_URL=https://jiuxiaoyw.online` remains separate for device firmware OTA because the ESP32 path requires direct-origin behavior.
- Firmware uploads use the server-calculated size and SHA-256. ESP versions come from the embedded image descriptor; other chip images may use the filename convention and must fail closed when no version can be recognized.
- The download page reads current release metadata dynamically; publishing a new APK requires no static-page copy or manual synchronization.

## Download site

The existing React `/download` route is the public product page. The download-domain Nginx virtual host redirects `/` to `/download`, serves only the SPA assets and public release metadata route, and retains `/firmware/` for binary files.

The canonical metadata source is `https://api.jiuxiaoyw.online/api/v1/ota/app/latest`. The download-domain alias is fallback only. This prevents a stale ESA cache entry on the alias from masking a newer database release.

The first viewport exposes the product identity, current Android version, size, compatibility, and download action. Desktop also provides a QR code; the page includes SHA-256 verification, release notes, and concise install guidance. It must remain responsive and usable on mobile.

## Failure behavior

- Invalid/non-APK uploads are rejected and removed.
- APKs without version metadata are rejected.
- A database failure removes the staged final file so no orphan release is advertised.
- If the canonical release endpoint is unavailable, the page tries the same-origin alias.
- If no release is available, the page shows an explicit unavailable state and disables download.

## Verification

- Unit tests cover binary AndroidManifest parsing and malformed packages.
- Handler tests cover server-derived metadata and cleanup on failure.
- Web tests prove no manual metadata fields are submitted and the newest canonical response wins over a stale alias.
- Type-check, production build, Go tests/vet/build, and production Compose validation pass.
- Production verification covers upload metadata, database record, generated URL, root download page, actual APK `HEAD`/Range response, and service health.
