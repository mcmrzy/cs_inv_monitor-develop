-- 允许 users.phone 为 NULL，支持海外用户纯邮箱注册（无需手机号）
-- PostgreSQL 中 UNIQUE 约束允许多个 NULL 值共存，不影响已有唯一性约束
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;
