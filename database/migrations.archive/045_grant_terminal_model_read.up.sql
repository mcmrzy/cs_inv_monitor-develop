-- 045: Terminal users need read-only access to the model registry so device
-- detail clients can resolve models, model fields, and the field catalog.
-- Existing rows are authoritative: in particular, an administrator may have
-- explicitly denied this permission and that choice must not be overwritten.
INSERT INTO role_permissions (role, resource, action, is_allowed)
VALUES (5, 'models', 'view', true)
ON CONFLICT (role, resource, action) DO NOTHING;
