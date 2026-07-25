import { useState, useCallback } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Tabs, Row, Col, Progress, Typography, Statistic, Card,
  Button, Space, Tag, Badge, message, Tooltip, Alert,
  Table, Input, Descriptions, Empty, Spin,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import { ProTable, ProCard } from '@ant-design/pro-components'
import type { ProColumns } from '@ant-design/pro-components'
import {
  ReloadOutlined, CheckCircleOutlined, WarningOutlined, CloseCircleOutlined,
  CloudServerOutlined, ApiOutlined, DatabaseOutlined, ClusterOutlined,
  DeleteOutlined, RedoOutlined, ThunderboltOutlined,
  DownloadOutlined, SearchOutlined,
} from '@ant-design/icons'
import ReactECharts from '@/lib/echarts'

import {
  getPipelineHealth,
  getPipelineMetrics,
  getDLQList,
  retryDLQItem,
  deleteDLQItem,
} from '@/api/pipeline-health'
import { usePipelineHealthSSE } from '@/hooks/usePipelineHealthSSE'
import { adminApi, type AuditLog, type SystemHealth } from '@/services/adminApi'
import useTranslation from '@/hooks/useTranslation'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import type {
  ServiceStatus,
  DLQItem,
  PipelineHealthResponse,
  PipelineMetricsResponse,
} from '@/types/pipeline-health'

const { Title, Text } = Typography

/* ==================== 辅助函数 ==================== */

const formatDetail = (v: any): string => {
  if (!v || (typeof v === 'object' && Object.keys(v).length === 0)) return ''
  if (typeof v === 'string') return v
  try { return JSON.stringify(v) } catch { return String(v) }
}

