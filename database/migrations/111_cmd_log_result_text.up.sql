-- Migration 111: device_cmd_logs.result 改为 TEXT
--
-- 背景：UpdateCommandLogStatus 把状态消息（如「设备 xxx 离线，命令已排队
-- 等待发送」）写入 result 列，而该列是 VARCHAR(20)，长文本必然触发 22001
-- 超长错误；调用方多以 `_ =` 忽略返回值，导致 queued/failed 状态静默停在
-- pending，命令审计链路出现不可见的状态丢失。
--
-- 修法选择改列类型而非改代码写入目标：result 列当前只写不读（无 SELECT
-- 消费方），放宽为 TEXT 无兼容性风险；UPDATE 路径的既有代码保持不变。
-- 幂等：TYPE TEXT 重放安全。
ALTER TABLE device_cmd_logs
    ALTER COLUMN result TYPE TEXT;
