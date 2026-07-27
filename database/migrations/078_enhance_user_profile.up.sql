-- 078_enhance_user_profile: 增强用户个人信息字段
-- 添加国家、地区、个人简介字段

-- 添加国家字段
ALTER TABLE users ADD COLUMN IF NOT EXISTS country VARCHAR(100);

-- 添加地区/州字段
ALTER TABLE users ADD COLUMN IF NOT EXISTS region_name VARCHAR(100);

-- 添加个人简介字段
ALTER TABLE users ADD COLUMN IF NOT EXISTS bio TEXT;

-- 添加索引（可选，如果需要按国家/地区查询）
CREATE INDEX IF NOT EXISTS idx_users_country ON users(country) WHERE deleted_at IS NULL;

COMMENT ON COLUMN users.country IS '用户国家/地区代码（如 CN, US）';
COMMENT ON COLUMN users.region_name IS '用户所在州/省/地区名称';
COMMENT ON COLUMN users.bio IS '用户个人简介';