function formatUptime(seconds: number): string {
  if (!seconds || seconds < 0) return '-'
  const days = Math.floor(seconds / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  if (days > 0) return `${days}d ${hours}h ${mins}m`
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

const STATUS_COLOR: Record<ServiceStatus, string> = {
  ok: '#22c55e',
  degraded: '#f59e0b',
  down: '#ef4444',
}

function connectionRateColor(rate: number): string {
  if (rate > 90) return '#22c55e'
  if (rate >= 70) return '#f59e0b'
  return '#ef4444'
}

function lagColor(lag: number): string {
  if (lag < 100) return '#22c55e'
  if (lag <= 1000) return '#f59e0b'
  return '#ef4444'
}

function commandRateColor(rate: number): string {
  if (rate > 95) return '#22c55e'
  if (rate >= 80) return '#f59e0b'
  return '#ef4444'
}

const ACTION_COLORS: Record<string, string> = {
  create: 'green', update: 'blue', delete: 'red', login: 'cyan', logout: 'orange',
  import: 'purple', export: 'geekblue', bind: 'lime', unbind: 'volcano',
  command: 'magenta', approve: 'green', reject: 'red',
}

const ROLE_LABELS: Record<number, string> = {
  0: '超级管理员', 1: '管理员', 2: '经销商', 3: '操作员', 4: '安装商', 5: '终端用户',
}

/* ==================== Tab 1: 系统健康 ==================== */

const SystemHealthTab: React.FC = () => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()

  const { data: healthData, isLoading, error, refetch } = useQuery({
    queryKey: ['system-health'],
    queryFn: () => adminApi.getSystemHealth().then((r) => r.data?.data as SystemHealth),
    refetchInterval: 30000,
  })

  const health = healthData

  const statusIcon = (ok: boolean) => ok
    ? <CheckCircleOutlined style={{ color: '#22c55e', fontSize: 18 }} />
    : <CloseCircleOutlined style={{ color: '#ef4444', fontSize: 18 }} />

  return (
    <div>
      {error && (
        <Alert type="warning" showIcon message={t('system.dataFetchError')} style={{ marginBottom: 16 }} />
      )}
      <div style={{ marginBottom: 16, textAlign: 'right' }}>
        <Button icon={<ReloadOutlined />} loading={isLoading} onClick={() => refetch()}>
          {t('admin.refreshStatus')}
        </Button>
      </div>
      <Spin spinning={isLoading}>
        <Row gutter={[16, 16]}>
          <Col xs={24} sm={12} md={6}>
            <ProCard title={t('admin.cpuUsage')}>
              <Progress
                type="dashboard"
                percent={Math.round(health?.cpuUsage ?? 0)}
                strokeColor={health && health.cpuUsage > 80 ? '#ef4444' : '#1677ff'}
                size={120}
              />
            </ProCard>
          </Col>
          <Col xs={24} sm={12} md={6}>
            <ProCard title={t('admin.memoryUsage')}>
              <Progress
                type="dashboard"
                percent={Math.round(health?.memoryUsage ?? 0)}
                strokeColor={health && health.memoryUsage > 80 ? '#ef4444' : '#1677ff'}
                size={120}
              />
            </ProCard>
          </Col>
          <Col xs={24} md={12}>
            <ProCard title={t('admin.systemHealth')}>
              <Descriptions column={1} size="small" style={{ marginTop: 8 }}>
                <Descriptions.Item label={t('admin.uptime')}>
                  {health ? formatUptime(health.uptime) : '-'}
                </Descriptions.Item>
                <Descriptions.Item label={t('admin.systemVersion')}>
                  <Tag>{health?.version ?? '-'}</Tag>
                </Descriptions.Item>
                <Descriptions.Item label={t('admin.lastCheck')}>
                  {health?.lastCheckAt
                    ? formatInTimezone(health.lastCheckAt, timezone, 'YYYY-MM-DD HH:mm:ss')
                    : '-'}
                </Descriptions.Item>
              </Descriptions>
            </ProCard>
          </Col>
        </Row>
        <Row gutter={[16, 16]} style={{ marginTop: 16 }}>
          <Col xs={24} sm={8}>
            <ProCard title={t('admin.database')}>
              <div style={{ textAlign: 'center', padding: '12px 0' }}>
                {statusIcon(health?.database ?? false)}
                <div style={{ marginTop: 8 }}>
                  <Tag color={health?.database ? 'green' : 'red'}>
                    {health?.database ? t('admin.connected') : t('admin.disconnected')}
                  </Tag>
                </div>
              </div>
            </ProCard>
          </Col>
          <Col xs={24} sm={8}>
            <ProCard title="Redis">
              <div style={{ textAlign: 'center', padding: '12px 0' }}>
                {statusIcon(health?.redis ?? false)}
                <div style={{ marginTop: 8 }}>
                  <Tag color={health?.redis ? 'green' : 'red'}>
                    {health?.redis ? t('admin.connected') : t('admin.disconnected')}
                  </Tag>
                </div>
              </div>
            </ProCard>
          </Col>
          <Col xs={24} sm={8}>
            <ProCard title="MQTT">
              <div style={{ textAlign: 'center', padding: '12px 0' }}>
                {statusIcon(health?.mqtt ?? false)}
                <div style={{ marginTop: 8 }}>
                  <Tag color={health?.mqtt ? 'green' : 'red'}>
                    {health?.mqtt ? t('admin.connected') : t('admin.disconnected')}
                  </Tag>
                </div>
              </div>
            </ProCard>
          </Col>
        </Row>
      </Spin>
    </div>
  )
}

/* ==================== Tab 2: 数据管道 ==================== */

interface StatusBadgeProps {
  status: ServiceStatus
  label: string
  icon: React.ReactNode
  statusLabel: string
}

const StatusIndicator: React.FC<StatusBadgeProps> = ({ status, label, icon, statusLabel }) => (
  <div style={{ textAlign: 'center', padding: '12px 0' }}>
    <div style={{ fontSize: 28, color: STATUS_COLOR[status], marginBottom: 4 }}>{icon}</div>
    <div style={{ fontWeight: 600, marginBottom: 4 }}>{label}</div>
    <Tag color={STATUS_COLOR[status]}>{statusLabel}</Tag>
  </div>
)

const DataPipelineTab: React.FC = () => {
  const queryClient = useQueryClient()
  const { t } = useTranslation()

  const getStatusLabel = (s: ServiceStatus): string => {
    switch (s) {
      case 'ok': return t('system.statusNormal')
      case 'degraded': return t('system.statusDegraded')
      case 'down': return t('system.statusDown')
    }
  }

  const { event: sseEvent, connected: sseConnected, error: sseError, reconnect } = usePipelineHealthSSE()

  const {
    data: healthData, isLoading: healthLoading, error: healthError, refetch: refetchHealth,
  } = useQuery({
    queryKey: ['pipeline-health'],
    queryFn: getPipelineHealth,
    refetchInterval: 30000,
  })

  const {
    data: metricsData, isLoading: metricsLoading, error: metricsError, refetch: refetchMetrics,
  } = useQuery({
    queryKey: ['pipeline-metrics'],
    queryFn: getPipelineMetrics,
    refetchInterval: 30000,
  })

  const [dlqPage, setDlqPage] = useState(1)
  const {
    data: dlqData, isLoading: dlqLoading, refetch: refetchDlq,
  } = useQuery({
    queryKey: ['pipeline-dlq', dlqPage],
    queryFn: () => getDLQList(dlqPage, 20),
    refetchInterval: 30000,
  })

  const retryMutation = useMutation({
    mutationFn: (id: string) => retryDLQItem(id),
    onSuccess: () => {
      message.success(t('system.messageRedelivered'))
      queryClient.invalidateQueries({ queryKey: ['pipeline-dlq'] })
    },
    onError: () => message.error(t('system.retryFailed')),
  })

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteDLQItem(id),
    onSuccess: () => {
      message.success(t('system.messageDeleted'))
      queryClient.invalidateQueries({ queryKey: ['pipeline-dlq'] })
    },
    onError: () => message.error(t('system.deleteFailed')),
  })

  const handleRefresh = useCallback(() => {
    refetchHealth()
    refetchMetrics()
    refetchDlq()
  }, [refetchHealth, refetchMetrics, refetchDlq])

  const health: PipelineHealthResponse | undefined = healthData
  const metrics: PipelineMetricsResponse | undefined = metricsData

  const messageRate = sseEvent?.message_rate ?? metrics?.message_rate ?? 0
  const onlineDevices = sseEvent?.online_devices ?? health?.summary?.online_devices ?? 0
  const totalDevices = sseEvent?.total_devices ?? health?.summary?.total_devices ?? 0
  const dlqPending = sseEvent?.dlq_pending ?? dlqData?.total ?? 0

  const connectionRate = totalDevices > 0 ? Math.round((onlineDevices / totalDevices) * 100) : 0
  const kafkaLag = metrics?.kafka_lag ?? 0
  const cmdSuccessRate = metrics?.commands_success_rate ?? 0
  const cmdExpired = metrics?.commands_expired ?? 0

  const dlqColumns: ProColumns<DLQItem>[] = [
    { title: 'ID', dataIndex: 'id', width: 120, ellipsis: true },
    {
      title: t('system.consumerType'), dataIndex: 'consumer_type', width: 120,
      render: (_, record: DLQItem) => <Tag>{record.consumer_type}</Tag>,
    },
    { title: 'Topic', dataIndex: 'topic', width: 160 },
    {
      title: t('system.messageContent'), dataIndex: 'payload_summary', ellipsis: true,
      render: (_, record: DLQItem) => (
        <Tooltip title={record.payload_summary}>
          <Text style={{ maxWidth: 240 }} ellipsis>{record.payload_summary}</Text>
        </Tooltip>
      ),
    },
    {
      title: t('system.errorMessage'), dataIndex: 'error_message', width: 180, ellipsis: true,
      render: (_, record: DLQItem) => <Text type="danger">{record.error_message}</Text>,
    },
    { title: t('system.retryCount'), dataIndex: 'retry_count', width: 90, align: 'center' },
    {
      title: t('system.actions'), key: 'actions', width: 140,
      render: (_, record) => (
        <Space size="small">
          <Button type="link" size="small" icon={<RedoOutlined />}
            loading={retryMutation.isPending && retryMutation.variables === record.id}
            onClick={() => retryMutation.mutate(record.id)}>{t('system.retry')}</Button>
          <Button type="link" size="small" danger icon={<DeleteOutlined />}
            loading={deleteMutation.isPending && deleteMutation.variables === record.id}
            onClick={() => deleteMutation.mutate(record.id)}>{t('common.delete')}</Button>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
        <Space>
          <Badge status={sseConnected ? 'success' : 'error'}
            text={sseConnected ? t('system.realtimeConnected') : t('system.connectionLost')} />
          {sseError && <Button size="small" onClick={reconnect}>{t('system.reconnectSSE')}</Button>}
        </Space>
        <Button icon={<ReloadOutlined />} onClick={handleRefresh}>{t('common.refresh')}</Button>
      </div>

      {(healthError || metricsError) && (
        <Alert type="warning" showIcon message={t('system.dataFetchError')}
          description={t('system.dataFetchErrorDesc')} style={{ marginBottom: 16 }} />
      )}

      <ProCard title={t('system.pipelineStatusOverview')} style={{ marginBottom: 24 }} loading={healthLoading}>
        <Row gutter={16}>
          <Col xs={12} sm={6}>
            <StatusIndicator status={health?.services?.bridge?.status ?? 'down'} label="Bridge"
              icon={<CloudServerOutlined />}
              statusLabel={getStatusLabel(health?.services?.bridge?.status ?? 'down')} />
          </Col>
          <Col xs={12} sm={6}>
            <StatusIndicator status={health?.services?.['device-server']?.status ?? 'down'} label="Device Server"
              icon={<ApiOutlined />}
              statusLabel={getStatusLabel(health?.services?.['device-server']?.status ?? 'down')} />
          </Col>
          <Col xs={12} sm={6}>
            <StatusIndicator status={health?.services?.api?.status ?? 'down'} label="API Server"
              icon={<DatabaseOutlined />}
              statusLabel={getStatusLabel(health?.services?.api?.status ?? 'down')} />
          </Col>
          <Col xs={12} sm={6}>
            <div style={{ textAlign: 'center', padding: '12px 0' }}>
              <div style={{ fontSize: 28, marginBottom: 4 }}>
                <Tag color={health?.overall_status === 'ok' ? '#22c55e'
                  : health?.overall_status === 'degraded' ? '#f59e0b' : '#ef4444'}>
                  {getStatusLabel(health?.overall_status ?? 'down')}
                </Tag>
              </div>
              <div style={{ fontWeight: 600, marginBottom: 4 }}>{t('system.overallStatus')}</div>
              <Text type="secondary">
                {health?.overall_status === 'ok' ? <CheckCircleOutlined style={{ color: '#22c55e' }} />
                  : health?.overall_status === 'degraded' ? <WarningOutlined style={{ color: '#f59e0b' }} />
                  : <CloseCircleOutlined style={{ color: '#ef4444' }} />}
              </Text>
            </div>
          </Col>
        </Row>
      </ProCard>

      <Row gutter={[16, 16]} style={{ marginBottom: 24 }}>
        <Col xs={24} md={8}>
          <ProCard title={t('system.deviceConnectionRate')}>
            <Progress percent={connectionRate} strokeColor={connectionRateColor(connectionRate)}
              format={(pct) => `${pct}%`} strokeWidth={12} />
            <div style={{ marginTop: 8 }}>
              <Text type="secondary">
                {t('system.deviceOnlineTotal', { online: onlineDevices, total: totalDevices })}
              </Text>
            </div>
          </ProCard>
        </Col>
        <Col xs={24} md={8}>
          <ProCard title={t('system.messageThroughput')}>
            <Statistic value={messageRate} precision={1} suffix={t('system.messagesPerSecond')}
              valueStyle={{ color: '#4f6ef7' }} prefix={<ThunderboltOutlined />} />
            <div style={{ marginTop: 8 }}>
              <Badge status={sseConnected ? 'processing' : 'default'}
                text={sseConnected ? t('system.sseRealtimePushing') : t('system.waitingForData')} />
            </div>
          </ProCard>
        </Col>
        <Col xs={24} md={8}>
          <ProCard title={t('system.kafkaConsumerLag')}>
            <Statistic value={kafkaLag} valueStyle={{ color: lagColor(kafkaLag) }} prefix={<ClusterOutlined />} />
            <div style={{ marginTop: 8 }}>
              <Text type="secondary">
                {kafkaLag < 100 ? t('system.lagNormal') : kafkaLag <= 1000 ? t('system.lagSlight') : t('system.lagSevere')}
              </Text>
            </div>
          </ProCard>
        </Col>
      </Row>

      <Row gutter={[16, 16]} style={{ marginBottom: 24 }}>
        <Col xs={24} md={12}>
          <ProCard title={t('system.commandDeliveryRate')}>
            <Progress type="dashboard" percent={cmdSuccessRate}
              strokeColor={commandRateColor(cmdSuccessRate)} size={120} />
            <div style={{ marginTop: 12, textAlign: 'center' }}>
              <Text type="secondary">
                {t('system.timeout')}: <Text type={cmdExpired > 0 ? 'danger' : 'secondary'}>{cmdExpired}</Text>
              </Text>
            </div>
          </ProCard>
        </Col>
        <Col xs={24} md={12}>
          <ProCard title={t('system.dlqBacklog')}>
            <Statistic value={dlqPending}
              valueStyle={{ color: dlqPending < 10 ? '#22c55e' : dlqPending <= 100 ? '#f59e0b' : '#ef4444' }} />
            <div style={{ marginTop: 8 }}>
              <Text type="secondary">
                {dlqPending === 0 ? t('system.dlqNoBacklog')
                  : dlqPending < 10 ? t('system.dlqSmallBacklog')
                  : dlqPending <= 100 ? t('system.dlqMediumBacklog')
                  : t('system.dlqSevereBacklog')}
              </Text>
            </div>
          </ProCard>
        </Col>
      </Row>

      <ProCard title={t('system.dlqMessageManagement')}
        extra={<Button size="small" icon={<ReloadOutlined />} onClick={() => refetchDlq()}>{t('common.refresh')}</Button>}>
        <ProTable<DLQItem>
          rowKey="id"
          columns={dlqColumns}
          dataSource={dlqData?.items ?? []}
          loading={dlqLoading}
          search={false}
          options={{ density: true, reload: () => refetchDlq(), setting: true }}
          pagination={{
            current: dlqPage, pageSize: 20, total: dlqData?.total ?? 0,
            onChange: (page) => setDlqPage(page), showSizeChanger: false,
            showTotal: (total) => t('common.total', { total }),
          }}
          locale={{ emptyText: t('system.noDlqMessages') }}
        />
      </ProCard>
    </div>
  )
}

/* ==================== Tab 3: 运营统计 ==================== */

const OperationStatsTab: React.FC = () => {
  const { t } = useTranslation()

  const { data: stats, isLoading, error, refetch } = useQuery({
    queryKey: ['operation-stats'],
    queryFn: () => adminApi.getOperationStats().then((r) => r.data?.data),
    refetchInterval: 60000,
  })

  if (error) {
    return (
      <Alert type="warning" showIcon message={t('system.dataFetchError')}
        action={<Button size="small" onClick={() => refetch()}>{t('common.refresh')}</Button>} />
    )
  }

  const users = stats?.users as any
  const emails = stats?.emails as any
  const pushes = stats?.pushes as any
  const devices = stats?.devices as any
  const commands = stats?.commands as any
  const roles = stats?.roles as any

  // 用户注册趋势图
  const regTrendData = (users?.registration_trend ?? []) as { date: string; count: number }[]
  const regChartOption = {
    tooltip: { trigger: 'axis' },
    grid: { left: 40, right: 20, top: 20, bottom: 30 },
    xAxis: { type: 'category', data: regTrendData.map((d) => d.date) },
    yAxis: { type: 'value', minInterval: 1 },
    series: [{
      type: 'line', data: regTrendData.map((d) => d.count),
      smooth: true, areaStyle: { opacity: 0.15 }, itemStyle: { color: '#1677ff' },
    }],
  }

  // 邮件分类饼图
  const emailByType = emails?.by_type ?? {}
  const emailPieData = Object.entries(emailByType).map(([name, value]) => ({ name, value: value as number }))
  const emailPieOption = emailPieData.length > 0 ? {
    tooltip: { trigger: 'item' },
    legend: { bottom: 0 },
    series: [{
      type: 'pie', radius: ['40%', '70%'], data: emailPieData,
      label: { formatter: '{b}: {c}' },
    }],
  } : null

  // 推送分类柱状图
  const pushByType = pushes?.by_type ?? {}
  const pushBarOption = Object.keys(pushByType).length > 0 ? {
    tooltip: { trigger: 'axis' },
    grid: { left: 40, right: 20, top: 20, bottom: 30 },
    xAxis: { type: 'category', data: Object.keys(pushByType) },
    yAxis: { type: 'value', minInterval: 1 },
    series: [{
      type: 'bar', data: Object.values(pushByType),
      itemStyle: { color: '#52c41a' },
    }],
  } : null

  // 设备在线趋势
  const onlineTrendData = (devices?.online_trend ?? []) as { date: string; count: number }[]
  const onlineChartOption = {
    tooltip: { trigger: 'axis' },
    grid: { left: 40, right: 20, top: 20, bottom: 30 },
    xAxis: { type: 'category', data: onlineTrendData.map((d) => d.date) },
    yAxis: { type: 'value', minInterval: 1 },
    series: [{
      type: 'line', data: onlineTrendData.map((d) => d.count),
      smooth: true, areaStyle: { opacity: 0.15 }, itemStyle: { color: '#722ed1' },
    }],
  }

  // 命令成功率趋势
  const cmdTrendData = (commands?.trend ?? []) as { date: string; success: number; total: number; rate: number }[]
  const cmdChartOption = {
    tooltip: { trigger: 'axis', formatter: (params: any) => {
      const d = cmdTrendData[params[0]?.dataIndex]
      if (!d) return ''
      return `${d.date}<br/>${t('system.successRate')}: ${d.rate.toFixed(1)}%<br/>成功: ${d.success} / 总计: ${d.total}`
    }},
    grid: { left: 40, right: 20, top: 20, bottom: 30 },
    xAxis: { type: 'category', data: cmdTrendData.map((d) => d.date) },
    yAxis: { type: 'value', min: 0, max: 100, axisLabel: { formatter: '{value}%' } },
    series: [{
      type: 'line', data: cmdTrendData.map((d) => Number(d.rate.toFixed(1))),
      smooth: true, itemStyle: { color: '#1677ff' },
      markLine: { data: [{ yAxis: 95, lineStyle: { color: '#52c41a', type: 'dashed' } }] },
    }],
  }

  // 命令失败原因饼图
  const cmdFailures = commands?.failures ?? {}
  const failPieData = Object.entries(cmdFailures).map(([name, value]) => ({ name, value: value as number }))
  const failPieOption = failPieData.length > 0 ? {
    tooltip: { trigger: 'item' },
    legend: { bottom: 0 },
    series: [{
      type: 'pie', radius: ['40%', '70%'], data: failPieData,
      label: { formatter: '{b}: {c}' },
    }],
  } : null

  // 用户角色分布柱状图
  const roleDist = (roles?.distribution ?? []) as { role: number; count: number }[]
  const roleChartOption = roleDist.length > 0 ? {
    tooltip: { trigger: 'axis' },
    grid: { left: 40, right: 20, top: 20, bottom: 30 },
    xAxis: { type: 'category', data: roleDist.map((d) => ROLE_LABELS[d.role] ?? `Role ${d.role}`),
      axisLabel: { rotate: 15 } },
    yAxis: { type: 'value', minInterval: 1 },
    series: [{
      type: 'bar', data: roleDist.map((d) => d.count),
      itemStyle: { color: '#fa8c16' },
    }],
  } : null

  return (
    <Spin spinning={isLoading}>
      {/* KPI 卡片行 */}
      <Row gutter={[16, 16]} style={{ marginBottom: 24 }}>
        <Col xs={12} sm={6}>
          <ProCard>
            <Statistic title={t('system.todayNew')} value={users?.today_new ?? 0}
              suffix={<Text type="secondary" style={{ fontSize: 12 }}>/ {t('system.weekNew')} {users?.week_new ?? 0}</Text>} />
          </ProCard>
        </Col>
        <Col xs={12} sm={6}>
          <ProCard>
            <Statistic title={t('system.todayActive')} value={users?.today_active ?? 0}
              suffix={<Text type="secondary" style={{ fontSize: 12 }}>· {t('system.todayLogins')} {users?.today_logins ?? 0}</Text>} />
          </ProCard>
        </Col>
        <Col xs={12} sm={6}>
          <ProCard>
            <Statistic title={t('system.todayEmails')} value={emails?.today ?? 0}
              suffix={<Text type="secondary" style={{ fontSize: 12 }}>/ {t('system.weekEmails')} {emails?.week ?? 0}</Text>} />
          </ProCard>
        </Col>
        <Col xs={12} sm={6}>
          <ProCard>
            <Statistic title={t('system.todayPushes')} value={pushes?.today ?? 0}
              suffix={<Text type="secondary" style={{ fontSize: 12 }}>/ {t('system.weekPushes')} {pushes?.week ?? 0}</Text>} />
          </ProCard>
        </Col>
      </Row>

      {/* 注册趋势 + 设备在线趋势 */}
      <Row gutter={[16, 16]} style={{ marginBottom: 24 }}>
        <Col xs={24} md={12}>
          <ProCard title={t('system.registrationTrend')}>
            {regTrendData.length > 0
              ? <ReactECharts option={regChartOption} style={{ height: 220 }} />
              : <Empty description={t('system.noData')} style={{ padding: 40 }} />}
          </ProCard>
        </Col>
        <Col xs={24} md={12}>
          <ProCard title={t('system.deviceOnlineTrend')}
            extra={<Tag color="blue">{t('system.onlineRate')}: {devices?.connection_rate ?? '0'}% ({devices?.online ?? 0}/{devices?.total ?? 0})</Tag>}>
            {onlineTrendData.length > 0
              ? <ReactECharts option={onlineChartOption} style={{ height: 220 }} />
              : <Empty description={t('system.noData')} style={{ padding: 40 }} />}
          </ProCard>
        </Col>
      </Row>

      {/* 邮件分类 + 推送分类 */}
      <Row gutter={[16, 16]} style={{ marginBottom: 24 }}>
        <Col xs={24} md={12}>
          <ProCard title={t('system.emailByType')}>
            {emailPieOption
              ? <ReactECharts option={emailPieOption} style={{ height: 220 }} />
              : <Empty description={t('system.noData')} style={{ padding: 40 }} />}
          </ProCard>
        </Col>
        <Col xs={24} md={12}>
          <ProCard title={t('system.pushByType')}>
            {pushBarOption
              ? <ReactECharts option={pushBarOption} style={{ height: 220 }} />
              : <Empty description={t('system.noData')} style={{ padding: 40 }} />}
          </ProCard>
        </Col>
      </Row>

      {/* 命令成功率 + 失败原因 */}
      <Row gutter={[16, 16]} style={{ marginBottom: 24 }}>
        <Col xs={24} md={12}>
          <ProCard title={t('system.commandSuccessTrend')}>
            {cmdTrendData.length > 0
              ? <ReactECharts option={cmdChartOption} style={{ height: 220 }} />
              : <Empty description={t('system.noData')} style={{ padding: 40 }} />}
          </ProCard>
        </Col>
        <Col xs={24} md={12}>
          <ProCard title={t('system.commandFailures')}>
            {failPieOption
              ? <ReactECharts option={failPieOption} style={{ height: 220 }} />
              : <Empty description={t('system.noData')} style={{ padding: 40 }} />}
          </ProCard>
        </Col>
      </Row>

      {/* 用户角色分布 + 租户/电站 KPI */}
      <Row gutter={[16, 16]}>
        <Col xs={24} md={16}>
          <ProCard title={t('system.userRoleDistribution')}>
            {roleChartOption
              ? <ReactECharts option={roleChartOption} style={{ height: 240 }} />
              : <Empty description={t('system.noData')} style={{ padding: 40 }} />}
          </ProCard>
        </Col>
        <Col xs={24} md={8}>
          <ProCard title={t('system.tenantCount')}>
            <Statistic value={roles?.tenant_count ?? 0} valueStyle={{ color: '#1677ff' }} />
            <div style={{ marginTop: 16 }}>
              <ProCard size="small" title={t('system.stationCount')} style={{ marginTop: 8 }}>
                <Statistic value={roles?.station_count ?? 0} valueStyle={{ color: '#52c41a' }} />
              </ProCard>
            </div>
          </ProCard>
        </Col>
      </Row>
    </Spin>
  )
}

/* ==================== Tab 4: 系统日志 ==================== */

const SystemLogTab: React.FC = () => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [searchUser, setSearchUser] = useState('')

  const params = {
    page,
    pageSize,
    ...(searchUser ? { username: searchUser } : {}),
  }

  const { data: result, isLoading, error, refetch } = useQuery({
    queryKey: ['system-logs', params],
    queryFn: () => adminApi.getAuditLogs(params).then((res) => {
      const d = res.data?.data ?? res.data ?? {}
      return {
        items: Array.isArray(d) ? d : (d?.items ?? d?.list ?? []) as AuditLog[],
        total: d?.total ?? 0,
      }
    }),
  })

  const handleExport = () => {
    const rows = (result?.items ?? []).map((r) => ({
      [t('logs.time')]: formatInTimezone(r.createdAt, timezone, 'YYYY-MM-DD HH:mm:ss'),
      [t('logs.user')]: r.username,
      [t('logs.operation')]: r.action,
      [t('logs.resource')]: r.resource,
      [t('logs.detail')]: formatDetail(r.details),
      IP: r.ipAddress,
    }))
    if (rows.length === 0) return
    const headers = Object.keys(rows[0])
    const csv = [
      '\uFEFF' + headers.join(','),
      ...rows.map((row) => headers.map((h) => {
        const val = row[h]
        const str = val == null ? '' : String(val).replace(/"/g, '""')
        return `"${str}"`
      }).join(',')),
    ].join('\n')
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
    const url = window.URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = `system_logs_${Date.now()}.csv`
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    window.URL.revokeObjectURL(url)
    message.success(t('logs.exportSuccess'))
  }

  const columns: ColumnsType<AuditLog> = [
    {
      title: t('logs.time'), dataIndex: 'createdAt', key: 'createdAt', width: 170,
      render: (v: string) => v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('logs.user'), dataIndex: 'username', key: 'username', width: 120,
      render: (v: string) => v || '-',
    },
    {
      title: t('logs.operation'), dataIndex: 'action', key: 'action', width: 100,
      render: (action: string) => <Tag color={ACTION_COLORS[action] || 'default'}>{action}</Tag>,
    },
    {
      title: t('logs.resource'), dataIndex: 'resource', key: 'resource', width: 140, ellipsis: true,
      render: (v: string) => v || '-',
    },
    {
      title: t('logs.detail'), dataIndex: 'details', key: 'details', ellipsis: true,
      render: (v: any) => formatDetail(v) || '-',
    },
    {
      title: t('logs.ipAddress'), dataIndex: 'ipAddress', key: 'ipAddress', width: 140,
      render: (v: string) => <Text code>{v || '-'}</Text>,
    },
  ]

  return (
    <div>
      {error && (
        <Alert type="warning" showIcon message={t('system.dataFetchError')} style={{ marginBottom: 16 }} />
      )}
      <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }} size="small">
        <Row justify="space-between" align="middle">
          <Col>
            <Input.Search
              placeholder={t('logs.username')}
              allowClear
              style={{ width: 200 }}
              onSearch={(v) => { setSearchUser(v); setPage(1) }}
            />
          </Col>
          <Col>
            <Space>
              <Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button>
              <Button icon={<DownloadOutlined />} onClick={handleExport}>{t('logs.exportCSV')}</Button>
            </Space>
          </Col>
        </Row>
      </Card>
      <Table<AuditLog>
        rowKey="id"
        columns={columns}
        dataSource={result?.items ?? []}
        loading={isLoading}
        pagination={{
          current: page, pageSize, total: result?.total ?? 0,
          showSizeChanger: true, pageSizeOptions: ['10', '20', '50', '100'],
          showTotal: (total) => t('common.total', { total }),
          onChange: (p, ps) => { setPage(p); setPageSize(ps) },
        }}
        scroll={{ x: 800 }}
        size="small"
      />
    </div>
  )
}

/* ==================== 主组件 ==================== */

const SystemMonitorPage: React.FC = () => {
  const { t } = useTranslation()
  const [activeTab, setActiveTab] = useState('health')

  return (
    <div>
      <Title level={4} style={{ marginBottom: 16 }}>{t('menu.systemMonitor')}</Title>
      <Tabs
        activeKey={activeTab}
        onChange={setActiveTab}
        items={[
          { key: 'health', label: t('system.tabSystemHealth'), children: <SystemHealthTab /> },
          { key: 'pipeline', label: t('system.tabDataPipeline'), children: <DataPipelineTab /> },
          { key: 'stats', label: t('system.tabOperationStats'), children: <OperationStatsTab /> },
          { key: 'logs', label: t('system.tabSystemLog'), children: <SystemLogTab /> },
        ]}
        size="large"
      />
    </div>
  )
}

export default SystemMonitorPage
