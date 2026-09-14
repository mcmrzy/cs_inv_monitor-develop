-- Migration 117: device_upgrades 增加 stage（设备上报的原始阶段）
--
-- 背景：设备通过 ota/status 上报的状态词表比库内 status 细得多：
--   accepted / downloading / receiving / verifying / installing / rebooting /
--   succeeded / failed / rolled_back
-- 而 business-api 的 OTAStatus 把它们折叠成 upgrading / success / failed 写库，
-- 原始阶段信息丢失 —— 管理后台与 App 只能显示笼统的「升级中」，用户看不出
-- 现在到底是在下载、校验、写入设备，还是重启生效。
--
-- 修法：新增 stage 列保存设备上报的原始状态，**不改动 status**（任务统计、
-- 超时检测、终端态判断等既有逻辑继续依赖 status，避免连带影响）。
-- 前端据此分阶段展示：
--   已下发 → 下载固件 → 校验固件 → 写入设备 → 重启生效 → 完成
-- 其中各阶段自带进度（progress），因此会出现"阶段内 0-100%"的自然表现
-- （例如 ARM 先下载到 100%，进入写入阶段后从 70% 重新推进）。
--
-- 写入时机：OTAStatus 每次收到设备状态都会更新 stage（终端态也记录，
-- 便于排查"最后停在哪一步"）。旧数据 stage 为空串，前端回退到 status 展示。
-- 幂等：IF NOT EXISTS。
ALTER TABLE device_upgrades
    ADD COLUMN IF NOT EXISTS stage VARCHAR(20) NOT NULL DEFAULT '';

COMMENT ON COLUMN device_upgrades.stage IS
    '设备上报的原始 OTA 阶段(accepted/downloading/receiving/verifying/installing/rebooting/succeeded/failed/rolled_back)，用于前端分阶段展示；空=未知（旧数据）';
