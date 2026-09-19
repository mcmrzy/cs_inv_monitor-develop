-- 122: 单设备调试会话表
-- 背景：单设备调试模式——App/Web 对指定设备开启临时调试后，设备按 30 秒周期
-- 上报运行快照（heartbeat V2.1），双端绘制 MPPT/电池/逆变/负载电压电流曲线。
-- device_debug_sessions 只保存调试意图与生命周期；曲线样本继续写
-- device_telemetry_3min（不复制遥测表），本表不落任何遥测数值。
--
-- 状态机：starting -> active -> stopping -> stopped
--                    |           \-> expired（到期兜底）
--                    \-> interrupted（样本中断/设备离线）
--         starting 超时无回执 -> failed
-- interrupted/failed/stopped/expired 为终态，允许重新开启。
--
-- 部分唯一索引保证同一设备同一时刻至多一个「占用中」会话
-- （starting/active/stopping），API 重试与 App/Web 同时点击不会创建
-- 多个设备侧定时器；(device_sn, request_id) 唯一保证同一请求幂等。

-- 附：调试曲线样本依赖的遥测列 buck1_current/buck2_current 由迁移 091 引入，
-- 但 squash 基线（0..95）未同步且 091 不在 migrator 的 096+ 回放尾部，
-- 全新 initdb 库会缺列导致样本查询 42703。此处幂等补齐（存量库为 no-op）。
ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS buck1_current REAL;
ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS buck2_current REAL;

CREATE TABLE IF NOT EXISTS device_debug_sessions (
    id               BIGSERIAL PRIMARY KEY,
    device_sn        VARCHAR(50) NOT NULL,
    request_id       VARCHAR(64) NOT NULL DEFAULT '',
    status           VARCHAR(20) NOT NULL DEFAULT 'starting',
    interval_seconds INT         NOT NULL DEFAULT 30,
    duration_seconds INT         NOT NULL DEFAULT 3600,
    started_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at       TIMESTAMPTZ NOT NULL,
    stopped_at       TIMESTAMPTZ,
    requested_by     BIGINT      NOT NULL DEFAULT 0,
    source           VARCHAR(20) NOT NULL DEFAULT 'web',
    start_task_id    VARCHAR(64) NOT NULL DEFAULT '',
    stop_task_id     VARCHAR(64) NOT NULL DEFAULT '',
    last_sample_at   TIMESTAMPTZ,
    failure_reason   TEXT        NOT NULL DEFAULT '',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_device_debug_request UNIQUE (device_sn, request_id),
    CONSTRAINT ck_device_debug_status CHECK (status IN
        ('starting', 'active', 'stopping', 'stopped', 'expired', 'interrupted', 'failed'))
);

CREATE INDEX IF NOT EXISTS idx_device_debug_sn_created
    ON device_debug_sessions (device_sn, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_debug_status_expires
    ON device_debug_sessions (status, expires_at);
-- 同一设备至多一个未结束会话：并发开启/重试只有一个能插入
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_debug_active_sn
    ON device_debug_sessions (device_sn)
    WHERE status IN ('starting', 'active', 'stopping');
