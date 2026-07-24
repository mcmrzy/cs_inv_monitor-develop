-- Capability grants are additive. Object-level views still decide which rows
-- an installer or end user may view or mutate. Existing administrator choices
-- remain authoritative, matching migration 042's conflict policy.
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
    (4, 'stations', 'create', TRUE),
    (4, 'stations', 'edit', TRUE),
    (4, 'alerts', 'edit', TRUE),
    (4, 'notifications', 'edit', TRUE),
    (5, 'stations', 'create', TRUE),
    (5, 'stations', 'edit', TRUE),
    (5, 'stations', 'delete', TRUE),
    (5, 'devices', 'create', TRUE),
    (5, 'devices', 'edit', TRUE),
    (5, 'devices', 'delete', TRUE),
    (5, 'alerts', 'edit', TRUE),
    (5, 'alerts', 'delete', TRUE),
    (5, 'notifications', 'edit', TRUE),
    (5, 'notifications', 'delete', TRUE),
    (5, 'work_orders', 'edit', TRUE)
ON CONFLICT (role, resource, action) DO NOTHING;
