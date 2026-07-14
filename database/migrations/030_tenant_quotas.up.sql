ALTER TABLE users
    ADD COLUMN IF NOT EXISTS device_limit INTEGER,
    ADD COLUMN IF NOT EXISTS user_limit INTEGER;

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_device_limit_check;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_user_limit_check;
ALTER TABLE users ADD CONSTRAINT users_device_limit_check CHECK (device_limit BETWEEN 0 AND 100000);
ALTER TABLE users ADD CONSTRAINT users_user_limit_check CHECK (user_limit BETWEEN 0 AND 100000);

COMMENT ON COLUMN users.device_limit IS 'Maximum devices owned by this tenant; NULL means system default';
COMMENT ON COLUMN users.user_limit IS 'Maximum direct sub-users of this tenant; NULL means system default';
