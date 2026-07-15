UPDATE device_parallel_events
SET event_type = 'topology_changed'
WHERE event_type = 'out_of_order';

ALTER TABLE device_parallel_events
    DROP CONSTRAINT IF EXISTS device_parallel_events_event_type_check;

ALTER TABLE device_parallel_events
    ADD CONSTRAINT device_parallel_events_event_type_check
    CHECK (event_type IN (
        'parallel_created', 'topology_changed', 'master_switched',
        'member_added', 'member_removed', 'sync_state_changed', 'disabled'
    ));
