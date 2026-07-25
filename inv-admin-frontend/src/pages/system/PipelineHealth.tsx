import { useState, useCallback } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Row, Col, Progress, Typography, Statistic,
  Button, Space, Tag, Badge, message, Tooltip, Alert,
} from 'antd'
import { ProTable, ProCard } from '@ant-design/pro-components'
import type { ProColumns } from '@ant-design/pro-components'
import {
  ReloadOutlined,
  CheckCircleOutlined,
  WarningOutlined,
  CloseCircleOutlined,
  CloudServerOutlined,
  ApiOutlined,
  DatabaseOutlined,
  ClusterOutlined,
  DeleteOutlined,
  RedoOutlined,
  ThunderboltOutlined,
} from '@ant-design/icons'

import {
  getPipelineHealth,
  getPipelineMetrics,
  getDLQList,
  retryDLQItem,
  deleteDLQItem,
} from '@/api/pipeline-health'
import { usePipelineHealthSSE } from '@/hooks/usePipelineHealthSSE'
import type {
  ServiceStatus,
  DLQItem,
  PipelineHealthResponse,
  PipelineMetricsResponse,
} from '@/types/pipeline-health'

const { Title, Text } = Typography

/* ==================== 常量 ==================== */

const STATUS_COLOR: Record<ServiceStatus, string> = {
  ok: '#22c55e',
  degraded: '#f59e0b',
  down: '#ef4444',
}

