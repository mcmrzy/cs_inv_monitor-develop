-- 040: Runtime contract fixes found by deployed protocol smoke tests.
-- 039 fresh installs already include this value; this migration upgrades
-- databases that applied the first 039 revision before the smoke test.

ALTER TABLE device_parallel_events
    DROP CONSTRAINT IF EXISTS device_parallel_events_event_type_check;

ALTER TABLE device_parallel_events
    ADD CONSTRAINT device_parallel_events_event_type_check
    CHECK (event_type IN (
        'parallel_created', 'topology_changed', 'master_switched',
        'member_added', 'member_removed', 'sync_state_changed', 'disabled',
        'out_of_order'
    ));

COMMENT ON CONSTRAINT device_parallel_events_event_type_check
    ON device_parallel_events IS
    'Includes out_of_order for immutable late topology snapshots that do not replace current state';
