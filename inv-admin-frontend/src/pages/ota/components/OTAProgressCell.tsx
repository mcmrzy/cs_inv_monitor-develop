import { Progress, Space, Typography } from 'antd'
import useTranslation from '@/hooks/useTranslation'
import type { DeviceUpgrade } from '@/types'

const stages: Record<string, string> = {
  accepted: 'ota.stageAccepted', downloading: 'ota.stageDownloading',
  receiving: 'ota.stageTransferring', transferring: 'ota.stageTransferring',
  verifying: 'ota.stageVerifying', installing: 'ota.stageInstalling',
  writing: 'ota.stageInstalling', upgrading: 'ota.stageInstalling',
  rebooting: 'ota.stageRebooting', succeeded: 'ota.stageSucceeded',
  failed: 'ota.stageFailed', cancelled: 'ota.stageCancelled',
  rolled_back: 'ota.stageRolledBack',
}
const statuses: Record<string, string> = {
  pending: 'ota.taskStatusPending', downloading: 'ota.downloading',
  upgrading: 'ota.upgrading', success: 'ota.success', failed: 'ota.failed',
  cancelled: 'ota.cancelled', blocked: 'ota.statusBlocked',
  skipped: 'ota.statusSkipped', timeout: 'ota.statusTimeout',
}

function percent(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 100
    ? value : null
}

export default function OTAProgressCell({ record }: { record: DeviceUpgrade }) {
  const { t } = useTranslation()
  const phase = percent(record.stage_progress)
  const overall = percent(record.overall_progress) ?? percent(record.progress)
  // Completing a phase is not completing an upgrade.
  const status = record.status === 'success' ? 'success'
    : record.status === 'failed' ? 'exception' : 'normal'
  return <Space direction="vertical" size={0} style={{ width: '100%', minWidth: 120 }}>
    <Typography.Text type="secondary" style={{ fontSize: 12 }}>
      {t(stages[record.stage] ?? statuses[record.status] ?? 'common.unknown')}
    </Typography.Text>
    {phase !== null ? <Progress percent={phase} size="small" status={status} /> : <span>--</span>}
    <Typography.Text type="secondary" style={{ fontSize: 12 }}>
      {t('ota.overallProgress')} {overall === null ? '--' : `${overall}%`}
    </Typography.Text>
  </Space>
}
