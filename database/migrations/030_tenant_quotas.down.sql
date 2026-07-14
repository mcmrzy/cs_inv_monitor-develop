ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_device_limit_check,
    DROP CONSTRAINT IF EXISTS users_user_limit_check,
    DROP COLUMN IF EXISTS device_limit,
    DROP COLUMN IF EXISTS user_limit;
