DROP TABLE IF EXISTS device_offline_op_logs;
ALTER TABLE devices DROP COLUMN IF EXISTS device_key_hash;
