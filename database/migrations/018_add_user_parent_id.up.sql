-- 添加用户上下级关系字段
-- parent_id 表示上级用户ID，用于建立设备商→安装商→终端用户的层级关系

ALTER TABLE users ADD COLUMN IF NOT EXISTS parent_id BIGINT;

CREATE INDEX IF NOT EXISTS idx_users_parent ON users(parent_id);

COMMENT ON COLUMN users.parent_id IS '上级用户ID，用于建立层级关系：设备商→安装商→终端用户';
