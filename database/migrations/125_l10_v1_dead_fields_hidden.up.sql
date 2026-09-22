-- 125: CS-L10-6K2 V1 遗留死键隐藏（DSP 不上传、V2 心跳永不填充的字段不再展示）
--
-- 背景（2026-09-22 依 DSP 发 ARM 的 TxBuf 实源 UsartDsp.c 逐字段核对）：
-- DSP 每帧仅上传 26 个物理量（Vgrid/Igrid/GridFreq/Pgrid/Sgrid/PgridPercent、
-- Vinvt/Iinvt/InvtFreq/Pinvt/Sinvt/InvtPercent、Vload/Iload/LoadFreq/Pload/
-- Sload/PloadPercent、Vbat/Ibat/Pbat/PbatPercent、Vbus/Ibus、Vpv1/Ipv1/Vpv2/
-- Ipv2/Ppv1/Ppv2/Ppv、Temprature）。下列 17 个键在 V2 心跳解析
-- (device-communication/internal/telemetry/heartbeat_v2.go) 中无任何赋值语句，
-- 历史表永远显示 "--"，其中 5 个与 V2 新键数据重复：
--   a) V2 有等价数据源（重复列，数据在括号内 V2 键下）：
--      pv1_current(buck1_current)、pv2_current(buck2_current)、
--      mos_temperature(boost_temperature, App 的 BoostTemp 即 LV_MOS 温度)、
--      alarm_code(warning)、runtime_hours(work_time_total)；
--   b) V1 专属概念，DSP/ARM 均无数据源：
--      mppt_state、pv1_power、pv1_power_max、pv1_voltage_max、pv2_power、
--      pv2_power_max、ac_power_factor、ac_voltage_thd、ambient_temperature、
--      efficiency、fan_speed_percent(V2 拆为 mppt/inv 两键)、system_mode。
-- 与 124 的处置一致（flag 门控而非删行）：is_supported/is_visible=FALSE 并关闭
-- show_realtime/show_history/allow_alarm_rule，行保留便于厂家将来实现后
-- 执行 down 一键恢复。数据库中历史遥测值不动。
-- 注：diag/sock/fan/pv_temperature/transformer_temperature 等未实现字段已由
--     124 隐藏，本迁移不重复处理；bms 组字段未接电池时为 null 属合法，
--     本迁移亦不处理。
--
-- 幂等可重放：UPDATE 带"尚需变更"谓词，重复执行影响 0 行；键不存在时
-- IN 列表天然不匹配、安全跳过（与 124 同款安全语义）。全脚本无 DDL、可随时重跑。

UPDATE device_model_fields
SET is_supported     = FALSE,
    is_visible       = FALSE,
    show_realtime    = FALSE,
    show_history     = FALSE,
    allow_alarm_rule = FALSE,
    updated_at       = NOW()
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2')
  AND field_key IN (
        'pv1_current',
        'pv2_current',
        'mos_temperature',
        'alarm_code',
        'runtime_hours',
        'mppt_state',
        'pv1_power',
        'pv1_power_max',
        'pv1_voltage_max',
        'pv2_power',
        'pv2_power_max',
        'ac_power_factor',
        'ac_voltage_thd',
        'ambient_temperature',
        'efficiency',
        'fan_speed_percent',
        'system_mode'
      )
  AND (is_supported IS DISTINCT FROM FALSE OR is_visible IS DISTINCT FROM FALSE
       OR show_realtime IS DISTINCT FROM FALSE OR show_history IS DISTINCT FROM FALSE
       OR allow_alarm_rule IS DISTINCT FROM FALSE);
