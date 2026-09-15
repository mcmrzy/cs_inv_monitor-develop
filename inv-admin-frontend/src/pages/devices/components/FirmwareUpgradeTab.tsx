import React from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Card, Descriptions, Button, Table, Tag, Space, message, Empty, Spin, Typography, Select } from 'antd'
import type { ColumnsType } from 'antd/es/table'
import { ReloadOutlined, CloudDownloadOutlined } from '@ant-design/icons'
import { deviceApi } from '@/services/deviceApi'
import { otaApi, createOtaIdempotencyKey } from '@/services/otaApi'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import { firmwareModuleLabel } from '@/pages/ota/firmwarePresentation'
import type { DeviceFirmwareOverview, DeviceUpgrade, FirmwareResource } from '@/types'

const { Text } = Typography

interface FirmwareUpgradeTabProps {
  sn: string
}

const STATUS_COLOR_MAP: Record<string, string> = {
  pending: 'default',
  downloading: 'cyan',
  upgrading: 'processing',
  success: 'success',
  failed: 'error',
  cancelled: 'warning',
  blocked: 'orange',
  skipped: 'default',
}

/**
 * 设备详情 — 固件升级 Tab。
 * 旧升级包写接口已退役，这里只提供独立模块概览 / 升级 / 历史。
 */
