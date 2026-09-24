# L10 BLE OTA binary transfer design

## Goal and rollout

Speed up phone-to-ESP local BLE OTA for a roughly 1.2 MB image without
claiming that a 1 KB GATT attribute is possible. Publish ESP 1.0.12 before
shipping the new App. The App uses only the binary data format; ESP 1.0.12
continues to accept the existing JSON data format during migration. Keep the
existing 1.0.11 release artifact unchanged.
Before binary upload, the App requires the explicit `ota_binary_v1` INFO
capability and negotiated MTU at least 256. This is a fail-fast
gate, not an old-transport fallback: older devices must first use the
currently installed App, cloud OTA, Wi-Fi AP OTA, or service flashing.

## Wire protocol

`ota.ctrl`, `ota.query`, `ota.cancel`, and `ota.status` remain JSON v2. The
OTA data characteristic additionally accepts binary frames:

| Byte(s) | Value |
| --- | --- |
| 0 | `0xB1` magic |
| 1 | `0x01` binary data version |
| 2–5 | transfer token, little-endian `uint32` from first eight hex digits of `transfer_id` |
| 6–9 | absolute file offset, little-endian `uint32` |
| 10 onward | raw firmware bytes, at least one byte |

The App generates a 24-hex-digit `transfer_id`. The device accepts a frame
only on the active OTA connection, with matching token and exact next offset;
it never silently skips or duplicates bytes. A physical write is at most
`min(509, negotiated_mtu - 3)` bytes including the 10-byte header. The App
targets at most 496 bytes of firmware data per write at MTU 512 and reduces
the size for lower MTUs. It uses write-with-response, not prepare/execute.

The App sends up to 1024 firmware bytes per logical batch, then waits for an
`ota.status.accepted_offset` at or beyond the batch end. The ESP sends a
receiving notification when the accepted offset crosses a 1024-byte boundary
or reaches the declared file size. `ota.query` returns the current accepted
offset at any time, including inside a batch. On an ambiguous GATT write
error or ACK timeout, the App queries this offset for the current transfer and
resumes from that exact point. ATT queue-full (9) is recoverable backpressure:
query the offset, briefly back off, and retry only unaccepted bytes. Bad
version/token/offset/length and inactive transfer fail immediately. The ESP queue admits
each physical fragment before advancing `accepted_offset`; its item count
and item size must remain within approximately the existing 1 KB queue
allocation. The worker buffer must be large enough for a fragment.
At the minimum supported MTU, status notifications must fit within MTU-3;
otherwise the App reads status after each batch rather than waiting for a
notification. The device's full JSON status remains available by read.

The App computes a whole-file SHA-256 if the manifest does not provide one.
The device retains end-of-file size, SHA-256, signature (when provided), and
ESP boot verification. One-kilobyte acceptance does not mean flash commit or
successful installation. On disconnect, the current local OTA session is
cancelled; retry starts a new session from zero unless a separately designed
resume protocol is introduced.

## Error and observability contract

Malformed version, token, offset, frame length, or inactive transfer returns
an ATT refusal without queue mutation. Full queue reports ATT queue-full,
without advancing the offset; this is not a terminal device refusal.
Keep accepted-offset and timing logs at batch boundaries, and distinguish
local BLE wait from upstream HTTP idle in diagnostics. A slow or failed
physical write must not be counted as accepted merely because Dart issued it.
The firmware honors a bounded `ota.ctrl.timeout_seconds`, never less than
600 seconds, while keeping the existing 30-second no-data escape. The App
requests at least 1200 seconds for a BLE transfer. Retry and ACK budgets must
stay below the 30-second idle limit: raw write and direct status read each
use a bounded timeout of about 5 seconds, and the App stops recovery after
20 seconds without accepted-offset progress. The performance goal is to transfer a
roughly 1.2 MB ESP image in 300 seconds or less on the test phone; the longer
total timeout is only a reliability guard, not a substitute for speed.

## Verification and release gates

Test binary parsing, token/offset validation, queue boundaries, batched ACK,
recovery after ambiguous write, low-MTU sizing, complete-file SHA, and legacy
JSON receiver behavior. Build ESP and release APK. Compare real-phone elapsed
time and final device version against the current 128/256-byte path. Do not
upload/publish ESP 1.0.12 as validated without a real-device transfer or an
explicitly identified unverified release decision.
