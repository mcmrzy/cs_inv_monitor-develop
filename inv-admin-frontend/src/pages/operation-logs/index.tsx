import { useState, useCallback, useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Row, Col, Card, Table, Tabs, DatePicker, Select, Button, Tag,
  Space, Typography, Timeline, Input, App,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  ReloadOutlined, DownloadOutlined, FileTextOutlined,
  AlertOutlined, ToolOutlined, HistoryOutlined, CodeOutlined,
  SearchOutlined,
} from '@ant-design/icons'
import dayjs from 'dayjs'
import { adminApi, type AuditLog } from '@/services/adminApi'
import { alertApi } from '@/services/alertApi'
import { commandApi } from '@/services/commandApi'
import { ALARM_LEVEL_MAP } from '@/utils/constants'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'

const { Title, Text } = Typography
const { RangePicker } = DatePicker

/* ==================== 类型定义 ==================== */

interface AlarmRecord {
  id: string | number
  device_sn: string
  alarm_level: number | string
  fault_code: string
  fault_message: string
  occurred_at: string
  status: string
  [key: string]: any
}

interface CommandRecord {
  id: number
  device_sn: string
  command_name: string
  command_label: string
  params: any
  req_id: string
  status: string
  result_message: string
  executed_by: number
  executed_by_name?: string
  ip_address: string
  retry_count: number
  created_at: string
  completed_at: string
  [key: string]: any
}

interface SystemEvent {
  id: number
  action: string
  resource: string
  resourceId: string
  details: string
  username: string
  ipAddress: string
  createdAt: string
}

/* ==================== 常量 ==================== */

const ACTION_COLORS: Record<string, string> = {
  create: 'green',
  update: 'blue',
  delete: 'red',
  login: 'cyan',
  logout: 'orange',
  import: 'purple',
  export: 'geekblue',
  bind: 'lime',
  unbind: 'volcano',
  command: 'magenta',
  approve: 'green',
  reject: 'red',
}

const TAB_KEY_MAP: Record<string, string> = {
  all: 'operation',
  operation: 'operation',
  alarm: 'alarm',
  system: 'system',
  command: 'command',
}

/* ==================== 主组件 ==================== */

