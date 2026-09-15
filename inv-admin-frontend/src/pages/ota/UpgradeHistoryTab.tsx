import React, { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Button,
  Card,
  Col,
  DatePicker,
  Empty,
  Input,
  Row,
  Select,
  Space,
  Table,
  Tag,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import { ReloadOutlined } from '@ant-design/icons'
import { type Dayjs } from 'dayjs'
import { otaApi } from '@/services/otaApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import useTimezoneStore from '@/stores/timezoneStore'
import { formatInTimezone } from '@/utils/timezone'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { firmwareModuleLabel } from './firmwarePresentation'
import type { DeviceUpgrade } from '@/types'

const { RangePicker } = DatePicker

const UPGRADE_STATUS_MAP: Record<string, { i18nKey: string; color: string }> = {
  pending: { i18nKey: 'ota.taskStatusPending', color: 'processing' },
  downloading: { i18nKey: 'ota.downloading', color: 'cyan' },
  upgrading: { i18nKey: 'ota.upgrading', color: 'warning' },
  success: { i18nKey: 'ota.success', color: 'success' },
  failed: { i18nKey: 'ota.failed', color: 'error' },
  cancelled: { i18nKey: 'ota.cancelled', color: 'default' },
  blocked: { i18nKey: 'ota.statusBlocked', color: 'orange' },
  skipped: { i18nKey: 'ota.statusSkipped', color: 'default' },
  timeout: { i18nKey: 'ota.statusTimeout', color: 'error' },
}

const MODULE_TARGETS = ['arm', 'esp', 'dsp', 'bms'] as const

/**
 * 授权范围内聚合升级历史。
 * 筛选参数在 otaApi.listUpgradeHistory 内序列化，组件不拼 URL。
 */
const UpgradeHistoryTab: React.FC = () => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()

  const [deviceSn, setDeviceSn] = useState('')
  const [deviceSnQuery, setDeviceSnQuery] = useState('')
  const [targetChip, setTargetChip] = useState<string | undefined>()
  const [status, setStatus] = useState<string | undefined>()
  const [range, setRange] = useState<[Dayjs | null, Dayjs | null] | null>(null)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)

  const queryParams = useMemo(
    () => ({
      device_sn: deviceSnQuery || undefined,
      target_chip: targetChip || undefined,
      status: status || undefined,
      start_time: range?.[0] ? range[0].toISOString() : undefined,
      end_time: range?.[1] ? range[1].toISOString() : undefined,
      page,
      page_size: pageSize,
    }),
    [deviceSnQuery, targetChip, status, range, page, pageSize],
  )

  const { data, isLoading, error, refetch, isFetching } = useQuery({
    queryKey: queryKeys.ota.history(queryParams),
    queryFn: () =>
      otaApi.listUpgradeHistory(queryParams).then((r) => {
        const d = r.data?.data ?? r.data ?? {}
        const items = d?.items ?? []
        return {
          items: (Array.isArray(items) ? items : []) as DeviceUpgrade[],
          total: (d?.total ?? 0) as number,
        }
      }),
  })

  const resetPaging = () => setPage(1)

  const columns: ColumnsType<DeviceUpgrade> = [
    {
      title: t('common.deviceSN'),
      dataIndex: 'device_sn',
      key: 'device_sn',
      width: 140,
      ellipsis: true,
    },
    {
      title: t('ota.model'),
      dataIndex: 'device_model',
      key: 'device_model',
      width: 110,
      render: (v: string) => v || '-',
    },
    {
      title: t('ota.module'),
      dataIndex: 'target_chip',
      key: 'target_chip',
      width: 110,
      render: (v: string) => firmwareModuleLabel(v, t),
    },
    {
      title: t('ota.oldVersion'),
      dataIndex: 'old_version',
      key: 'old_version',
      width: 110,
      render: (v: string) => v || '-',
    },
    {
      title: t('ota.firmwareVersion'),
      dataIndex: 'firmware_version',
      key: 'firmware_version',
      width: 110,
    },
    {
      title: t('common.status'),
      dataIndex: 'status',
      key: 'status',
      width: 100,
      render: (s: string) => {
        const cfg = UPGRADE_STATUS_MAP[s]
        return <Tag color={cfg?.color || 'default'}>{cfg ? t(cfg.i18nKey) : s}</Tag>
      },
    },
    {
      title: t('ota.progress'),
      dataIndex: 'progress',
      key: 'progress',
      width: 80,
      render: (v: number) => `${v ?? 0}%`,
    },
    {
      title: t('ota.executeTime'),
      dataIndex: 'started_at',
      key: 'started_at',
      width: 160,
      render: (v: string, r: DeviceUpgrade) =>
        v
          ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss')
          : r.created_at
            ? formatInTimezone(r.created_at, timezone, 'YYYY-MM-DD HH:mm:ss')
            : '-',
    },
    {
      title: t('ota.completeTime'),
      dataIndex: 'completed_at',
      key: 'completed_at',
      width: 160,
      render: (v: string) => (v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss') : '-'),
    },
    {
      title: t('ota.errorInfo'),
      dataIndex: 'error_message',
      key: 'error_message',
      ellipsis: true,
      render: (v: string) => v || '-',
    },
    {
      title: t('ota.source'),
      dataIndex: 'source',
      key: 'source',
      width: 100,
      render: (v: string) => {
        const map: Record<string, { label: string; color: string }> = {
          admin: { label: t('ota.sourceAdmin'), color: 'blue' },
          app: { label: t('ota.sourceApp'), color: 'green' },
          local: { label: t('ota.sourceLocal'), color: 'orange' },
        }
        const cfg = map[v || '']
        return cfg ? <Tag color={cfg.color}>{cfg.label}</Tag> : (v || '-')
      },
    },
    {
      title: t('common.createdAt'),
      dataIndex: 'created_at',
      key: 'created_at',
      width: 160,
      render: (v: string) => (v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss') : '-'),
    },
  ]

  return (
    <div>
      {error && (
        <QueryErrorAlert error={error} onRetry={() => void refetch()} style={{ marginBottom: 16 }} />
      )}
      <Card size="small" style={{ marginBottom: 16 }}>
        <Row gutter={[12, 12]} align="middle">
          <Col>
            <Input.Search
              allowClear
              placeholder={t('ota.filterByDeviceSn')}
              style={{ width: 180 }}
              value={deviceSn}
              onChange={(e) => setDeviceSn(e.target.value)}
              onSearch={(v) => {
                setDeviceSnQuery(v.trim())
                resetPaging()
              }}
              enterButton
            />
          </Col>
          <Col>
            <Select
              allowClear
              placeholder={t('ota.filterByModule')}
              style={{ width: 140 }}
              value={targetChip}
              onChange={(v) => {
                setTargetChip(v)
                resetPaging()
              }}
              options={MODULE_TARGETS.map((chip) => ({
                label: firmwareModuleLabel(chip, t),
                value: chip,
              }))}
            />
          </Col>
          <Col>
            <Select
              allowClear
              placeholder={t('ota.filterByStatus')}
              style={{ width: 140 }}
              value={status}
              onChange={(v) => {
                setStatus(v)
                resetPaging()
              }}
              options={[
                { label: t('ota.taskStatusPending'), value: 'pending' },
                { label: t('ota.downloading'), value: 'downloading' },
                { label: t('ota.upgrading'), value: 'upgrading' },
                { label: t('ota.success'), value: 'success' },
                { label: t('ota.failed'), value: 'failed' },
                { label: t('ota.cancelled'), value: 'cancelled' },
                { label: t('ota.statusBlocked'), value: 'blocked' },
                { label: t('ota.statusSkipped'), value: 'skipped' },
              ]}
            />
          </Col>
          <Col>
            <RangePicker
              showTime
              value={range}
              onChange={(vals) => {
                setRange(vals as [Dayjs | null, Dayjs | null] | null)
                resetPaging()
              }}
              placeholder={[t('ota.startTime'), t('ota.endTime')]}
            />
          </Col>
          <Col>
            <Space>
              <Button
                onClick={() => {
                  setDeviceSn('')
                  setDeviceSnQuery('')
                  setTargetChip(undefined)
                  setStatus(undefined)
                  setRange(null)
                  resetPaging()
                }}
              >
                {t('common.reset')}
              </Button>
              <Button icon={<ReloadOutlined />} loading={isFetching} onClick={() => refetch()}>
                {t('common.refresh')}
              </Button>
            </Space>
          </Col>
        </Row>
      </Card>

      <Table<DeviceUpgrade>
        rowKey={(r) => String(r.id)}
        size="small"
        loading={isLoading}
        columns={columns}
        dataSource={data?.items ?? []}
        scroll={{ x: 1100 }}
        locale={{ emptyText: <Empty description={t('ota.noUpgradeHistory')} /> }}
        pagination={{
          current: page,
          pageSize,
          total: data?.total ?? 0,
          showSizeChanger: true,
          showTotal: (total) => t('common.total', { total }),
          onChange: (p, ps) => {
            setPage(p)
            setPageSize(ps)
          },
        }}
      />
    </div>
  )
}

export default UpgradeHistoryTab
