-- 回滚：恢复 users.phone 为 NOT NULL
-- 注意：若已存在 phone 为 NULL 的记录，需先处理数据才能执行此回滚
UPDATE users SET phone = '' WHERE phone IS NULL;
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
