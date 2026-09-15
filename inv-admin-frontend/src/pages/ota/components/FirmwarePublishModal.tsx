import React, { useEffect, useMemo, useState } from 'react'
import { Alert, Descriptions, Form, Input, Modal, Select, Slider, Tag } from 'antd'
import useTranslation from '@/hooks/useTranslation'
import useTimezoneStore from '@/stores/timezoneStore'
import { formatInTimezone } from '@/utils/timezone'
import type { Firmware, FirmwarePublishRequest } from '@/types'

const ROLLOUT_MARKS: Record<number, string> = {
  1: '1%',
  25: '25%',
  50: '50%',
  75: '75%',
  100: '100%',
}

interface FirmwarePublishModalProps {
  open: boolean
  firmware: Firmware | null
  confirmLoading?: boolean
  /** 同型号其它已发布固件，供选择回退目标 */
  publishedPeers?: Firmware[]
  onOk: (values: FirmwarePublishRequest) => void
  onCancel: () => void
}

/** 固件发布弹窗：范围 / 灰度 / 回退目标 */
const FirmwarePublishModal: React.FC<FirmwarePublishModalProps> = ({
  open,
  firmware,
  confirmLoading,
  publishedPeers = [],
  onOk,
  onCancel,
}) => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const [scope, setScope] = useState<'all' | 'device'>('all')
  const [targets, setTargets] = useState('')
  const [rolloutPercent, setRolloutPercent] = useState(100)
  const [rollbackTo, setRollbackTo] = useState<number | null>(null)
  const [error, setError] = useState('')

  useEffect(() => {
    if (!open) return
    setScope((firmware?.rollout_type as 'all' | 'device') || 'all')
    setTargets(firmware?.rollout_targets || '')
    setRolloutPercent(firmware?.rollout_percent ?? 100)
    setRollbackTo(
      firmware?.rollback_to_firmware_id != null && Number(firmware.rollback_to_firmware_id) > 0
        ? Number(firmware.rollback_to_firmware_id)
        : null,
    )
    setError('')
  }, [open, firmware])

  const peerOptions = useMemo(() => {
    if (!firmware) return []
    return publishedPeers
      .filter((fw) => Number(fw.id) !== Number(firmware.id) && fw.target_chip === firmware.target_chip)
      .map((fw) => ({
        label: `${fw.version}${fw.published_at ? ` · ${formatInTimezone(fw.published_at, timezone, 'YYYY-MM-DD HH:mm')}` : ''}`,
        value: Number(fw.id),
      }))
  }, [publishedPeers, firmware, timezone])

  const handleOk = () => {
    if (scope === 'device') {
      const list = targets
        .split(/[,，\s]+/)
        .map((s) => s.trim())
        .filter(Boolean)
      if (list.length === 0) {
        setError(t('ota.publishTargetsRequired'))
        return
      }
    }
    setError('')
    onOk({
      rollout_percent: rolloutPercent,
      rollout_type: scope,
      rollout_targets:
        scope === 'device'
          ? targets
              .split(/[,，\s]+/)
              .map((s) => s.trim())
              .filter(Boolean)
              .join(',')
          : '',
      rollback_to_firmware_id: rollbackTo,
    })
  }

  return (
    <Modal
      title={t('ota.publishConfigTitle')}
      open={open}
      onOk={handleOk}
      onCancel={onCancel}
      confirmLoading={confirmLoading}
      destroyOnClose
      width={560}
      okText={t('ota.publishFirmware')}
    >
      {firmware && (
        <>
          <Descriptions column={2} size="small" bordered style={{ marginBottom: 16 }}>
            <Descriptions.Item label={t('ota.model')}>{firmware.model}</Descriptions.Item>
            <Descriptions.Item label={t('ota.module')}>{firmware.target_chip}</Descriptions.Item>
            <Descriptions.Item label={t('ota.subVersion')}>{firmware.version}</Descriptions.Item>
            <Descriptions.Item label={t('ota.uploadTime')}>
              {formatInTimezone(firmware.created_at, timezone, 'YYYY-MM-DD HH:mm:ss')}
            </Descriptions.Item>
          </Descriptions>
          <Alert type="info" showIcon message={t('ota.publishConfigDesc')} style={{ marginBottom: 16 }} />
        </>
      )}
      <Form layout="vertical">
        <Form.Item label={t('ota.publishScope')} required>
          <Select
            value={scope}
            onChange={(v) => setScope(v as 'all' | 'device')}
            options={[
              { label: t('ota.publishScopeAll'), value: 'all' },
              { label: t('ota.publishScopeDevice'), value: 'device' },
            ]}
          />
        </Form.Item>
        {scope === 'device' && (
          <Form.Item label={t('ota.publishTargets')} required>
            <Input.TextArea
              rows={3}
              value={targets}
              onChange={(e) => setTargets(e.target.value)}
              placeholder={t('ota.publishTargetsPlaceholder')}
            />
          </Form.Item>
        )}
        <Form.Item label={t('ota.rolloutPercentLabel')}>
          <Slider min={1} max={100} value={rolloutPercent} onChange={setRolloutPercent} marks={ROLLOUT_MARKS} />
          <div style={{ color: '#999', fontSize: 12 }}>{t('ota.rolloutPercentHint')}</div>
        </Form.Item>
        <Form.Item label={t('ota.publishRollbackTo')}>
          <Select
            allowClear
            placeholder={t('ota.noPublishedFirmware')}
            value={rollbackTo ?? undefined}
            onChange={(v) => setRollbackTo(v == null ? null : Number(v))}
            options={peerOptions}
          />
          <div style={{ color: '#999', fontSize: 12, marginTop: 4 }}>{t('ota.publishRollbackHint')}</div>
        </Form.Item>
      </Form>
      {error && <Alert type="error" showIcon message={error} style={{ marginBottom: 8 }} />}
      <div style={{ textAlign: 'right' }}>
        <Tag color="blue">{scope === 'all' ? t('ota.publishScopeAll') : t('ota.publishScopeDevice')}</Tag>
        <Tag color="geekblue">{rolloutPercent}%</Tag>
      </div>
    </Modal>
  )
}

export default FirmwarePublishModal
