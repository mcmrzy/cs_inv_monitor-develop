import { useState, useMemo } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Card, Table, Button, Select, Tag, Space, Row, Col, DatePicker,
  Statistic, Typography, App, Empty, Tabs, Drawer, Alert as AntAlert, Tooltip, Descriptions,
} from 'antd'
import { ReloadOutlined, CheckOutlined, StopOutlined, AlertOutlined, DeleteOutlined, ClearOutlined, BellOutlined } from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import dayjs from 'dayjs'
import api from '@/services/api'
import { alertApi, notificationApi } from '@/services/alertApi'
import { deviceApi } from '@/services/deviceApi'
import { getApiErrorMessage, protocolApi, type AlarmEvent } from '@/services/protocolApi'
import { ALARM_LEVEL_MAP, getAlarmLevelDisplay, getAlarmMessageI18nKey } from '@/utils/constants'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import type { Alert } from '@/types'
import useTranslation from '@/hooks/useTranslation'
import useTimezoneStore from '@/stores/timezoneStore'
import StatisticCard from '@/components/StatisticCard'

const { RangePicker } = DatePicker
const { Title, Text } = Typography

interface NotificationItem {
  id: number
  device_sn: string
  notify_type: string
  title: string
  content: string
  created_at: string
  _type: 'notification'
}