const STATUS_LABEL: Record<ServiceStatus, string> = {
  ok: '正常',
  degraded: '降级',
  down: '离线',
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

/* ==================== 辅助组件 ==================== */

interface StatusBadgeProps {
  status: ServiceStatus
  label: string
  icon: React.ReactNode
}

const StatusIndicator: React.FC<StatusBadgeProps> = ({ status, label, icon }) => (
  <div style={{ textAlign: 'center', padding: '12px 0' }}>
    <div style={{ fontSize: 28, color: STATUS_COLOR[status], marginBottom: 4 }}>
      {icon}
    </div>
    <div style={{ fontWeight: 600, marginBottom: 4 }}>{label}</div>
    <Tag color={STATUS_COLOR[status]}>{STATUS_LABEL[status]}</Tag>
  </div>
)

/* ==================== 主组件 ==================== */

const PipelineHealthPage: React.FC = () => {
  const queryClient = useQueryClient()

  /* ---------- SSE 实时推送 ---------- */
  const { event: sseEvent, connected: sseConnected, error: sseError, reconnect } = usePipelineHealthSSE()

  /* ---------- REST API 查询 ---------- */
  const {
    data: healthData,
    isLoading: healthLoading,
    error: healthError,
    refetch: refetchHealth,
  } = useQuery({
    queryKey: ['pipeline-health'],
    queryFn: getPipelineHealth,
    refetchInterval: 30000,
  })

  const {
    data: metricsData,
    isLoading: metricsLoading,
    error: metricsError,
    refetch: refetchMetrics,
  } = useQuery({
    queryKey: ['pipeline-metrics'],
    queryFn: getPipelineMetrics,
    refetchInterval: 30000,
  })

  const [dlqPage, setDlqPage] = useState(1)
  const {
    data: dlqData,
    isLoading: dlqLoading,
    error: dlqError,
    refetch: refetchDlq,
  } = useQuery({
    queryKey: ['pipeline-dlq', dlqPage],
    queryFn: () => getDLQList(dlqPage, 20),
    refetchInterval: 30000,
  })

  /* ---------- DLQ 操作 ---------- */
  const retryMutation = useMutation({
    mutationFn: (id: string) => retryDLQItem(id),
    onSuccess: () => {
      message.success('消息已重新投递')
      queryClient.invalidateQueries({ queryKey: ['pipeline-dlq'] })
    },
    onError: () => message.error('重试失败'),
  })

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteDLQItem(id),
    onSuccess: () => {
      message.success('消息已删除')
      queryClient.invalidateQueries({ queryKey: ['pipeline-dlq'] })
    },
    onError: () => message.error('删除失败'),
  })

  /* ---------- 刷新 ---------- */
  const handleRefresh = useCallback(() => {
    refetchHealth()
    refetchMetrics()
    refetchDlq()
  }, [refetchHealth, refetchMetrics, refetchDlq])

  /* ---------- 计算数据 ---------- */
  const health: PipelineHealthResponse | undefined = healthData
  const metrics: PipelineMetricsResponse | undefined = metricsData

  // SSE 实时数据覆盖
  const messageRate = sseEvent?.message_rate ?? metrics?.message_rate ?? 0
  const onlineDevices = sseEvent?.online_devices ?? health?.summary?.online_devices ?? 0
  const totalDevices = sseEvent?.total_devices ?? health?.summary?.total_devices ?? 0
  const dlqPending = sseEvent?.dlq_pending ?? dlqData?.total ?? 0

  const connectionRate = totalDevices > 0 ? Math.round((onlineDevices / totalDevices) * 100) : 0
  const kafkaLag = metrics?.kafka_lag ?? 0
  const cmdSuccessRate = metrics?.commands_success_rate ?? 0
  const cmdExpired = metrics?.commands_expired ?? 0

  /* ---------- DLQ 表格列 ---------- */
  const dlqColumns: ProColumns<DLQItem>[] = [
    {
      title: 'ID',
      dataIndex: 'id',
      width: 120,
      ellipsis: true,
    },
    {
      title: '消费者类型',
      dataIndex: 'consumer_type',
      width: 120,
      render: (_, record: DLQItem) => <Tag>{record.consumer_type}</Tag>,
    },
    {
      title: 'Topic',
      dataIndex: 'topic',
      width: 160,
    },
    {
      title: '消息内容',
      dataIndex: 'payload_summary',
      ellipsis: true,
      render: (_, record: DLQItem) => (
        <Tooltip title={record.payload_summary}>
          <Text style={{ maxWidth: 240 }} ellipsis>{record.payload_summary}</Text>
        </Tooltip>
      ),
    },
    {
      title: '错误信息',
      dataIndex: 'error_message',
      width: 180,
      ellipsis: true,
      render: (_, record: DLQItem) => <Text type="danger">{record.error_message}</Text>,
    },
    {
      title: '重试次数',
      dataIndex: 'retry_count',
      width: 90,
      align: 'center',
    },
    {
      title: '操作',
      key: 'actions',
      width: 140,
      render: (_, record) => (
        <Space size="small">
          <Button
            type="link"
            size="small"
            icon={<RedoOutlined />}
            loading={retryMutation.isPending && retryMutation.variables === record.id}
            onClick={() => retryMutation.mutate(record.id)}
          >
            重试
          </Button>
          <Button
            type="link"
            size="small"
            danger
            icon={<DeleteOutlined />}
            loading={deleteMutation.isPending && deleteMutation.variables === record.id}
            onClick={() => deleteMutation.mutate(record.id)}
          >
            删除
          </Button>
        </Space>
      ),
    },
  ]

  /* ---------- 渲染 ---------- */
  return (
    <div style={{ padding: 0 }}>
      {/* 页面标题 + 操作栏 */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
        <Title level={4} style={{ margin: 0 }}>系统管道健康</Title>
        <Space>
          <Badge
            status={sseConnected ? 'success' : 'error'}
            text={sseConnected ? '实时连接' : '连接断开'}
          />
          {sseError && (
            <Button size="small" onClick={reconnect}>重连 SSE</Button>
          )}
          <Button icon={<ReloadOutlined />} onClick={handleRefresh}>刷新</Button>
        </Space>
      </div>

      {(healthError || metricsError) && (
        <Alert
          type="warning"
          showIcon
          message="数据获取异常"
          description="部分数据可能不可用，请检查后端服务状态"
          style={{ marginBottom: 16 }}
        />
      )}

      {/* 1. 管道状态总览 */}
      <ProCard title="管道状态总览" style={{ marginBottom: 24 }} loading={healthLoading}>
        <Row gutter={16}>
          <Col xs={12} sm={6}>
            <StatusIndicator
              status={health?.services?.bridge?.status ?? 'down'}
              label="Bridge"
              icon={<CloudServerOutlined />}
            />
          </Col>
          <Col xs={12} sm={6}>
            <StatusIndicator
              status={health?.services?.['device-server']?.status ?? 'down'}
              label="Device Server"
              icon={<ApiOutlined />}
            />
          </Col>
          <Col xs={12} sm={6}>
            <StatusIndicator
              status={health?.services?.api?.status ?? 'down'}
              label="API Server"
              icon={<DatabaseOutlined />}
            />
          </Col>
          <Col xs={12} sm={6}>
            <div style={{ textAlign: 'center', padding: '12px 0' }}>
              <div style={{ fontSize: 28, marginBottom: 4 }}>
                <Tag color={
                  health?.overall_status === 'ok' ? '#22c55e'
                  : health?.overall_status === 'degraded' ? '#f59e0b'
                  : '#ef4444'
                }>
                  {STATUS_LABEL[health?.overall_status ?? 'down']}
                </Tag>
              </div>
              <div style={{ fontWeight: 600, marginBottom: 4 }}>整体状态</div>
              <Text type="secondary">
                {health?.overall_status === 'ok'
                  ? <CheckCircleOutlined style={{ color: '#22c55e' }} />
                  : health?.overall_status === 'degraded'
                  ? <WarningOutlined style={{ color: '#f59e0b' }} />
                  : <CloseCircleOutlined style={{ color: '#ef4444' }} />}
              </Text>
            </div>
          </Col>
        </Row>
      </ProCard>

      {/* 2-4: 指标卡片行 */}
      <Row gutter={[16, 16]} style={{ marginBottom: 24 }}>
        {/* 2. 设备连接率 */}
        <Col xs={24} md={8}>
          <ProCard title="设备连接率">
            <Progress
              percent={connectionRate}
              strokeColor={connectionRateColor(connectionRate)}
              format={(pct) => `${pct}%`}
              strokeWidth={12}
            />
            <div style={{ marginTop: 8 }}>
              <Text type="secondary">
                在线 <Text strong>{onlineDevices}</Text> / 总计 <Text strong>{totalDevices}</Text>
              </Text>
            </div>
          </ProCard>
        </Col>

        {/* 3. 消息吞吐量 */}
        <Col xs={24} md={8}>
          <ProCard title="消息吞吐量">
            <Statistic
              value={messageRate}
              precision={1}
              suffix="条/秒"
              valueStyle={{ color: '#4f6ef7' }}
              prefix={<ThunderboltOutlined />}
            />
            <div style={{ marginTop: 8 }}>
              <Badge
                status={sseConnected ? 'processing' : 'default'}
                text={sseConnected ? 'SSE 实时推送中' : '等待数据...'}
              />
            </div>
          </ProCard>
        </Col>

        {/* 5. Kafka 消费延迟 */}
        <Col xs={24} md={8}>
          <ProCard title="Kafka 消费延迟">
            <Statistic
              value={kafkaLag}
              valueStyle={{ color: lagColor(kafkaLag) }}
              prefix={<ClusterOutlined />}
            />
            <div style={{ marginTop: 8 }}>
              <Text type="secondary">
                {kafkaLag < 100 ? '正常' : kafkaLag <= 1000 ? '消费略有延迟' : '消费严重滞后'}
              </Text>
            </div>
          </ProCard>
        </Col>
      </Row>

      {/* 6. 命令投递 */}
      <Row gutter={[16, 16]} style={{ marginBottom: 24 }}>
        <Col xs={24} md={12}>
          <ProCard title="命令投递成功率">
            <Progress
              type="dashboard"
              percent={cmdSuccessRate}
              strokeColor={commandRateColor(cmdSuccessRate)}
              size={120}
            />
            <div style={{ marginTop: 12, textAlign: 'center' }}>
              <Text type="secondary">
                超时: <Text type={cmdExpired > 0 ? 'danger' : 'secondary'}>{cmdExpired}</Text>
              </Text>
            </div>
          </ProCard>
        </Col>

        {/* DLQ 积压统计 */}
        <Col xs={24} md={12}>
          <ProCard title="DLQ 积压">
            <Statistic
              value={dlqPending}
              valueStyle={{
                color: dlqPending < 10 ? '#22c55e'
                  : dlqPending <= 100 ? '#f59e0b'
                  : '#ef4444',
              }}
            />
            <div style={{ marginTop: 8 }}>
              <Text type="secondary">
                {dlqPending === 0
                  ? '无积压消息'
                  : dlqPending < 10
                  ? '少量积压'
                  : dlqPending <= 100
                  ? '中等积压，请关注'
                  : '严重积压，请尽快处理'}
              </Text>
            </div>
          </ProCard>
        </Col>
      </Row>

      {/* 4. DLQ 管理表格 */}
      <ProCard
        title="DLQ 消息管理"
        extra={
          <Button size="small" icon={<ReloadOutlined />} onClick={() => refetchDlq()}>
            刷新
          </Button>
        }
      >
        <ProTable<DLQItem>
          rowKey="id"
          columns={dlqColumns}
          dataSource={dlqData?.items ?? []}
          loading={dlqLoading}
          search={false}
          options={{ density: true, reload: () => refetchDlq(), setting: true }}
          pagination={{
            current: dlqPage,
            pageSize: 20,
            total: dlqData?.total ?? 0,
            onChange: (page) => setDlqPage(page),
            showSizeChanger: false,
            showTotal: (total) => `共 ${total} 条`,
          }}
          locale={{ emptyText: '暂无 DLQ 消息' }}
        />
      </ProCard>
    </div>
  )
}

export default PipelineHealthPage
