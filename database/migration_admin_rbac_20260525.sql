-- RBAC 管理后台数据库迁移
-- 1. users表增加层级关系和安全字段
ALTER TABLE users ADD COLUMN IF NOT EXISTS parent_id BIGINT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS login_fail_count INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP;

-- 2. devices表增加安装商字段
ALTER TABLE devices ADD COLUMN IF NOT EXISTS installer_id BIGINT;

-- 3. firmware_versions表增加上传者字段
ALTER TABLE firmware_versions ADD COLUMN IF NOT EXISTS uploaded_by BIGINT;

-- 4. OTA升级任务表
CREATE TABLE IF NOT EXISTS ota_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(200) NOT NULL,
    firmware_id BIGINT NOT NULL,
    created_by BIGINT,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    total_devices INTEGER DEFAULT 0,
    success_count INTEGER DEFAULT 0,
    failed_count INTEGER DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ota_task_devices (
    id BIGSERIAL PRIMARY KEY,
    task_id UUID NOT NULL REFERENCES ota_tasks(id) ON DELETE CASCADE,
    device_sn VARCHAR(50) NOT NULL,
    old_version VARCHAR(50),
    new_version VARCHAR(50),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    progress INTEGER DEFAULT 0,
    error_message TEXT,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 5. 工单表
CREATE TABLE IF NOT EXISTS work_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(200) NOT NULL,
    description TEXT,
    device_sn VARCHAR(50),
    station_id BIGINT,
    created_by BIGINT,
    assigned_to BIGINT,
    priority INTEGER DEFAULT 2,
    status VARCHAR(20) NOT NULL DEFAULT 'open',
    resolution TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP
);

-- 6. 审计日志表
CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT,
    username VARCHAR(100),
    action VARCHAR(50) NOT NULL,
    resource VARCHAR(50),
    resource_id VARCHAR(100),
    details JSONB,
    ip_address VARCHAR(45),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

SELECT 'MIGRATION_OK' as result;
