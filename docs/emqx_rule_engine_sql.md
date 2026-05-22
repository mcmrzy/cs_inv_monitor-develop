-- ============================================
-- EMQX Rule Engine SQL 参考
-- 位置: EMQX Dashboard → 数据集成 → 规则
-- 此文件仅供参考，需在 EMQX Dashboard 中手动配置
-- ============================================

-- ============================================
-- 规则 1：数据消息桥接到 Redis Streams
-- ============================================
-- SQL:
SELECT
  payload as data,
  topic as mqtt_topic,
  clientid,
  timestamp
FROM
  "cs_inv/+/data/#"

-- 动作: Redis Streams → device:stream
-- 参数:
--   Stream: device:stream
--   Max Length: 100000
--   Fields:
--     data = ${payload}
--     sn   = regex_replace(topic, 'cs_inv/([^/]+)/.*', '$1')

-- ============================================
-- 规则 2：remapLegacyPV 字段映射（替代 Go 代码）
-- ============================================
-- SQL:
SELECT
  payload.pv1_v as pv_voltage,
  payload.pv1_i as pv_current,
  payload.pv1_p as pv_power,
  payload.pv2_v,
  payload.pv2_i,
  payload.pv2_p,
  payload.pv1_temp,
  payload.pv2_temp
FROM
  "cs_inv/+/dc"

-- 动作: 消息重发布（将映射后的 JSON 发布到标准 topic）
-- 目标 Topic: cs_inv/${clientid}/data/pv
-- 或直接桥接到 Redis Streams

-- ============================================
-- 规则 3：remapLegacyEnergy 字段映射（替代 Go 代码）
-- ============================================
-- SQL:
SELECT
  payload.daily as daily_pv,
  payload.total as total_pv,
  payload.hours as runtime_hours
FROM
  "cs_inv/+/energy"

-- 动作: 消息重发布
-- 目标 Topic: cs_inv/${clientid}/data/energy

-- ============================================
-- 规则 4：告警阈值前置判断
-- ============================================
-- SQL:
SELECT
  payload.voltage as voltage,
  payload.temperature as temperature,
  payload.fault_code as fault_code
FROM
  "cs_inv/+/data/status"
WHERE
  payload.fault_code != 0

-- 动作: HTTP 请求 → http://api_server:8080/api/v1/internal/alarm
