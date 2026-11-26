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
import { getDeviceControlContext } from './controlContract'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'

const { Title, Text } = Typography

type View = { name: 'home' } | { name: 'advanced' }

const RemoteSettingsPage: React.FC = () => {
  const { t } = useTranslation()
  const [searchParams] = useSearchParams()
  const linkedSn = searchParams.get('sn')?.trim() || null
  const [selectedSn, setSelectedSn] = useState<string | null>(() => {
    return localStorage.getItem('remote-settings-device-sn')
  })
  const sn = linkedSn ?? selectedSn

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

      {!linkedSn && <DeviceSelector selectedSn={selectedSn} onDeviceChange={handleDeviceChange} />}
      {sn ? (
        <SelectedDeviceSettings key={sn} sn={sn} linked={Boolean(linkedSn)} />
      ) : (
        <div style={{ borderRadius: 16, marginTop: 8, textAlign: 'center', padding: 48, background: '#fff' }}>
          <Empty description={t('remote.pleaseSelectDeviceFirst')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
        </div>
      )}
    </div>
  )
}

function SelectedDeviceSettings({ sn, linked }: { sn: string; linked: boolean }) {
  const { t } = useTranslation()
  const { data, isPending, error, refetch } = useQuery({
    queryKey: queryKeys.devices.detail(sn),
    queryFn: () => deviceApi.getDeviceBySn(encodeURIComponent(sn)).then((res) => res.data?.data ?? null),
    refetchInterval: 10_000,
  })

  if (isPending) return <Skeleton active />
  const device = getDeviceControlContext(data, sn)
  if (!device) {
    return error
      ? <QueryErrorAlert error={error} onRetry={() => void refetch()} />
      : <Empty description={t('remote.noDevice')} />
  }

  return (
    <>
      {error && <QueryErrorAlert error={error} onRetry={() => void refetch()} />}
      <SettingsWorkspace sn={sn} linked={linked} device={{ ...device, online: !error && device.online }} />
    </>
  )
}

type SettingsWorkspaceProps = { sn: string; linked: boolean; device: NonNullable<ReturnType<typeof getDeviceControlContext>> }

const SettingsWorkspace: React.FC<SettingsWorkspaceProps> = ({ sn, linked, device }) => {
  const { t } = useTranslation()
  const cfg = useDeviceConfig(sn, device.online && !device.modelMismatch)
  const powerLabel = t(cfg.powerCommand ? `commands.${cfg.powerCommand}` : 'remote.powerStateUnknown')
  const { timezone } = useTimezoneStore()
  const [view, setView] = useState<View>({ name: 'home' })

  return (
    <>
      {cfg.capabilitiesError && <QueryErrorAlert error={cfg.capabilitiesError} onRetry={cfg.refetchAll} />}
      <Card size="small" style={{ marginBottom: 16 }}>
        <Flex align="center" gap={8} wrap="wrap">
          <Text strong>{sn}</Text>
          {device.label && <Tag>{device.label}</Tag>}
          <Tag color={device.online ? 'success' : 'default'}>{t(device.online ? 'remote.online' : 'remote.offline')}</Tag>
          <Button onClick={cfg.readCurrent} loading={cfg.reading} disabled={!cfg.canRead}>
            {t('remote.readCurrent')}
          </Button>
          {cfg.showPower && (
            <Button
              aria-label={powerLabel}
              type={cfg.powerCommand === 'ac_on' ? 'primary' : 'default'}
              danger={cfg.powerCommand === 'ac_off'}
              disabled={!cfg.powerCommand || !cfg.canSendPower(cfg.powerCommand)}
              loading={cfg.sendingKey === 'ac_on' || cfg.sendingKey === 'ac_off'}
              onClick={() => { if (cfg.powerCommand) cfg.sendPower(cfg.powerCommand) }}
            >
              {powerLabel}
            </Button>
          )}
          {linked && <Link to="/remote-settings">{t('remote.selectDevice')}</Link>}
        </Flex>
        {cfg.controlState?.reported_at && (
          <Text type="secondary">{t('remote.lastReportedAt')} · {formatInTimezone(cfg.controlState.reported_at, timezone, 'YYYY-MM-DD HH:mm:ss')}</Text>
        )}
        {device.modelMismatch
          ? <Alert style={{ marginTop: 8 }} showIcon type="warning" message={t('remote.modelMismatch')} />
          : !device.online && <Alert style={{ marginTop: 8 }} showIcon type="warning" message={t('remote.linkedOffline')} />}
      </Card>

      {view.name === 'home' && (
        <SettingsHome
          cfg={cfg}
          loading={cfg.schemaLoading && cfg.stateLoading}
          onOpenAdvanced={() => setView({ name: 'advanced' })}
        />
      )}
      {view.name === 'advanced' && <AdvancedPanel cfg={cfg} onBack={() => setView({ name: 'home' })} />}
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
              ? t(Number(target) ? 'remote3.enabled' : 'remote3.disabled')
              : String(target)
            return (
              <List.Item>
                <Flex vertical gap={4} style={{ width: '100%' }}>
                  <Flex gap={8} justify="space-between" wrap="wrap">
                    <Text>{['ac_on', 'ac_off'].includes(command) ? t(`commands.${command}`) : cfg.fieldLabel(command)}</Text>
                    <Tag color={presentation.color}>{presentation.label_zh}</Tag>
                  </Flex>
                  {target !== undefined && (
                    <Text type="secondary">{t('remote.targetValue')} · {valueText}</Text>
                  )}
                  <Text type="secondary">
                    {record.created_at ? formatInTimezone(record.created_at, timezone, 'YYYY-MM-DD HH:mm:ss') : '—'}
                  </Text>
                  <Text copyable>{record.task_id}</Text>
                  {record.result_message && <Text type="secondary">{record.result_message}</Text>}
                </Flex>
              </List.Item>
            )
          }}
        />
      </Card>
    </>
  )
}

export default RemoteSettingsPage
