# Signed binding state v1

## Activation

1. Apply the new `130_device_binding_revision.up.sql` through the existing business-api migration startup process before enabling the responder.
2. Configure the device server's controlled runtime environment `BINDING_SIGNING_KEY_HEX` with a dedicated 32-byte Ed25519 signing seed (64 hex characters). Never use the product PIN HMAC secret or OTA key here. Never put it in source, build output or device firmware.
3. In the same controlled environment, run `go run ./cmd/binding-public-key`. The program prints **only the corresponding 32-byte public key**. Set that public value in firmware `CONFIG_DIRECT_BINDING_PUBLIC_KEY`. key_id is 1 for this protocol version.
4. Restart only as part of the separately approved deployment. Blank signing configuration disables the responder; malformed configuration fails startup when MQTT is enabled.

No production key has been generated, written or deployed by this implementation. A candidate with a blank firmware public key does not activate signed binding synchronization.

## Wire contract

Query topic `cs_inv/{SN}/binding/query`, regular firmware envelope with `data={"sn":"<16 uppercase alphanumeric>","nonce":"<32 lowercase hex>"}`. Max 512 bytes. Response topic `cs_inv/{SN}/binding/state` uses QoS 1, retain=false, and a **bare** JSON object with sn, state, revision (decimal string), nonce, key_id=1, signature (128 lowercase hex characters). SN mismatch or malformed nonce is ignored.

Canonical signature bytes, including final LF:

```text
CSERGY-BINDING-V1
<sn>
<UNKNOWN|UNBOUND|BOUND>
<revision>
<nonce>
```

SN absent from devices/counter => UNKNOWN revision "0". A deleted device or a retained tombstone => UNKNOWN with its durable revision. Active device user_id>0 => BOUND, otherwise UNBOUND. Database errors do not fabricate an UNBOUND response. No account name, PIN or user ID appears on this topic.

## Revision and rollback

The per-SN revision side table survives physical deletion/recreation. The devices trigger increments transactionally on insert/delete or changes of SN, user_id or deleted_at. Ordinary telemetry timestamps and idempotent ownership writes do not increment it. This covers service Bind/Unbind, approved unlink, claim, device transfer, station ownership transfer and administrative raw SQL updates. Any bigint exhaustion rolls back the ownership change rather than wrapping.

The down migration removes the trigger/function but retains counters. Re-enable migration advances retained counters before backfilling current devices. Do not drop the counter table in production. This preserves device cache monotonicity across rollback; no revision is reset by normal operations.

## Runtime behavior and validation limits

The callback parses a bounded payload and nonblocking-enqueues into a 64-slot channel. One worker accesses the database, signs and publishes with a five-second deadline. Saturated queues and unavailable database/broker rely on device-side timeout/backoff. The exact query/state dispatch occurs before the wildcard subscription updates heartbeat counters; the service's own state response never marks a device online.

Go service/repository/mqtt tests and static vet run locally. New actual-migration PostgreSQL test is under the integration build tag and requires a dedicated `BINDING_TEST_DATABASE_URL`; it creates/drops a unique isolated schema. No dedicated database or running Docker daemon was available during implementation, so SQL migration, concurrent database and end-to-end acceptance remain unverified. No server deployment was performed.
