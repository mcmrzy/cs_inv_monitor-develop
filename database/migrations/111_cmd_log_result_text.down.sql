-- 回滚：result 回到 VARCHAR(20)。
-- 注意：若列中已存在超过 20 字符的数据，此回滚会失败；需先截断或清理。
ALTER TABLE device_cmd_logs
    ALTER COLUMN result TYPE VARCHAR(20);
