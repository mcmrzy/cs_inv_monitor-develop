ALTER TABLE users ADD COLUMN IF NOT EXISTS region_id BIGINT;

CREATE INDEX IF NOT EXISTS idx_users_region ON users(region_id);

SELECT column_name FROM information_schema.columns WHERE table_name = 'users' ORDER BY ordinal_position;
