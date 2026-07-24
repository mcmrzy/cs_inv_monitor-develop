-- Repair the RBAC defaults introduced by migrations 012 and 020.
-- Fresh baseline databases skipped those migration bodies through baseline_version=22,
-- while upgraded databases may also be missing individual rows. Existing choices are
-- authoritative, so conflicts must never update is_allowed or updated_at.
INSERT INTO role_permissions (role, resource, action, is_allowed)
SELECT defaults.role, defaults.resource, allowed.action, true
FROM (VALUES
    (1, 'stations',     ARRAY['view', 'create', 'edit', 'delete']),
    (1, 'devices',      ARRAY['view', 'create', 'edit', 'delete']),
    (1, 'alerts',       ARRAY['view', 'edit']),
    (1, 'ota',          ARRAY['view', 'create', 'edit']),
    (1, 'firmware',     ARRAY['view', 'create']),
    (1, 'users',        ARRAY['view', 'create', 'edit']),
    (1, 'admin',        ARRAY['view']),
    (1, 'parallel',     ARRAY['view', 'create', 'edit']),
    (1, 'notifications', ARRAY['view', 'create', 'edit', 'delete']),
    (1, 'alert_rules',  ARRAY['view', 'create', 'edit', 'delete']),
    (1, 'work_orders',  ARRAY['view', 'create', 'edit', 'delete']),
    (1, 'models',       ARRAY['view', 'create', 'edit', 'delete']),
    (1, 'dashboard',    ARRAY['view']),

    (2, 'stations',     ARRAY['view', 'create', 'edit']),
    (2, 'devices',      ARRAY['view', 'create', 'edit']),
    (2, 'alerts',       ARRAY['view', 'edit']),
    (2, 'ota',          ARRAY['view', 'create']),
    (2, 'firmware',     ARRAY['view']),
    (2, 'users',        ARRAY['view']),
    (2, 'parallel',     ARRAY['view', 'create']),
    (2, 'notifications', ARRAY['view', 'create', 'edit']),
    (2, 'alert_rules',  ARRAY['view', 'create', 'edit']),
    (2, 'work_orders',  ARRAY['view', 'create', 'edit']),
    (2, 'models',       ARRAY['view']),
    (2, 'dashboard',    ARRAY['view']),

    (3, 'stations',     ARRAY['view', 'create', 'edit']),
    (3, 'devices',      ARRAY['view', 'create', 'edit']),
    (3, 'alerts',       ARRAY['view', 'edit']),
    (3, 'ota',          ARRAY['view', 'create']),
    (3, 'firmware',     ARRAY['view']),
    (3, 'users',        ARRAY['view']),
    (3, 'parallel',     ARRAY['view', 'create']),
    (3, 'notifications', ARRAY['view', 'create', 'edit']),
    (3, 'alert_rules',  ARRAY['view', 'create', 'edit']),
    (3, 'work_orders',  ARRAY['view', 'create', 'edit']),
    (3, 'models',       ARRAY['view']),
    (3, 'dashboard',    ARRAY['view']),

    (4, 'stations',     ARRAY['view']),
    (4, 'devices',      ARRAY['view', 'create', 'edit']),
    (4, 'alerts',       ARRAY['view']),
    (4, 'ota',          ARRAY['view']),
    (4, 'notifications', ARRAY['view']),
    (4, 'alert_rules',  ARRAY['view']),
    (4, 'work_orders',  ARRAY['view', 'create', 'edit']),
    (4, 'models',       ARRAY['view']),
    (4, 'dashboard',    ARRAY['view']),

    (5, 'stations',     ARRAY['view']),
    (5, 'devices',      ARRAY['view']),
    (5, 'alerts',       ARRAY['view']),
    (5, 'ota',          ARRAY['view']),
    (5, 'notifications', ARRAY['view']),
    (5, 'alert_rules',  ARRAY['view']),
    (5, 'work_orders',  ARRAY['view']),
    (5, 'dashboard',    ARRAY['view'])
) AS defaults(role, resource, actions)
CROSS JOIN LATERAL unnest(defaults.actions) AS allowed(action)
ON CONFLICT (role, resource, action) DO NOTHING;