const AlertsPage: React.FC = () => {
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [statusFilter, setStatusFilter] = useState<string>()
  const [levelFilter, setLevelFilter] = useState<string>()
  const [stationId, setStationId] = useState<number>()
  const [keyword, setKeyword] = useState<string>()
  const [dateRange, setDateRange] = useState<[dayjs.Dayjs, dayjs.Dayjs] | null>(null)
  const [activeTab, setActiveTab] = useState<string>('all')
  const [traceSN, setTraceSN] = useState<string>()
  const [traceOpen, setTraceOpen] = useState(false)
  const [selectedEventID, setSelectedEventID] = useState<number>()

  const ALERT_STATUS_MAP: Record<string, { label: string; color: string }> = {
    '0': { label: t('alert.unprocessed'), color: '#ff4d4f' },
    '1': { label: t('alert.processed'), color: '#52c41a' },
    '2': { label: t('alert.ignored'), color: '#d9d9d9' },
  }

  const NOTIFY_TYPE_MAP: Record<string, { label: string; color: string; icon: string }> = {
    'device_online': { label: t('alert.deviceOnline') || '设备上线', color: '#52c41a', icon: '↑' },
    'device_offline': { label: t('alert.deviceOffline') || '设备离线', color: '#ff4d4f', icon: '↓' },
    'ota_available': { label: t('alert.otaAvailable') || 'OTA更新', color: '#1890ff', icon: '↑' },
    'command_sent': { label: t('alert.commandSent') || '命令下发', color: '#722ed1', icon: '→' },
    'command_success': { label: t('alert.commandSuccess') || '命令成功', color: '#52c41a', icon: '✓' },
    'command_failed': { label: t('alert.commandFailed') || '命令失败', color: '#ff4d4f', icon: '✗' },
    'command_queued': { label: t('alert.commandQueued') || '命令排队', color: '#faad14', icon: '…' },
    'alarm_cleared': { label: t('alert.alarmCleared'), color: '#52c41a', icon: '✓' },
    'device_alarm': { label: t('alert.deviceAlarm'), color: '#ff4d4f', icon: '!' },
  }

  // 获取设备列表（用于 SN 下拉）
  const { data: devicesData, error: devicesError } = useQuery({
    queryKey: queryKeys.devices.allDevices(),
    queryFn: () => deviceApi.getAll().then((r) => {
      const d = r.data?.data ?? r.data ?? {}
      return (Array.isArray(d) ? d : (d?.items ?? d?.list ?? [])) as any[]
    }),
    staleTime: 60_000,
  })

  // 获取电站列表（用于电站下拉）
  const { data: stationsData, error: stationsError } = useQuery({
    queryKey: queryKeys.stations.list(),
    queryFn: () => api.get('/stations', { params: { page_size: 100, all: true }, expectedDataShape: 'page' }).then((r) => {
      const d = r.data?.data ?? r.data ?? {}
      return (Array.isArray(d) ? d : (d?.items ?? d?.list ?? [])) as any[]
    }),
    staleTime: 60_000,
  })

  const deviceOptions = useMemo(() => {
    if (!Array.isArray(devicesData)) return []
    const filtered = stationId
      ? devicesData.filter((d: any) => d.station_id === stationId || d.stationId === stationId)
      : devicesData
    return filtered.map((d: any) => ({ label: d.sn, value: d.sn }))
  }, [devicesData, stationId])

  const stationOptions = useMemo(() => {
    if (!Array.isArray(stationsData)) return []
    return stationsData.map((s: any) => ({ label: s.name || `电站#${s.id}`, value: s.id }))
  }, [stationsData])

  const [notifyTypeFilter, setNotifyTypeFilter] = useState<string>()

  const commonFilters = {
    page, page_size: pageSize,
    station_id: stationId,
    keyword: keyword || undefined,
    startTime: dateRange?.[0]?.format('YYYY-MM-DD'),
    endTime: dateRange?.[1]?.format('YYYY-MM-DD'),
  }

  const queryParams = {
    ...commonFilters,
    status: statusFilter !== undefined ? Number(statusFilter) : undefined,
    alarmLevel: levelFilter !== undefined ? Number(levelFilter) : undefined,
  }

  const notifyQueryParams = {
    ...commonFilters,
    notify_type: notifyTypeFilter || undefined,
  }

  // 告警列表
  const { data: listRes, isLoading, refetch, error: listError } = useQuery({
    queryKey: queryKeys.alerts.list(queryParams),
    queryFn: () => alertApi.list(queryParams).then((r) => {
      const d = r.data?.data ?? r.data ?? {}
      return {
        items: (Array.isArray(d) ? d : (d?.items ?? d?.list ?? [])) as Alert[],
        total: d?.total ?? 0,
      }
    }),
    enabled: activeTab !== 'notification',
  })

  // 通知列表
  const { data: notifyRes, isLoading: notifyLoading, refetch: refetchNotify, error: notifyError } = useQuery({
    queryKey: ['notifications', 'list', notifyQueryParams],
    queryFn: () => notificationApi.list(notifyQueryParams).then((r) => {
      const d = r.data?.data ?? r.data ?? {}
      return {
        items: (Array.isArray(d) ? d : (d?.items ?? d?.list ?? [])) as NotificationItem[],
        total: d?.total ?? 0,
      }
    }),
    enabled: activeTab !== 'alarm',
  })

  // 告警统计
  const { data: stats, error: statsError } = useQuery({
    queryKey: queryKeys.alerts.stats(),
    queryFn: () => alertApi.getStats().then((r) => r.data?.data ?? { total: 0, unhandled: 0, handled: 0, critical: 0 }),
  })

  // 通知统计
  const { data: notifyStats, error: notifyStatsError } = useQuery({
    queryKey: ['notifications', 'stats'],
    queryFn: () => notificationApi.getStats().then((r) => r.data?.data ?? { total: 0, unread: 0 }),
  })

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: queryKeys.alerts.all })
    queryClient.invalidateQueries({ queryKey: ['notifications'] })
  }

  const handleMutation = useMutation({
    mutationFn: (id: number) => alertApi.handle(id),
    onSuccess: () => { message.success(t('alert.confirmSuccess')); invalidate() },
    onError: () => { message.error(t('alert.operationFailed')) },
  })

  const ignoreMutation = useMutation({
    mutationFn: (id: number) => alertApi.ignore(id),
    onSuccess: () => { message.success(t('alert.ignoreSuccess')); invalidate() },
    onError: () => { message.error(t('alert.operationFailed')) },
  })

  const deleteAlarmMutation = useMutation({
    mutationFn: (id: number) => alertApi.delete(id),
    onSuccess: () => { message.success(t('alert.deleteSuccess') || '已删除'); invalidate() },
    onError: () => { message.error(t('alert.operationFailed')) },
  })

  const deleteNotifyMutation = useMutation({
    mutationFn: (id: number) => notificationApi.delete(id),
    onSuccess: () => { message.success(t('alert.deleteSuccess') || '已删除'); invalidate() },
    onError: () => { message.error(t('alert.operationFailed')) },
  })

  const clearAllMutation = useMutation({
    mutationFn: async () => {
      await Promise.all([alertApi.clearAll(), notificationApi.clearAll()])
    },
    onSuccess: () => { message.success(t('alert.clearSuccess') || '已清除所有通知'); invalidate() },
    onError: () => { message.error(t('alert.operationFailed')) },
  })

  const traceQuery = useQuery({
    queryKey: ['protocol', 'alarm-events', traceSN, dateRange?.[0]?.toISOString(), dateRange?.[1]?.toISOString()],
    queryFn: () => protocolApi.getAlarmEvents(traceSN!, {
      page: 1,
      page_size: 200,
      start_time: dateRange?.[0]?.startOf('day').toISOString(),
      end_time: dateRange?.[1]?.endOf('day').toISOString(),
    }),
    enabled: Boolean(traceSN && traceOpen),
    retry: false,
  })

  const eventDetailQuery = useQuery({
    queryKey: ['protocol', 'alarm-event-detail', selectedEventID],
    queryFn: () => protocolApi.getAlarmEventDetail(selectedEventID!),
    enabled: Boolean(traceOpen && selectedEventID),
    retry: false,
  })

  const openTrace = (sn?: string) => {
    if (!sn) return
    setTraceSN(sn)
    setSelectedEventID(undefined)
    setTraceOpen(true)
  }

  const renderSnapshot = (snapshotType: 'before' | 'after') => {
    const snapshot = eventDetailQuery.data?.snapshots.find((item) => item.snapshot_type === snapshotType)
    const raw = snapshot?.raw_snapshot
    const missing = raw?.missing === true
    const label = snapshotType === 'before' ? t('alert.snapshotBefore') : t('alert.snapshotAfter')
    if (!snapshot) {
      return <Card size="small" title={label}><Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t('alert.snapshotNotCaptured')} /></Card>
    }
    if (missing) {
      return (
        <Card size="small" title={label}>
          <AntAlert type="warning" showIcon message={t('alert.snapshotMissing')} description={String(raw?.reason || t('alert.snapshotMissingUnknown'))} />
        </Card>
      )
    }
    const metric = (value: number | null | undefined, unit = '') => value == null ? '-' : `${value}${unit}`
    return (
      <Card size="small" title={label} extra={snapshot.captured_at ? formatInTimezone(snapshot.captured_at, timezone, 'YYYY-MM-DD HH:mm:ss') : undefined}>
        <Descriptions size="small" column={{ xs: 1, sm: 2, lg: 3 }} bordered>
          <Descriptions.Item label={t('alert.acVoltage')}>{metric(snapshot.ac_voltage, ' V')}</Descriptions.Item>
          <Descriptions.Item label={t('alert.acCurrent')}>{metric(snapshot.ac_current, ' A')}</Descriptions.Item>
          <Descriptions.Item label={t('alert.acPower')}>{metric(snapshot.ac_active_power, ' W')}</Descriptions.Item>
          <Descriptions.Item label={t('alert.frequency')}>{metric(snapshot.ac_frequency, ' Hz')}</Descriptions.Item>
          <Descriptions.Item label={t('alert.batterySoc')}>{metric(snapshot.battery_soc, '%')}</Descriptions.Item>
          <Descriptions.Item label={t('alert.batteryVoltage')}>{metric(snapshot.battery_voltage, ' V')}</Descriptions.Item>
          <Descriptions.Item label={t('alert.batteryCurrent')}>{metric(snapshot.battery_current, ' A')}</Descriptions.Item>
          <Descriptions.Item label={t('alert.batteryTemperature')}>{metric(snapshot.battery_temperature, ' °C')}</Descriptions.Item>
          <Descriptions.Item label={t('alert.internalTemperature')}>{metric(snapshot.internal_temperature, ' °C')}</Descriptions.Item>
          <Descriptions.Item label={t('alert.dcBusVoltage')}>{metric(snapshot.dc_bus_voltage, ' V')}</Descriptions.Item>
          <Descriptions.Item label={t('alert.workState')}>{metric(snapshot.work_state)}</Descriptions.Item>
          <Descriptions.Item label={t('alert.snapshotFaultCode')}>{metric(snapshot.fault_code)}</Descriptions.Item>
        </Descriptions>
      </Card>
    )
  }

  const traceColumns: ColumnsType<AlarmEvent> = [
    { title: t('alert.source'), dataIndex: 'source', width: 70 },
    { title: t('alert.faultCode'), dataIndex: 'code', width: 90 },
    {
      title: t('alert.alertLevel'), dataIndex: 'level', width: 90,
      render: (value: number) => <Tag color={value === 1 ? 'red' : value === 2 ? 'orange' : 'blue'}>{value}</Tag>,
    },
    {
      title: t('alert.lifecycleState'), dataIndex: 'state', width: 110,
      render: (value: string) => <Tag color={String(value) === '0' || value === 'recovered' ? 'success' : 'error'}>{String(value) === '0' ? 'recovered' : String(value) === '1' ? 'active' : value}</Tag>,
    },
    {
      title: t('alert.eventTime'), dataIndex: 'event_time', width: 170,
      render: (value: string) => value ? formatInTimezone(value, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('alert.receivedAt'), dataIndex: 'received_at', width: 170,
      render: (value: string) => value ? formatInTimezone(value, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('alert.activeAt'), dataIndex: 'active_at', width: 170,
      render: (value: string) => value ? formatInTimezone(value, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('alert.recoveredAt'), dataIndex: 'recovered_at', width: 170,
      render: (value: string) => value ? formatInTimezone(value, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('alert.dataHash'), dataIndex: 'data_hash', width: 190,
      render: (value: string) => <Tooltip title={value}><Text code copyable>{value ? `${value.slice(0, 12)}…` : '-'}</Text></Tooltip>,
    },
  ]

  // 告警表格列
  const alarmColumns: ColumnsType<any> = [
    {
      title: t('alert.type') || '类型', key: '_type', width: 80,
      render: () => <Tag color="red">{t('alert.alarmType') || '告警'}</Tag>,
    },
    { title: t('alert.deviceSN'), dataIndex: 'device_sn', key: 'device_sn', width: 140 },
    { title: t('alert.faultCode'), dataIndex: 'fault_code', key: 'fault_code', width: 80 },
    {
      title: t('alert.alertLevel'), dataIndex: 'alarm_level', key: 'alarm_level', width: 80,
      render: (level: number | string, record: any) => {
        const cfg = getAlarmLevelDisplay(record.fault_code, level)
        return <Tag color={cfg.color}>{cfg.i18nKey ? t(cfg.i18nKey) : cfg.label}</Tag>
      },
    },
    {
      title: t('alert.faultInfo'), dataIndex: 'fault_message', key: 'fault_message', ellipsis: true,
      render: (message: string, record: any) => {
        const key = getAlarmMessageI18nKey(record.fault_code)
        return key ? t(key) : message
      },
    },
    {
      title: t('alert.status'), dataIndex: 'status', key: 'status', width: 80,
      render: (status: number | string) => {
        const key = typeof status === 'number' ? String(status) : status
        const cfg = ALERT_STATUS_MAP[key] || { label: String(status), color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: t('alert.occurTime'), dataIndex: 'occurred_at', key: 'occurred_at', width: 170,
      render: (val: string) => val ? formatInTimezone(val, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('common.operation'), key: 'action', width: 200,
      render: (_: any, record: any) => (
        <Space>
          {String(record.status) === '0' && (
            <>
              <Button type="link" size="small" icon={<CheckOutlined />}
                onClick={() => handleMutation.mutate(record.id)}
              >{t('alert.confirmProcess')}</Button>
              <Button type="link" size="small" icon={<StopOutlined />}
                onClick={() => ignoreMutation.mutate(record.id)}
              >{t('alert.ignore')}</Button>
            </>
          )}
          <Button type="link" size="small" onClick={() => openTrace(record.device_sn)}>{t('alert.trace')}</Button>
          <Button type="link" size="small" danger icon={<DeleteOutlined />}
            onClick={() => deleteAlarmMutation.mutate(record.id)}
          >{t('alert.delete') || '删除'}</Button>
        </Space>
      ),
    },
  ]

  // 通知表格列
  const notifyColumns: ColumnsType<any> = [
    {
      title: t('alert.type') || '类型', key: '_type', width: 80,
      render: () => <Tag color="blue">{t('alert.notifyType') || '通知'}</Tag>,
    },
    { title: t('alert.deviceSN'), dataIndex: 'device_sn', key: 'device_sn', width: 140 },
    {
      title: t('alert.notifyType') || '通知类型', dataIndex: 'notify_type', key: 'notify_type', width: 100,
      render: (val: string) => {
        const cfg = NOTIFY_TYPE_MAP[val] || { label: val, color: '#d9d9d9', icon: '' }
        return <Tag color={cfg.color}>{cfg.icon} {cfg.label}</Tag>
      },
    },
    { title: t('alert.columnTitle') || '标题', dataIndex: 'title', key: 'title', width: 120 },
    { title: t('alert.content') || '内容', dataIndex: 'content', key: 'content', ellipsis: true },
    {
      title: t('alert.occurTime'), dataIndex: 'created_at', key: 'created_at', width: 170,
      render: (val: string) => val ? formatInTimezone(val, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('common.operation'), key: 'action', width: 80,
      render: (_: any, record: any) => (
        <Button type="link" size="small" danger icon={<DeleteOutlined />}
          onClick={() => deleteNotifyMutation.mutate(record.id)}
        >{t('alert.delete') || '删除'}</Button>
      ),
    },
  ]

  // 合并数据（全部tab）
  const mergedData = useMemo(() => {
    const alarmItems = Array.isArray(listRes?.items) ? listRes.items : []
    const notifyItems = Array.isArray(notifyRes?.items) ? notifyRes.items : []
    if (activeTab === 'alarm') {
      return alarmItems.map((item: any) => ({ ...item, _type: 'alarm', _sortTime: item.occurred_at }))
    }
    if (activeTab === 'notification') {
      return notifyItems.map((item: any) => ({ ...item, _type: 'notification', _sortTime: item.created_at }))
    }
    // 全部 - 合并排序
    const alarms = alarmItems.map((item: any) => ({ ...item, _type: 'alarm', _sortTime: item.occurred_at }))
    const notifications = notifyItems.map((item: any) => ({ ...item, _type: 'notification', _sortTime: item.created_at }))
    return [...alarms, ...notifications].sort((a, b) =>
      new Date(b._sortTime).getTime() - new Date(a._sortTime).getTime()
    )
  }, [listRes, notifyRes, activeTab])

  // 合并列（全部tab）
  const mergedColumns: ColumnsType<any> = [
    {
      title: t('alert.type') || '类型', key: '_type', width: 80,
      render: (_: any, record: any) => {
        if (record._type === 'notification') {
          const cfg = NOTIFY_TYPE_MAP[record.notify_type] || { label: record.notify_type, color: '#d9d9d9', icon: '' }
          return <Tag color={cfg.color}>{cfg.icon} {cfg.label}</Tag>
        }
        return <Tag color="red">{t('alert.alarmType') || '告警'}</Tag>
      },
    },
    { title: t('alert.deviceSN'), dataIndex: 'device_sn', key: 'device_sn', width: 140 },
    {
      title: t('alert.detail') || '详情', key: 'detail', ellipsis: true,
      render: (_: any, record: any) => {
        if (record._type === 'notification') {
          return record.content || record.title
        }
        const cfg = getAlarmLevelDisplay(record.fault_code, record.alarm_level)
        const messageKey = getAlarmMessageI18nKey(record.fault_code)
        return <><Tag color={cfg.color} style={{ marginRight: 4 }}>{cfg.i18nKey ? t(cfg.i18nKey) : cfg.label}</Tag>{messageKey ? t(messageKey) : record.fault_message}</>
      },
    },
    {
      title: t('alert.status'), key: 'status', width: 80,
      render: (_: any, record: any) => {
        if (record._type === 'notification') {
          return <Tag color="blue">{t('alert.notification') || '通知'}</Tag>
        }
        const key = typeof record.status === 'number' ? String(record.status) : record.status
        const cfg = ALERT_STATUS_MAP[key] || { label: String(record.status), color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: t('alert.occurTime'), key: 'time', width: 170,
      render: (_: any, record: any) => {
        const val = record._type === 'notification' ? record.created_at : record.occurred_at
        return val ? formatInTimezone(val, timezone, 'YYYY-MM-DD HH:mm:ss') : '-'
      },
    },
    {
      title: t('common.operation'), key: 'action', width: 200,
      render: (_: any, record: any) => (
        <Space>
          {record._type === 'alarm' && String(record.status) === '0' && (
            <>
              <Button type="link" size="small" icon={<CheckOutlined />}
                onClick={() => handleMutation.mutate(record.id)}
              >{t('alert.confirmProcess')}</Button>
              <Button type="link" size="small" icon={<StopOutlined />}
                onClick={() => ignoreMutation.mutate(record.id)}
              >{t('alert.ignore')}</Button>
            </>
          )}
          {record._type === 'alarm' && (
            <Button type="link" size="small" onClick={() => openTrace(record.device_sn)}>{t('alert.trace')}</Button>
          )}
          <Button type="link" size="small" danger icon={<DeleteOutlined />}
            onClick={() => record._type === 'notification'
              ? deleteNotifyMutation.mutate(record.id)
              : deleteAlarmMutation.mutate(record.id)
            }
          >{t('alert.delete') || '删除'}</Button>
        </Space>
      ),
    },
  ]

  const getColumns = () => {
    if (activeTab === 'alarm') return alarmColumns
    if (activeTab === 'notification') return notifyColumns
    return mergedColumns
  }

  const isLoadingData = activeTab === 'notification' ? notifyLoading : isLoading
  const total = activeTab === 'notification' ? (notifyRes?.total ?? 0) : (listRes?.total ?? 0)

  return (
    <div>
      <Title level={4} style={{ marginBottom: 16 }}>
        <AlertOutlined style={{ marginRight: 8 }} />{t('alert.title')}
      </Title>
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={4}>
          <StatisticCard size="small" title={t('alert.total')} value={(stats?.total ?? 0) + (notifyStats?.total ?? 0)} />
        </Col>
        <Col span={4}>
          <StatisticCard size="small" title={t('alert.unprocessed')} value={stats?.unhandled ?? 0} valueStyle={{ color: '#ff4d4f' }} />
        </Col>
        <Col span={4}>
          <StatisticCard size="small" title={t('alert.processed')} value={stats?.handled ?? 0} valueStyle={{ color: '#52c41a' }} />
        </Col>
        <Col span={4}>
          <StatisticCard size="small" title={t('alert.criticalCount')} value={stats?.critical ?? 0} valueStyle={{ color: '#ff4d4f' }} />
        </Col>
        <Col span={4}>
          <StatisticCard size="small" title={t('alert.notifyCount') || '通知数'} value={notifyStats?.total ?? 0} prefix={<BellOutlined />} />
        </Col>
        <Col span={4}>
          <StatisticCard size="small" title={t('alert.unreadNotify') || '未读通知'} value={notifyStats?.unread ?? 0} valueStyle={{ color: '#1890ff' }} />
        </Col>
      </Row>

      <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        {(devicesError || stationsError) && (
          <AntAlert
            type="warning"
            showIcon
            message={getApiErrorMessage(devicesError || stationsError)}
            style={{ marginBottom: 12 }}
          />
        )}
        <Row gutter={16} align="middle">
          <Col>
            <Select allowClear showSearch placeholder={t('alert.stationFilter') || '选择电站'} style={{ width: 160 }}
              value={stationId} onChange={(val) => { setStationId(val); setKeyword(undefined); setPage(1) }}
              options={stationOptions}
              filterOption={(input, option) => (option?.label as string)?.toLowerCase().includes(input.toLowerCase())}
            />
          </Col>
          <Col>
            <Select allowClear showSearch placeholder={t('alert.searchPlaceholder') || '搜索SN'} style={{ width: 200 }}
              value={keyword} onChange={(val) => { setKeyword(val); setPage(1) }}
              options={deviceOptions}
              filterOption={(input, option) => (option?.label as string)?.toLowerCase().includes(input.toLowerCase())}
            />
          </Col>
          {activeTab !== 'notification' && (
            <>
              <Col>
                <Select allowClear placeholder={t('alert.filterStatus')} style={{ width: 120 }}
                  value={statusFilter} onChange={(val) => { setStatusFilter(val); setPage(1) }}
                  options={[{ label: t('alert.unprocessed'), value: '0' }, { label: t('alert.processed'), value: '1' }, { label: t('alert.ignored'), value: '2' }]}
                />
              </Col>
              <Col>
                <Select allowClear placeholder={t('alert.filterLevel')} style={{ width: 120 }}
                  value={levelFilter} onChange={(val) => { setLevelFilter(val); setPage(1) }}
                  options={[{ label: t('alert.critical'), value: '1' }, { label: t('alert.warningLevel'), value: '2' }, { label: t('alert.infoLevel'), value: '3' }]}
                />
              </Col>
            </>
          )}
          {activeTab === 'notification' && (
            <Col>
              <Select allowClear placeholder={t('alert.notifyType') || '通知类型'} style={{ width: 120 }}
                value={notifyTypeFilter} onChange={(val) => { setNotifyTypeFilter(val); setPage(1) }}
                options={[
                  { label: t('alert.deviceOnline') || '设备上线', value: 'device_online' },
                  { label: t('alert.deviceOffline') || '设备离线', value: 'device_offline' },
                  { label: t('alert.otaAvailable') || 'OTA更新', value: 'ota_available' },
                  { label: t('alert.commandSent') || '命令下发', value: 'command_sent' },
                  { label: t('alert.commandSuccess') || '命令成功', value: 'command_success' },
                  { label: t('alert.commandFailed') || '命令失败', value: 'command_failed' },
                  { label: t('alert.commandQueued') || '命令排队', value: 'command_queued' },
                ]}
              />
            </Col>
          )}
          <Col>
            <RangePicker value={dateRange as any} onChange={(vals) => { setDateRange(vals as any); setPage(1) }} />
          </Col>
          <Col>
            <Button icon={<ReloadOutlined />} onClick={() => { refetch(); refetchNotify() }}>{t('common.refresh')}</Button>
          </Col>
          <Col>
            <Button danger icon={<ClearOutlined />}
              onClick={() => clearAllMutation.mutate()}
              loading={clearAllMutation.isPending}
            >{t('alert.clearAll') || '清除通知记录'}</Button>
          </Col>
        </Row>
      </Card>

      <Card bordered={false} style={{ borderRadius: 12 }}>
        <Tabs activeKey={activeTab} onChange={(key) => { setActiveTab(key); setPage(1) }}
          items={[
            { key: 'all', label: t('alert.tabAll') || '全部' },
            { key: 'alarm', label: t('alert.tabAlarm') || '告警' },
            { key: 'notification', label: t('alert.tabNotification') || '通知' },
          ]}
        />
        {((activeTab !== 'notification' && listError) || (activeTab !== 'alarm' && notifyError)) && (
          <AntAlert
            type="error"
            showIcon
            message={getApiErrorMessage(activeTab === 'notification' ? notifyError : listError || notifyError)}
            style={{ marginBottom: 12 }}
          />
        )}
        {(statsError || notifyStatsError) && (
          <AntAlert
            type="error"
            showIcon
            message={getApiErrorMessage(statsError || notifyStatsError)}
            style={{ marginBottom: 12 }}
          />
        )}
        <Table
          rowKey={(record) => `${record._type || 'alarm'}-${record.id}`}
          columns={getColumns()}
          dataSource={mergedData}
          loading={isLoadingData}
          size="small"
          locale={{ emptyText: <Empty description={t('common.noData')} /> }}
          pagination={{
            current: page, pageSize, total, showSizeChanger: true,
            showTotal: (total) => t('common.total', { total }),
            onChange: (p, ps) => { setPage(p); setPageSize(ps) },
          }}
        />
      </Card>
      <Drawer
        title={`${t('alert.traceTitle')}${traceSN ? ` · ${traceSN}` : ''}`}
        width="min(1100px, 94vw)"
        open={traceOpen}
        onClose={() => setTraceOpen(false)}
      >
        <Text type="secondary">{t('alert.traceHint')}</Text>
        {traceQuery.isError && (
          <AntAlert type="error" showIcon message={t('alert.traceLoadFailed')} description={getApiErrorMessage(traceQuery.error)} style={{ margin: '16px 0' }} />
        )}
        <Table
          style={{ marginTop: 16 }}
          rowKey={(event) => event.id}
          columns={traceColumns}
          dataSource={traceQuery.data?.items ?? []}
          loading={traceQuery.isLoading}
          scroll={{ x: 1350 }}
          size="small"
          locale={{ emptyText: <Empty description={t('alert.noTraceData')} /> }}
          pagination={{ pageSize: 20, showSizeChanger: true }}
          rowSelection={{
            type: 'radio',
            selectedRowKeys: selectedEventID ? [selectedEventID] : [],
            onChange: (keys) => setSelectedEventID(Number(keys[0])),
          }}
          onRow={(event) => ({ onClick: () => setSelectedEventID(event.id), style: { cursor: 'pointer' } })}
        />
        {selectedEventID && (
          <Card title={`${t('alert.snapshotTitle')} #${selectedEventID}`} style={{ marginTop: 16 }} loading={eventDetailQuery.isLoading}>
            {eventDetailQuery.isError && (
              <AntAlert
                type="error"
                showIcon
                message={t('alert.snapshotLoadFailed')}
                description={getApiErrorMessage(eventDetailQuery.error)}
              />
            )}
            {eventDetailQuery.data && (
              <Space direction="vertical" size="middle" style={{ width: '100%' }}>
                <Text type="secondary">{t('alert.snapshotHint')}</Text>
                <Row gutter={[16, 16]}>
                  <Col xs={24} xl={12}>{renderSnapshot('before')}</Col>
                  <Col xs={24} xl={12}>{renderSnapshot('after')}</Col>
                </Row>
              </Space>
            )}
          </Card>
        )}
      </Drawer>
    </div>
  )
}

export default AlertsPage