const FirmwareUpgradeTab: React.FC<FirmwareUpgradeTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { timezone } = useTimezoneStore()
  const { user, hasPermission } = useAuthStore()
  const isSuperAdmin = user?.isSystemAdmin
  const canControl = Boolean(isSuperAdmin) || hasPermission('devices:control') || hasPermission('ota:control')

  const [historyPage, setHistoryPage] = React.useState(1)
  const [historyPageSize, setHistoryPageSize] = React.useState(10)
  const [selectedFirmwareId, setSelectedFirmwareId] = React.useState<number | null>(null)

  const { data: deviceData, isLoading: deviceLoading } = useQuery({
    queryKey: ['deviceBySn', sn],
    queryFn: () => deviceApi.getDeviceBySn(sn).then((res) => res.data?.data ?? res.data),
    enabled: !!sn,
  })

  const { data: overview, isLoading: overviewLoading, refetch: refetchOverview } = useQuery({
    queryKey: ['otaFirmwareOverview', sn],
    queryFn: () =>
      otaApi.getFirmwareOverview(sn).then((res) => {
        return (res.data?.data ?? res.data) as DeviceFirmwareOverview
      }),
    enabled: !!sn,
  })

  const { data: resources = [] } = useQuery({
    queryKey: ['otaFirmwareResources', sn],
    queryFn: () =>
      otaApi.getFirmwareResources(sn).then((res) => {
        const d = res.data?.data ?? res.data ?? {}
        const list = d?.items ?? (Array.isArray(d) ? d : [])
        return (Array.isArray(list) ? list : []) as FirmwareResource[]
      }),
    enabled: !!sn,
  })

  const { data: upgradeHistory, isLoading: historyLoading } = useQuery({
    queryKey: ['deviceUpgradeHistory', sn, historyPage, historyPageSize],
    queryFn: () =>
      otaApi
        .getDeviceUpgradeHistory(sn, { page: historyPage, page_size: historyPageSize })
        .then((res) => {
          const data = res.data?.data ?? res.data
          return {
            items: (data?.items ?? []) as DeviceUpgrade[],
            total: (data?.total ?? 0) as number,
          }
        }),
    enabled: !!sn,
  })

  const triggerMutation = useMutation({
    mutationFn: (firmwareId: number) =>
      otaApi.triggerFirmwareUpgrade({
        device_sn: sn,
        firmware_ids: [firmwareId],
        idempotency_key: createOtaIdempotencyKey('trigger'),
      }),
    onSuccess: () => {
      message.success(t('ota.triggerSuccess'))
      setSelectedFirmwareId(null)
      queryClient.invalidateQueries({ queryKey: ['otaFirmwareOverview', sn] })
      queryClient.invalidateQueries({ queryKey: ['deviceUpgradeHistory', sn] })
    },
    onError: (error: any) => {
      message.error(`${t('ota.triggerFailed')}: ${error?.response?.data?.message || error.message}`)
    },
  })

  const firmwareItems = React.useMemo(() => {
    if (!deviceData) return []
    return [
      { label: t('dev.firmwareArm'), children: deviceData.firmware_arm || '-' },
      { label: t('dev.firmwareEsp'), children: deviceData.firmware_esp || '-' },
      { label: t('dev.firmwareDsp'), children: deviceData.firmware_dsp || '-' },
      { label: t('dev.firmwareBms'), children: deviceData.firmware_bms || '-' },
      { label: t('dev.bootloaderVersion'), children: deviceData.bootloader_version || '-' },
    ]
  }, [deviceData, t])

  const historyColumns: ColumnsType<DeviceUpgrade> = [
    {
      title: t('ota.module'),
      dataIndex: 'target_chip',
      key: 'target_chip',
      render: (v: string) => firmwareModuleLabel(v, t),
    },
    { title: t('dev.firmwareVersion_col'), dataIndex: 'firmware_version', key: 'firmware_version' },
    { title: t('dev.oldVersion'), dataIndex: 'old_version', key: 'old_version', render: (v: string) => v || '-' },
    {
      title: t('dev.upgradeStatus'),
      dataIndex: 'status',
      key: 'status',
      render: (status: string) => <Tag color={STATUS_COLOR_MAP[status] || 'default'}>{status}</Tag>,
    },
    { title: t('dev.progress'), dataIndex: 'progress', key: 'progress', render: (v: number) => `${v ?? 0}%` },
    { title: t('dev.errorInfo'), dataIndex: 'error_message', key: 'error_message', render: (v: string) => v || '-' },
    {
      title: t('common.startTime'),
      dataIndex: 'started_at',
      key: 'started_at',
      render: (v: string) => formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss'),
    },
    {
      title: t('common.endTime'),
      dataIndex: 'completed_at',
      key: 'completed_at',
      render: (v: string) => formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss'),
    },
  ]

  const updatable = (overview?.modules ?? []).filter((m) => m.update_available)

  return (
    <Space direction="vertical" size="middle" style={{ width: '100%' }}>
      <Card size="small" title={t('dev.currentFirmware')}>
        {deviceLoading ? (
          <Spin />
        ) : deviceData ? (
          <Descriptions column={2} size="small">
            {firmwareItems.map((item) => (
              <Descriptions.Item key={item.label} label={item.label}>{item.children}</Descriptions.Item>
            ))}
          </Descriptions>
        ) : (
          <Empty description={t('dev.noRealtimeData')} />
        )}
      </Card>

      <Card
        size="small"
        title={t('ota.deviceFirmwareOverview')}
        extra={
          <Button icon={<ReloadOutlined />} size="small" onClick={() => refetchOverview()}>
            {t('ota.checkUpdates')}
          </Button>
        }
      >
        {overviewLoading ? (
          <Spin />
        ) : (overview?.modules?.length ?? 0) === 0 ? (
          <Empty description={t('ota.noFirmwareResources')} />
        ) : (
          <Table
            rowKey={(r: any) => r.target || String(r.latest_firmware_id)}
            size="small"
            pagination={false}
            dataSource={overview!.modules}
            columns={[
              {
                title: t('ota.module'),
                dataIndex: 'target',
                render: (v: string) => firmwareModuleLabel(v, t),
              },
              {
                title: t('ota.moduleCurrentVersion'),
                dataIndex: 'current_version',
                render: (v: string) => v || '-',
              },
              {
                title: t('ota.moduleLatestVersion'),
                dataIndex: 'latest_version',
                render: (v: string) => v || '-',
              },
              {
                title: t('common.status'),
                dataIndex: 'update_available',
                render: (available: boolean) =>
                  available ? (
                    <Tag color="warning">{t('ota.moduleUpdateAvailable')}</Tag>
                  ) : (
                    <Tag color="success">{t('ota.moduleNoUpdate')}</Tag>
                  ),
              },
            ]}
          />
        )}
      </Card>

      <Card size="small" title={t('ota.upgradeModule')}>
        <Space direction="vertical" size={8} style={{ width: '100%' }}>
          <Text type="secondary">{t('ota.firmwareLifecycleHint')}</Text>
          <Space wrap>
            <Select
              style={{ minWidth: 220 }}
              placeholder={t('ota.selectFirmwareToUpgrade')}
              value={selectedFirmwareId}
              onChange={setSelectedFirmwareId}
              options={resources.map((fw) => ({
                label: `${firmwareModuleLabel(fw.target_chip, t)} · ${fw.version}`,
                value: Number(fw.id),
              }))}
              notFoundContent={t('ota.noFirmwareResources')}
            />
            <Button
              type="primary"
              icon={<CloudDownloadOutlined />}
              disabled={!canControl || !selectedFirmwareId}
              loading={triggerMutation.isPending}
              onClick={() => {
                if (selectedFirmwareId) triggerMutation.mutate(selectedFirmwareId)
              }}
            >
              {t('ota.upgradeModule')}
            </Button>
            <Button
              disabled={!canControl || updatable.length === 0}
              onClick={() => {
                const ids = updatable
                  .map((m) => Number(m.latest_firmware_id))
                  .filter((id) => Number.isFinite(id) && id > 0)
                if (ids.length === 0) return
                otaApi
                  .triggerFirmwareUpgrade({
                    device_sn: sn,
                    firmware_ids: ids,
                    idempotency_key: createOtaIdempotencyKey('trigger'),
                  })
                  .then(() => {
                    message.success(t('ota.triggerSuccess'))
                    queryClient.invalidateQueries({ queryKey: ['otaFirmwareOverview', sn] })
                    queryClient.invalidateQueries({ queryKey: ['deviceUpgradeHistory', sn] })
                  })
                  .catch((error: any) => {
                    message.error(`${t('ota.triggerFailed')}: ${error?.response?.data?.message || error.message}`)
                  })
              }}
            >
              {t('ota.upgradeAllModules')}
            </Button>
          </Space>
        </Space>
      </Card>

      <Card size="small" title={t('ota.upgradeHistory')}>
        <Table<DeviceUpgrade>
          rowKey={(r) => String(r.id)}
          size="small"
          loading={historyLoading}
          columns={historyColumns}
          dataSource={upgradeHistory?.items ?? []}
          locale={{ emptyText: <Empty description={t('ota.noUpgradeHistory')} /> }}
          pagination={{
            current: historyPage,
            pageSize: historyPageSize,
            total: upgradeHistory?.total ?? 0,
            showSizeChanger: true,
            onChange: (p, ps) => {
              setHistoryPage(p)
              setHistoryPageSize(ps)
            },
          }}
        />
      </Card>
    </Space>
  )
}

export default FirmwareUpgradeTab
