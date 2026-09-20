-- 124: CS-L10-6K2 未实现字段标记（诊断/健康度按"型号字段能力"门控）
--
-- 背景（现场实证，L10 ARM 固件 CS-L10-6K2 未实现下列 10 个字段）：
--   a) 恒填 0：mppt_fan_speed / inv_fan_speed / parallel_charge_current / work_time_total；
--   b) 从未赋值（ARM malloc 未清零，上报随机堆内存）：inv_current / pv_temperature /
--      transformer_temperature / paired_socket / online_socket / on_socket。
-- 这些"0/垃圾值"原先被诊断与健康度当成真实数据，导致型号级恒假：
--   - 健康度：任一风扇 <30% 即扣 15 分 → L10 恒扣 15 分（fan_speed=0 恒命中）；
--   - 散热状态：fanLow → 恒 warning（实测 43°C 正常带载也报 warning）；
--   - 设备详情页：风扇/插槽/逆变电流等列显示 0 或垃圾值。
--
-- 本次处置（代码侧读取 specifications.diagnostics.unsupported_fields，
-- 见 device-communication/internal/model/diagnostics.go 的 DiagnosticSpecs.IsUnsupported）：
--   1. unsupported_fields 声明未实现字段 → 诊断判据（风扇异常/保养提醒）与健康度扣分项跳过该字段；
--      diagnostics 段其余键（阈值）原样保留，不覆盖 096 写入的值；
--   2. device_model_fields 对应字段标记不支持：is_supported/is_visible=FALSE，并同步关闭
--      show_realtime/show_history/allow_alarm_rule（与前端型号能力表"取消 is_supported"的级联语义一致，
--      见 inv-admin-frontend/src/pages/models/model_registry_workspace.tsx:283-288），
--      避免将来基于 field-capabilities 的"告警规则可选字段"把未实现字段列出来；
--      数据库中历史遥测值不动，保留取证。
--
-- 字段注册来源（已逐一确认存在，无需补注册）：
--   096 §5.3 注册 fan/diag/sock 8 键（mppt_fan_speed, inv_fan_speed, inv_current,
--   parallel_charge_current, work_time_total, paired_socket, online_socket, on_socket）；
--   091 §5 按协议字段全量注册 sys 组（含 pv_temperature=sys[6]、transformer_temperature=sys[7]）。
--   若某 key 因环境差异未注册，下述 UPDATE 以 IN 列表匹配，天然不匹配该行、安全跳过（不报错）。
--
-- 幂等可重放：JSONB 合并（|| / jsonb_build_object）结果确定（重复执行生成同一 JSON，且不丢其它键）；
-- 两条 UPDATE 均带"尚需变更"谓词（键不存在 / 值确为 TRUE），重复执行影响 0 行。全脚本无 DDL、可随时重跑。
-- 反向迁移：厂家补齐固件后执行 124_l10_unsupported_fields.down.sql 即恢复 096 行为
-- （unsupported_fields 清空后判据自动生效，无需改代码）；届时这些字段的真实值会被重新纳入判定。

-- ============================================================
-- 1. 型号诊断规格：写入 unsupported_fields（JSON 名与 model.DiagnosticSpecs 的 json tag 一致）
--    specifications || jsonb_build_object(...)：只覆盖 diagnostics 段，保留 phase/grid_mode 等其它规格；
--    JSONB 合并只影响 diagnostics 段内的 unsupported_fields 键，096 写入的阈值全部保留。
--    末尾谓词：未声明过该键时才写入 → 重放为严格 no-op（与 down 的谓词对称）。
-- ============================================================
UPDATE device_models
SET specifications = COALESCE(specifications, '{}'::jsonb) || jsonb_build_object(
        'diagnostics',
        COALESCE(specifications->'diagnostics', '{}'::jsonb)
            || jsonb_build_object(
                   'unsupported_fields',
                   '["mppt_fan_speed","inv_fan_speed","parallel_charge_current","work_time_total","inv_current","pv_temperature","transformer_temperature","paired_socket","online_socket","on_socket"]'::jsonb
               )
    ),
    updated_at = NOW()
WHERE model_code = 'CS-L10-6K2'
  AND NOT (COALESCE(specifications->'diagnostics', '{}'::jsonb) ? 'unsupported_fields');

-- ============================================================
-- 2. 字段能力表：10 个字段对 L10 型号标记为不支持
--    is_supported=FALSE → 后端能力判定；is_visible=FALSE → 前端不渲染；
--    show_realtime/show_history=FALSE → 实时/历史字段选择器不再提供；
--    allow_alarm_rule=FALSE → 告警规则字段选择器不再提供（该 flag 为 TRUE 的 6 个键：
--      096 §5.3 的 inv_fan_speed/mppt_fan_speed/inv_current/work_time_total/paired_socket
--      + 091 §5 的 transformer_temperature；allow_compare/default_chart 注册时即为 FALSE，无需改）
-- ============================================================
UPDATE device_model_fields
SET is_supported     = FALSE,
    is_visible       = FALSE,
    show_realtime    = FALSE,
    show_history     = FALSE,
    allow_alarm_rule = FALSE,
    updated_at       = NOW()
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2')
  AND field_key IN (
        'mppt_fan_speed',
        'inv_fan_speed',
        'parallel_charge_current',
        'work_time_total',
        'inv_current',
        'pv_temperature',
        'transformer_temperature',
        'paired_socket',
        'online_socket',
        'on_socket'
      )
  AND (is_supported IS DISTINCT FROM FALSE OR is_visible IS DISTINCT FROM FALSE
       OR show_realtime IS DISTINCT FROM FALSE OR show_history IS DISTINCT FROM FALSE
       OR allow_alarm_rule IS DISTINCT FROM FALSE);
