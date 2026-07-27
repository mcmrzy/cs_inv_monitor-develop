-- 078_enhance_user_profile: 回滚用户个人信息字段增强

DROP INDEX IF EXISTS idx_users_country;
ALTER TABLE users DROP COLUMN IF EXISTS bio;
ALTER TABLE users DROP COLUMN IF EXISTS region_name;
ALTER TABLE users DROP COLUMN IF EXISTS country;
