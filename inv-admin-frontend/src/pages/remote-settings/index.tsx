// 远程设置 —— 两层结构：设置首页（模块分组折叠列表，逐项点击展开）→ 高级参数（工程师模式）

import React, { useState } from 'react'
import { Alert, Button, Card, Empty, Flex, Skeleton, Tag, Typography, List } from 'antd'
import { Link, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import DeviceSelector from './components/DeviceSelector'
import SettingsHome from './components/SettingsHome'
import AdvancedPanel from './components/AdvancedPanel'
import { useDeviceConfig } from './hooks/useDeviceConfig'
import { commandRecordPresentation } from './types'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'

const { Title, Text } = Typography

type View = { name: 'home' } | { name: 'advanced' }

const RemoteSettingsPage: React.FC = () => {
  const { t } = useTranslation()
  const [searchParams] = useSearchParams()
  const linkedSn = searchParams.get('sn')?.trim()
  const [selectedSn, setSelectedSn] = useState<string | null>(() => {
    return localStorage.getItem('remote-settings-device-sn')
  })

  const handleDeviceChange = (sn: string) => {
    setSelectedSn(sn || null)
    if (sn) {
      localStorage.setItem('remote-settings-device-sn', sn)
    } else {
      localStorage.removeItem('remote-settings-device-sn')
    }
  }

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>{t('remote.title')}</Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 24 }}>
        {t('remote.pageDescription')}
      </Text>

      {linkedSn ? (
        <LinkedDeviceSettings key={linkedSn} sn={linkedSn} />
      ) : selectedSn ? (
        <SettingsWorkspace key={selectedSn} sn={selectedSn} onDeviceChange={handleDeviceChange} />
      ) : (
        <>
          <DeviceSelector selectedSn={null} onDeviceChange={handleDeviceChange} onRead={() => undefined} reading={false} />
          <div style={{ borderRadius: 16, marginTop: 8, textAlign: 'center', padding: 48, background: '#fff' }}>
            <Empty description={t('remote.pleaseSelectDeviceFirst')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
          </div>
        </>
      )}
    </div>
  )
}

function LinkedDeviceSettings({ sn }: { sn: string }) {
  const { t } = useTranslation()
  const { data, isPending, error, refetch } = useQuery({
    queryKey: queryKeys.devices.detail(sn),
    queryFn: () => deviceApi.getDeviceBySn(encodeURIComponent(sn)).then((res) => res.data?.data ?? null),
    refetchInterval: 10_000,
  })

  if (isPending) return <Skeleton active />
  const device = data?.device ?? data
  if (device?.sn !== sn) {
    return error
      ? <QueryErrorAlert error={error} onRetry={() => void refetch()} />
      : <Empty description={t('remote.noDevice')} />
  }

  const reported = device.reported_model?.trim().toUpperCase()
  const assigned = device.model?.trim().toUpperCase()
  const modelMismatch = Boolean(reported && assigned &&
    ['PWR2KH12H1', '3KU', '6KU', '12KU'].includes(reported) && reported !== assigned)
  const online = !error && (data?.online_status?.online ?? (device.status === 1 || device.status === 2 || device.status === 'online'))

  return <SettingsWorkspace sn={sn} linkedDevice={{ online, modelMismatch, label: device.model || device.device_type }} />
}

type SettingsWorkspaceProps = { sn: string } & (
  | { onDeviceChange: (sn: string) => void; linkedDevice?: never }
  | { onDeviceChange?: never; linkedDevice: { online: boolean; modelMismatch?: boolean; label?: string } }
)

/** 选中设备后的工作区：设备选择器 + 三层视图切换 */
const SettingsWorkspace: React.FC<SettingsWorkspaceProps> = ({ sn, onDeviceChange, linkedDevice }) => {
  const { t } = useTranslation()
  const cfg = useDeviceConfig(sn, linkedDevice ? linkedDevice.online && !linkedDevice.modelMismatch : undefined)
  const { timezone } = useTimezoneStore()
  const [view, setView] = useState<View>({ name: 'home' })

  return (
    <>
      {linkedDevice ? (
        <Card size="small" style={{ marginBottom: 16 }}>
          <Flex align="center" gap={8} wrap="wrap">
            <Text strong>{sn}</Text>
            {linkedDevice.label && <Tag>{linkedDevice.label}</Tag>}
            <Tag color={linkedDevice.online ? 'success' : 'default'}>{t(linkedDevice.online ? 'remote.online' : 'remote.offline')}</Tag>
            <Button onClick={cfg.readCurrent} loading={cfg.reading} disabled={!cfg.canRead}>
              {t('remote.readCurrent')}
            </Button>
            <Link to="/remote-settings">{t('remote.selectDevice')}</Link>
          </Flex>
          {linkedDevice.modelMismatch
            ? <Alert style={{ marginTop: 8 }} showIcon type="warning" message={t('remote.modelMismatch')} />
            : !linkedDevice.online && <Alert style={{ marginTop: 8 }} showIcon type="warning" message={t('remote.linkedOffline')} />}
        </Card>
      ) : (
        <DeviceSelector
          selectedSn={sn}
          onDeviceChange={(next) => {
            setView({ name: 'home' })
            onDeviceChange(next)
          }}
          onRead={cfg.readCurrent}
          reading={cfg.reading}
        />
      )}

      {view.name === 'home' && (
        <SettingsHome
          cfg={cfg}
          loading={cfg.schemaLoading && cfg.stateLoading}
          onOpenAdvanced={() => setView({ name: 'advanced' })}
        />
      )}
      {view.name === 'advanced' && <AdvancedPanel cfg={cfg} onBack={() => setView({ name: 'home' })} />}
      {linkedDevice && (
        <Card title={t('remote.commandHistory')} size="small" style={{ marginTop: 16 }}>
          <List
            size="small"
            dataSource={cfg.history}
            rowKey="task_id"
            renderItem={(record) => {
              const presentation = commandRecordPresentation(record)
              const command = record.command_code ?? record.command_name ?? ''
              const target = record.params?.value
              const valueText = cfg.getMeta(command).kind === 'boolean'
                ? t(target ? 'remote3.enabled' : 'remote3.disabled')
                : String(target)
              return (
                <List.Item>
                  <Flex vertical gap={4} style={{ width: '100%' }}>
                    <Flex gap={8} justify="space-between" wrap="wrap">
                      <Text>{cfg.fieldLabel(command)}</Text>
                      <Tag color={presentation.color}>{presentation.label_zh}</Tag>
                    </Flex>
                    {target !== undefined && (
                      <Text type="secondary">{t('remote.targetValue')} · {valueText}</Text>
                    )}
                    <Text type="secondary">
                      {record.created_at ? formatInTimezone(record.created_at, timezone, 'YYYY-MM-DD HH:mm:ss') : '—'}
                    </Text>
                  </Flex>
                </List.Item>
              )
            }}
          />
        </Card>
      )}
    </>
  )
}

export default RemoteSettingsPage
