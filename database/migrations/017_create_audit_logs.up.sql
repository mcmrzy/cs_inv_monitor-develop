-- 017_create_audit_logs: 审计日志表
-- 记录用户操作审计，用于安全审计和操作追溯

BEGIN;

-- 审计日志表
CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    operator_id BIGINT,                    -- 操作者用户ID
    operator_name VARCHAR(100) DEFAULT '', -- 操作者用户名/昵称
    action VARCHAR(50) NOT NULL,           -- 操作类型: login/logout/create/update/delete/import/export/bind/unbind/command/approve/reject
    resource_type VARCHAR(50) DEFAULT '',  -- 资源类型: auth/device/station/alarm/firmware/user/config 等
    resource_id BIGINT,                    -- 资源ID（可为空）
    detail JSONB DEFAULT '{}',             -- 操作详情（JSON格式）
    ip VARCHAR(45) DEFAULT '',             -- 操作者IP地址
    user_agent TEXT DEFAULT '',            -- 用户代理（可选）
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 索引优化
CREATE INDEX IF NOT EXISTS idx_audit_logs_operator ON audit_logs(operator_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_resource ON audit_logs(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_ip ON audit_logs(ip);

-- 注释
COMMENT ON TABLE audit_logs IS '审计日志表 - 记录所有用户操作';
COMMENT ON COLUMN audit_logs.action IS '操作类型: login/logout/create/update/delete/import/export/bind/unbind/command/approve/reject/reset_password';
COMMENT ON COLUMN audit_logs.resource_type IS '资源类型: auth/device/station/alarm/firmware/user/config/system';
COMMENT ON COLUMN audit_logs.detail IS '操作详情JSON，可包含变更前后值、操作描述等';

INSERT INTO schema_migrations (version, name) VALUES (17, 'create_audit_logs') ON CONFLICT DO NOTHING;

COMMIT;