const OperationLogsPage: React.FC = () => {
  const { message } = App.useApp()
  const { t } = useTranslation()

  const ACTION_LABELS: Record<string, string> = {
    create: t('logs.createAction'),
    update: t('logs.updateAction'),
    delete: t('logs.deleteAction'),
    login: t('logs.loginAction'),
    logout: t('logs.logoutAction'),
    import: t('logs.importAction'),
    export: t('logs.exportAction'),
    bind: t('logs.bindAction'),
    unbind: t('logs.unbindAction'),
    command: t('logs.commandLabel'),
    approve: t('logs.approveAction'),
    reject: t('logs.rejectAction'),
  }

  const COMMAND_STATUS_MAP: Record<string, { label: string; color: string }> = {
    pending: { label: t('logs.waiting'), color: 'default' },
    sent: { label: t('logs.sent'), color: 'processing' },
    ack_received: { label: t('logs.deviceConfirmed'), color: 'blue' },
    success: { label: t('logs.success'), color: 'green' },
    failed: { label: t('logs.failed'), color: 'red' },
    timeout: { label: t('logs.timeout'), color: 'orange' },
  }

  const ALARM_STATUS_MAP: Record<string, { label: string; color: string }> = {
    '0': { label: t('logs.unprocessed'), color: 'red' },
    '1': { label: t('logs.processed'), color: 'green' },
    '2': { label: t('logs.ignored'), color: 'default' },
    unhandled: { label: t('logs.unprocessed'), color: 'red' },
    handled: { label: t('logs.processed'), color: 'green' },
    ignored: { label: t('logs.ignored'), color: 'default' },
  }

  const LOG_TYPE_OPTIONS = [
    { label: t('logs.all'), value: 'all' },
    { label: t('logs.operationLog'), value: 'operation' },
    { label: t('logs.alertLog'), value: 'alarm' },
    { label: t('logs.systemLog'), value: 'system' },
    { label: t('logs.commandLog'), value: 'command' },
  ]

  // 全局过滤
  const [activeTab, setActiveTab] = useState('operation')
  const [dateRange, setDateRange] = useState<[dayjs.Dayjs, dayjs.Dayjs] | null>(null)
  const [logType, setLogType] = useState<string>('all')
  const [userFilter, setUserFilter] = useState<string>('')
  const [deviceSnFilter, setDeviceSnFilter] = useState<string>('')

  // 同步日志类型下拉到 Tab
  useEffect(() => {
    if (logType !== 'all') {
      setActiveTab(TAB_KEY_MAP[logType] || 'operation')
    }
  }, [logType])

  /* ---------- 公共查询参数 ---------- */

  const buildTimeParams = useCallback(() => {
    const params: any = {}
    if (dateRange) {
      params.startTime = dateRange[0].toISOString()
      params.endTime = dateRange[1].toISOString()
    }
    return params
  }, [dateRange])

  /* ---------- 导出CSV通用函数 ---------- */

  const exportToCsv = (rows: Record<string, any>[], filename: string) => {
    if (rows.length === 0) {
      message.warning(t('logs.noDataToExport'))
      return
    }
    const headers = Object.keys(rows[0])
    const csvContent = [
      '\uFEFF' + headers.join(','),
      ...rows.map((row) =>
        headers.map((h) => {
          const val = row[h]
          const str = val == null ? '' : String(val).replace(/"/g, '""')
          return `"${str}"`
        }).join(',')
      ),
    ].join('\n')
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' })
    const url = window.URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = `${filename}_${dayjs().format('YYYYMMDD_HHmmss')}.csv`
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    window.URL.revokeObjectURL(url)
    message.success(t('logs.exportSuccess'))
  }

  /* ============================================================
   *  Tab 1: 操作记录 (Audit Logs)
   * ============================================================ */

  const [auditPage, setAuditPage] = useState(1)
  const [auditPageSize, setAuditPageSize] = useState(20)

  const auditQueryParams = {
    page: auditPage,
    pageSize: auditPageSize,
    ...buildTimeParams(),
    ...(userFilter ? { username: userFilter } : {}),
    ...(deviceSnFilter ? { keyword: deviceSnFilter } : {}),
  }

  const { data: auditResult, isLoading: auditLoading } = useQuery({
    queryKey: queryKeys.admin.auditLogs(auditQueryParams),
    queryFn: () => adminApi.getAuditLogs(auditQueryParams).then((res) => {
      const d = res.data?.data ?? res.data ?? {}
      return {
        items: Array.isArray(d) ? d : (d?.items ?? d?.list ?? []) as AuditLog[],
        total: d?.total ?? 0,
      }
    }),
    enabled: activeTab === 'operation',
  })

  const auditData = auditResult?.items ?? []
  const auditTotal = auditResult?.total ?? 0

  const handleExportAudit = async () => {
    try {
      const params: any = { ...buildTimeParams(), pageSize: 10000 }
      if (userFilter) params.username = userFilter
      const res = await adminApi.exportAuditLogs(params)
      const blob = res.data as Blob
      const url = window.URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = url
      link.download = `audit_logs_${Date.now()}.csv`
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)
      window.URL.revokeObjectURL(url)
      message.success(t('logs.exportSuccess'))
    } catch {
      exportToCsv(
        auditData.map((r) => ({
          [t('logs.time')]: dayjs(r.createdAt).format('YYYY-MM-DD HH:mm:ss'),
          [t('logs.user')]: r.username,
          [t('logs.operation')]: r.action,
          [t('logs.resource')]: r.resource,
          [t('logs.detail')]: r.details,
          IP: r.ipAddress,
        })),
        'audit_logs'
      )
    }
  }

  const auditColumns: ColumnsType<AuditLog> = [
    {
      title: t('logs.time'),
      dataIndex: 'createdAt',
      key: 'createdAt',
      width: 170,
      render: (v: string) => v ? dayjs(v).format('YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('logs.user'),
      dataIndex: 'username',
      key: 'username',
      width: 120,
      render: (v: string) => v || '-',
    },
    {
      title: t('logs.operation'),
      dataIndex: 'action',
      key: 'action',
      width: 100,
      render: (action: string) => {
        const color = ACTION_COLORS[action] || 'default'
        const label = ACTION_LABELS[action] || action
        return <Tag color={color}>{label}</Tag>
      },
    },
    {
      title: t('logs.resource'),
      dataIndex: 'resource',
      key: 'resource',
      width: 140,
      ellipsis: true,
      render: (v: string) => v || '-',
    },
    {
      title: t('logs.detail'),
      dataIndex: 'details',
      key: 'details',
      ellipsis: true,
      render: (v: string) => v || '-',
    },
    {
      title: t('logs.ipAddress'),
      dataIndex: 'ipAddress',
      key: 'ipAddress',
      width: 140,
      render: (v: string) => <Text code>{v || '-'}</Text>,
    },
  ]

  /* ============================================================
   *  Tab 2: 告警日志
   * ============================================================ */

  const [alarmPage, setAlarmPage] = useState(1)
  const [alarmPageSize, setAlarmPageSize] = useState(20)

  const alarmQueryParams = {
    page: alarmPage,
    pageSize: alarmPageSize,
    ...buildTimeParams(),
    ...(deviceSnFilter ? { keyword: deviceSnFilter } : {}),
  }

  const { data: alarmResult, isLoading: alarmLoading } = useQuery({
    queryKey: queryKeys.operationLogs.alarmRecords(alarmQueryParams),
    queryFn: () => alertApi.list(alarmQueryParams).then((res) => {
      const d = res.data?.data ?? res.data ?? {}
      return {
        items: Array.isArray(d) ? d : (d?.items ?? d?.list ?? []) as AlarmRecord[],
        total: d?.total ?? 0,
      }
    }),
    enabled: activeTab === 'alarm',
  })

  const alarmData = alarmResult?.items ?? []
  const alarmTotal = alarmResult?.total ?? 0

  const handleExportAlarms = () => {
    exportToCsv(
      alarmData.map((r) => ({
        [t('logs.time')]: r.occurred_at ? dayjs(r.occurred_at).format('YYYY-MM-DD HH:mm:ss') : '',
        [t('logs.deviceSN')]: r.device_sn,
        [t('logs.alertLevel')]: typeof r.alarm_level === 'number' ? (ALARM_LEVEL_MAP[r.alarm_level]?.label || r.alarm_level) : r.alarm_level,
        [t('logs.faultCode')]: r.fault_code,
        [t('logs.faultInfo')]: r.fault_message,
        [t('logs.status')]: ALARM_STATUS_MAP[String(r.status)]?.label || r.status,
      })),
      'alarm_logs'
    )
  }

  const alarmColumns: ColumnsType<AlarmRecord> = [
    {
      title: t('logs.time'),
      dataIndex: 'occurred_at',
      key: 'occurred_at',
      width: 170,
      render: (v: string) => v ? dayjs(v).format('YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('logs.deviceSN'),
      dataIndex: 'device_sn',
      key: 'device_sn',
      width: 150,
      render: (v: string) => <Text code>{v || '-'}</Text>,
    },
    {
      title: t('logs.alertLevel'),
      dataIndex: 'alarm_level',
      key: 'alarm_level',
      width: 90,
      render: (level: number | string) => {
        const key = typeof level === 'number' ? String(level) : level
        const cfg = ALARM_LEVEL_MAP[key] || { label: String(level), color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: t('logs.faultCode'),
      dataIndex: 'fault_code',
      key: 'fault_code',
      width: 100,
      render: (v: string) => v || '-',
    },
    {
      title: t('logs.faultInfo'),
      dataIndex: 'fault_message',
      key: 'fault_message',
      ellipsis: true,
      render: (v: string) => v || '-',
    },
    {
      title: t('logs.status'),
      dataIndex: 'status',
      key: 'status',
      width: 90,
      render: (status: number | string) => {
        const key = typeof status === 'number' ? String(status) : status
        const cfg = ALARM_STATUS_MAP[key] || { label: String(status), color: 'default' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
  ]

  /* ============================================================
   *  Tab 3: 命令日志
   * ============================================================ */

  const [cmdPage, setCmdPage] = useState(1)
  const [cmdPageSize, setCmdPageSize] = useState(20)

  const cmdQueryParams = {
    page: cmdPage,
    pageSize: cmdPageSize,
    ...buildTimeParams(),
    ...(deviceSnFilter ? { keyword: deviceSnFilter } : {}),
  }

  const { data: cmdResult, isLoading: cmdLoading } = useQuery({
    queryKey: queryKeys.operationLogs.commandRecords(cmdQueryParams),
    queryFn: async () => {
      const res = await adminApi.getAuditLogs({ ...cmdQueryParams, action: 'command' })
      const d = res.data?.data ?? res.data ?? {}
      const items = Array.isArray(d) ? d : (d?.items ?? d?.list ?? [])
      return {
        items: items.map((item: any) => ({
          id: item.id,
          device_sn: item.resourceId || item.resource || '-',
          command_name: item.action,
          command_label: item.action,
          params: {},
          req_id: '',
          status: 'success',
          result_message: item.details || '',
          executed_by: item.userId,
          executed_by_name: item.username,
          ip_address: item.ipAddress,
          retry_count: 0,
          created_at: item.createdAt,
          completed_at: item.createdAt,
        })),
        total: d?.total ?? 0,
      }
    },
    enabled: activeTab === 'command',
  })

  const cmdData = cmdResult?.items ?? []
  const cmdTotal = cmdResult?.total ?? 0

  const handleExportCommands = () => {
    exportToCsv(
      cmdData.map((r: CommandRecord) => ({
        [t('logs.time')]: dayjs(r.created_at).format('YYYY-MM-DD HH:mm:ss'),
        [t('logs.deviceSN')]: r.device_sn,
        [t('logs.command')]: r.command_label || r.command_name,
        [t('logs.status')]: COMMAND_STATUS_MAP[r.status]?.label || r.status,
        [t('logs.result')]: r.result_message,
        [t('logs.operator')]: r.executed_by_name || String(r.executed_by),
      })),
      'command_logs'
    )
  }

  const cmdColumns: ColumnsType<CommandRecord> = [
    {
      title: t('logs.time'),
      dataIndex: 'created_at',
      key: 'created_at',
      width: 170,
      render: (v: string) => v ? dayjs(v).format('YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('logs.deviceSN'),
      dataIndex: 'device_sn',
      key: 'device_sn',
      width: 150,
      render: (v: string) => <Text code>{v || '-'}</Text>,
    },
    {
      title: t('logs.command'),
      key: 'command',
      width: 150,
      render: (_: any, record: CommandRecord) => record.command_label || record.command_name || '-',
    },
    {
      title: t('logs.status'),
      dataIndex: 'status',
      key: 'status',
      width: 110,
      render: (status: string) => {
        const cfg = COMMAND_STATUS_MAP[status] || { label: status, color: 'default' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: t('logs.result'),
      dataIndex: 'result_message',
      key: 'result_message',
      ellipsis: true,
      render: (v: string) => v || '-',
    },
    {
      title: t('logs.operator'),
      key: 'operator',
      width: 120,
      render: (_: any, record: CommandRecord) => record.executed_by_name || String(record.executed_by || '-'),
    },
  ]

  /* ============================================================
   *  Tab 4: 系统日志 (Timeline)
   * ============================================================ */

  const [sysPage, setSysPage] = useState(1)
  const [sysPageSize, setSysPageSize] = useState(20)

  const sysQueryParams = {
    page: sysPage,
    pageSize: sysPageSize,
    ...buildTimeParams(),
    ...(userFilter ? { username: userFilter } : {}),
  }

  const { data: sysResult, isLoading: sysLoading, refetch: refetchSystemLogs } = useQuery({
    queryKey: queryKeys.operationLogs.systemEvents(sysQueryParams),
    queryFn: () => adminApi.getAuditLogs(sysQueryParams).then((res) => {
      const d = res.data?.data ?? res.data ?? {}
      const items = Array.isArray(d) ? d : (d?.items ?? d?.list ?? [])
      return {
        items: items as SystemEvent[],
        total: d?.total ?? 0,
      }
    }),
    enabled: activeTab === 'system',
  })

  const sysData = sysResult?.items ?? []
  const sysTotal = sysResult?.total ?? 0

  const handleExportSystem = () => {
    exportToCsv(
      sysData.map((r) => ({
        [t('logs.time')]: dayjs(r.createdAt).format('YYYY-MM-DD HH:mm:ss'),
        [t('logs.user')]: r.username,
        [t('logs.operation')]: r.action,
        [t('logs.resource')]: r.resource,
        [t('logs.detail')]: r.details,
        IP: r.ipAddress,
      })),
      'system_logs'
    )
  }

  const sysTableColumns: ColumnsType<SystemEvent> = [
    {
      title: t('logs.time'),
      dataIndex: 'createdAt',
      key: 'createdAt',
      width: 170,
      render: (v: string) => v ? dayjs(v).format('YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('logs.user'),
      dataIndex: 'username',
      key: 'username',
      width: 120,
      render: (v: string) => v || '-',
    },
    {
      title: t('logs.operation'),
      dataIndex: 'action',
      key: 'action',
      width: 100,
      render: (action: string) => {
        const color = ACTION_COLORS[action] || 'default'
        const label = ACTION_LABELS[action] || action
        return <Tag color={color}>{label}</Tag>
      },
    },
    {
      title: t('logs.resource'),
      dataIndex: 'resource',
      key: 'resource',
      width: 140,
      ellipsis: true,
    },
    {
      title: t('logs.detail'),
      dataIndex: 'details',
      key: 'details',
      ellipsis: true,
    },
    {
      title: 'IP',
      dataIndex: 'ipAddress',
      key: 'ipAddress',
      width: 130,
      render: (v: string) => <Text code>{v || '-'}</Text>,
    },
  ]

  /* ---------- 渲染时间线视图 ---------- */

  const renderSystemTimeline = () => {
    if (sysLoading) return <div style={{ padding: 40, textAlign: 'center' }}>{t('common.loading')}</div>
    if (sysData.length === 0) return <div style={{ padding: 40, textAlign: 'center', color: '#999' }}>{t('logs.noSystemLogs')}</div>

    return (
      <Timeline
        items={sysData.map((event) => {
          const color = ACTION_COLORS[event.action] || 'gray'
          return {
            color,
            children: (
              <div>
                <div style={{ marginBottom: 4 }}>
                  <Tag color={color}>{ACTION_LABELS[event.action] || event.action}</Tag>
                  <Text type="secondary" style={{ fontSize: 12 }}>
                    {event.username && <span>{event.username} · </span>}
                    {dayjs(event.createdAt).format('YYYY-MM-DD HH:mm:ss')}
                  </Text>
                </div>
                <Text>{event.details || `${event.resource}${event.resourceId ? ` #${event.resourceId}` : ''}`}</Text>
                {event.ipAddress && (
                  <div>
                    <Text type="secondary" style={{ fontSize: 12 }}>
                      IP: {event.ipAddress}
                    </Text>
                  </div>
                )}
              </div>
            ),
          }
        })}
      />
    )
  }

  /* ============================================================
   *  Tab 配置
   * ============================================================ */

  const tabItems = [
    {
      key: 'operation',
      label: <span><FileTextOutlined /> {t('logs.operationLog')}</span>,
      children: (
        <>
          <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }} size="small">
            <Row justify="end">
              <Button icon={<DownloadOutlined />} size="small" onClick={handleExportAudit}>
                {t('logs.exportCSV')}
              </Button>
            </Row>
          </Card>
          <Table<AuditLog>
            rowKey="id"
            columns={auditColumns}
            dataSource={auditData}
            loading={auditLoading}
            pagination={{
              current: auditPage,
              pageSize: auditPageSize,
              total: auditTotal,
              showSizeChanger: true,
              pageSizeOptions: ['10', '20', '50', '100'],
              showTotal: (total) => t('common.total', { total }),
              onChange: (p, ps) => { setAuditPage(p); setAuditPageSize(ps) },
            }}
            scroll={{ x: 800 }}
            size="small"
          />
        </>
      ),
    },
    {
      key: 'alarm',
      label: <span><AlertOutlined /> {t('logs.alertLog')}</span>,
      children: (
        <>
          <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }} size="small">
            <Row justify="end">
              <Button icon={<DownloadOutlined />} size="small" onClick={handleExportAlarms}>
                {t('logs.exportCSV')}
              </Button>
            </Row>
          </Card>
          <Table<AlarmRecord>
            rowKey="id"
            columns={alarmColumns}
            dataSource={alarmData}
            loading={alarmLoading}
            rowClassName={(record: any) =>
              String(record.alarm_level) === '1' ? 'alert-row-critical' : ''
            }
            pagination={{
              current: alarmPage,
              pageSize: alarmPageSize,
              total: alarmTotal,
              showSizeChanger: true,
              pageSizeOptions: ['10', '20', '50', '100'],
              showTotal: (total) => t('common.total', { total }),
              onChange: (p, ps) => { setAlarmPage(p); setAlarmPageSize(ps) },
            }}
            scroll={{ x: 800 }}
            size="small"
          />
        </>
      ),
    },
    {
      key: 'command',
      label: <span><CodeOutlined /> {t('logs.commandLog')}</span>,
      children: (
        <>
          <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }} size="small">
            <Row justify="end">
              <Button icon={<DownloadOutlined />} size="small" onClick={handleExportCommands}>
                {t('logs.exportCSV')}
              </Button>
            </Row>
          </Card>
          <Table<CommandRecord>
            rowKey="id"
            columns={cmdColumns}
            dataSource={cmdData}
            loading={cmdLoading}
            pagination={{
              current: cmdPage,
              pageSize: cmdPageSize,
              total: cmdTotal,
              showSizeChanger: true,
              pageSizeOptions: ['10', '20', '50', '100'],
              showTotal: (total) => t('common.total', { total }),
              onChange: (p, ps) => { setCmdPage(p); setCmdPageSize(ps) },
            }}
            scroll={{ x: 850 }}
            size="small"
          />
        </>
      ),
    },
    {
      key: 'system',
      label: <span><ToolOutlined /> {t('logs.systemLog')}</span>,
      children: (
        <>
          <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }} size="small">
            <Row justify="space-between" align="middle">
              <Col>
                <Text type="secondary" style={{ fontSize: 13 }}>
                  {t('logs.systemEventTimeline')}
                </Text>
              </Col>
              <Col>
                <Space>
                  <Button icon={<ReloadOutlined />} size="small" onClick={() => refetchSystemLogs()}>
                    {t('logs.refresh')}
                  </Button>
                  <Button icon={<DownloadOutlined />} size="small" onClick={handleExportSystem}>
                    {t('logs.exportCSV')}
                  </Button>
                </Space>
              </Col>
            </Row>
          </Card>
          <Row gutter={16}>
            <Col xs={24} lg={10}>
              <Card title={t('logs.timelineView')} size="small" bordered={false} style={{ minHeight: 400, borderRadius: 12 }}>
                {renderSystemTimeline()}
              </Card>
            </Col>
            <Col xs={24} lg={14}>
              <Card title={t('logs.listView')} size="small" bordered={false} style={{ borderRadius: 12 }}>
                <Table<SystemEvent>
                  rowKey="id"
                  columns={sysTableColumns}
                  dataSource={sysData}
                  loading={sysLoading}
                  pagination={{
                    current: sysPage,
                    pageSize: sysPageSize,
                    total: sysTotal,
                    showSizeChanger: true,
                    pageSizeOptions: ['10', '20', '50', '100'],
                    showTotal: (total) => t('common.total', { total }),
                    onChange: (p, ps) => { setSysPage(p); setSysPageSize(ps) },
                  }}
                  scroll={{ x: 800 }}
                  size="small"
                />
              </Card>
            </Col>
          </Row>
        </>
      ),
    },
  ]

  /* ---------- 过滤器变更时重置页码 ---------- */

  const handleFilterChange = () => {
    setAuditPage(1)
    setAlarmPage(1)
    setCmdPage(1)
    setSysPage(1)
  }

  return (
    <div>
      <Title level={4} style={{ marginBottom: 24 }}>
        <HistoryOutlined style={{ marginRight: 8 }} />
        {t('logs.title')}
      </Title>

      {/* 全局过滤栏 */}
      <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row gutter={[12, 12]} align="middle">
          <Col xs={12} sm={8} md={4}>
            <div style={{ marginBottom: 4 }}>
              <Text type="secondary" style={{ fontSize: 12 }}>{t('logs.timeRange')}</Text>
            </div>
            <RangePicker
              style={{ width: '100%' }}
              value={dateRange as any}
              onChange={(dates) => {
                setDateRange(dates as any)
                handleFilterChange()
              }}
              showTime
              placeholder={[t('logs.startTime'), t('logs.endTime')]}
            />
          </Col>
          <Col xs={12} sm={8} md={4}>
            <div style={{ marginBottom: 4 }}>
              <Text type="secondary" style={{ fontSize: 12 }}>{t('logs.logType')}</Text>
            </div>
            <Select
              style={{ width: '100%' }}
              value={logType}
              onChange={(v) => {
                setLogType(v)
                handleFilterChange()
              }}
              options={LOG_TYPE_OPTIONS}
            />
          </Col>
          <Col xs={12} sm={8} md={4}>
            <div style={{ marginBottom: 4 }}>
              <Text type="secondary" style={{ fontSize: 12 }}>{t('logs.userFilter')}</Text>
            </div>
            <Input
              placeholder={t('logs.username')}
              allowClear
              value={userFilter}
              onChange={(e) => setUserFilter(e.target.value)}
              onPressEnter={handleFilterChange}
            />
          </Col>
          <Col xs={12} sm={8} md={4}>
            <div style={{ marginBottom: 4 }}>
              <Text type="secondary" style={{ fontSize: 12 }}>{t('logs.deviceSN')}</Text>
            </div>
            <Input
              placeholder={t('logs.deviceSnPlaceholder')}
              allowClear
              value={deviceSnFilter}
              onChange={(e) => setDeviceSnFilter(e.target.value)}
              onPressEnter={handleFilterChange}
            />
          </Col>
          <Col xs={12} sm={8} md={3}>
            <div style={{ marginBottom: 4 }}>&nbsp;</div>
            <Button
              icon={<SearchOutlined />}
              type="primary"
              onClick={handleFilterChange}
            >
              {t('logs.query')}
            </Button>
          </Col>
          <Col xs={12} sm={8} md={3}>
            <div style={{ marginBottom: 4 }}>&nbsp;</div>
            <Button
              icon={<ReloadOutlined />}
              onClick={() => {
                setDateRange(null)
                setLogType('all')
                setUserFilter('')
                setDeviceSnFilter('')
                handleFilterChange()
              }}
            >
              {t('common.reset')}
            </Button>
          </Col>
        </Row>
      </Card>

      {/* Tab 内容 */}
      <Card bordered={false} style={{ borderRadius: 12 }}>
        <Tabs
          onChange={(key) => {
            setActiveTab(key)
            setLogType(key)
          }}
          items={tabItems}
          size="large"
        />
      </Card>
    </div>
  )
}

export default OperationLogsPage