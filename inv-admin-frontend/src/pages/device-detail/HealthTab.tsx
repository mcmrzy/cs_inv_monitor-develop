import { useQuery } from '@tanstack/react-query'
import {
  Card, Progress, Tag, Spin, Empty, Typography, Space, Table, Row, Col, Statistic, Alert,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  HeartOutlined, FireOutlined, ThunderboltOutlined, ToolOutlined, ApartmentOutlined,
} from '@ant-design/icons'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'

const { Text, Title: AntTitle } = Typography

interface HealthTabProps {
  sn: string
}

interface DiagEvent {
  rule_code: string
  level: 'fault' | 'warning' | 'info'
  status: 'active' | 'resolved'
  detail: Record<string, unknown>
  first_at: string
  last_at: string
  count: number
}

interface HealthPoint {
  event_time: string
  score: number
  level: string
  factors: Record<string, number>
}

// 健康度颜色分级（≥90 健康 / 70-89 良好 / 50-69 注意 / <50 需维护）
const HEALTH_COLOR: Record<string, string> = {
  healthy: '#52c41a',
  good: '#1677ff',
  attention: '#faad14',
  maintenance: '#ff4d4f',
}
const HEALTH_LEVEL_KEY = (level: string) => `deviceDetail.health.level.${level}`

// 诊断规则文案（V2.1 文档 14 节规则码）
const RULE_LABEL_KEY = (code: string) => `deviceDetail.health.rule.${code}`

function popcount(v: number): number {
  let n = 0
  while (v) { n += v & 1; v >>= 1 }
  return n
}

const HealthTab: React.FC<HealthTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()

  const { data: realtime, isLoading: rtLoading, error: rtError, refetch: refetchRt } = useQuery({
    queryKey: queryKeys.devices.realtime(sn),
    queryFn: () => deviceApi.getRealtime(sn).then((r) => (r.data?.data ?? null) as Record<string, any> | null),
    refetchInterval: 10_000,
  })

  const { data: diagnostics, isLoading: diagLoading, error: diagError, refetch: refetchDiag } = useQuery({
    queryKey: ['device-diagnostics', sn],
    queryFn: () => deviceApi.getDiagnostics(sn).then((r) => (r.data?.data ?? r.data ?? []) as DiagEvent[]),
    refetchInterval: 30_000,
  })

  const { data: healthHistory, isLoading: histLoading, error: histError, refetch: refetchHist } = useQuery({
    queryKey: ['device-health-history', sn],
    queryFn: () => deviceApi.getHealthHistory(sn, { limit: 24 }).then((r) => (r.data?.data ?? r.data ?? []) as HealthPoint[]),
    refetchInterval: 60_000,
  })

  const loading = rtLoading || diagLoading || histLoading
  const loadError = rtError || diagError || histError
  const retryAll = () => { void refetchRt(); void refetchDiag(); void refetchHist() }

  const derived = (realtime?.derived?.data ?? {}) as Record<string, any>
  const fan = (realtime?.fan?.data ?? {}) as Record<string, any>
  const diag = (realtime?.diag?.data ?? {}) as Record<string, any>
  const sock = (realtime?.sock?.data ?? {}) as Record<string, any>
  const sys = (realtime?.sys?.data ?? {}) as Record<string, any>

  const healthScore = derived.health_score ?? healthHistory?.[0]?.score ?? null
  const healthLevel = derived.health_level ?? healthHistory?.[0]?.level ?? null
  const thermalStatus = derived.thermal_status ?? 'unknown'

  const paired = sock.paired_socket != null ? popcount(Number(sock.paired_socket)) : null
  const online = sock.online_socket != null ? popcount(Number(sock.online_socket)) : null
  const on = sock.on_socket != null ? popcount(Number(sock.on_socket)) : null
  const parallelRole = derived.parallel_role ?? (paired ? 'master' : 'standalone')

  const workHours = diag.work_time_total != null ? (Number(diag.work_time_total) / 3600).toFixed(1) : null

  const diagColumns: ColumnsType<DiagEvent> = [
    {
      title: t('deviceDetail.health.rule'), dataIndex: 'rule_code', key: 'rule_code', width: 200,
      render: (v: string) => {
        const key = RULE_LABEL_KEY(v)
        return <Space size={6}><span>{t(key) !== key ? t(key) : v}</span><Text code style={{ fontSize: 11 }}>{v}</Text></Space>
      },
    },
    {
      title: t('deviceDetail.health.level'), dataIndex: 'level', key: 'level', width: 100,
      render: (v: string) => (
        <Tag color={v === 'fault' ? 'red' : v === 'warning' ? 'orange' : 'blue'}>{t(`deviceDetail.health.levelName.${v}`)}</Tag>
      ),
    },
    {
      title: t('deviceDetail.health.status'), dataIndex: 'status', key: 'status', width: 100,
      render: (v: string) => (v === 'active' ? <Tag color="processing">{t('deviceDetail.health.statusActive')}</Tag> : <Tag>{t('deviceDetail.health.statusResolved')}</Tag>),
    },
    {
      title: t('deviceDetail.health.count'), dataIndex: 'count', key: 'count', width: 80, align: 'right',
    },
    {
      title: t('deviceDetail.health.firstAt'), dataIndex: 'first_at', key: 'first_at', width: 160,
      render: (v: string) => formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm'),
    },
    {
      title: t('deviceDetail.health.lastAt'), dataIndex: 'last_at', key: 'last_at', width: 160,
      render: (v: string) => formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm'),
    },
    {
      title: t('deviceDetail.health.detail'), key: 'detail', ellipsis: true,
      render: (_: unknown, r: DiagEvent) => (
        <Text type="secondary" style={{ fontSize: 12 }}>
          {Object.keys(r.detail ?? {}).length ? JSON.stringify(r.detail) : '-'}
        </Text>
      ),
    },
  ]

  const thermalCard = () => {
    const statusColor = thermalStatus === 'fault' ? '#ff4d4f' : thermalStatus === 'warning' ? '#faad14' : '#52c41a'
    const statusKey = `deviceDetail.health.thermal.${thermalStatus}`
    return (
      <Card size="small" title={<Space><FireOutlined style={{ color: statusColor }} /><span>{t('deviceDetail.health.thermalTitle')}</span></Space>} bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}>
        <Space direction="vertical" size={8} style={{ width: '100%' }}>
          <Space>
            <span>{t('deviceDetail.health.thermalStatus')}:</span>
            <Tag color={statusColor}>{t(statusKey) !== statusKey ? t(statusKey) : thermalStatus}</Tag>
          </Space>
          {thermalStatus !== 'normal' && thermalStatus !== 'unknown' && (
            <Alert type="warning" showIcon message={t('deviceDetail.health.thermalAlert')} style={{ marginBottom: 8 }} />
          )}
          <Row gutter={16}>
            <Col span={8}>
              <Statistic title={t('deviceDetail.health.invFan')} value={fan.inv_fan_speed != null ? `${fan.inv_fan_speed}%` : '-'} />
            </Col>
            <Col span={8}>
              <Statistic title={t('deviceDetail.health.mpptFan')} value={fan.mppt_fan_speed != null ? `${fan.mppt_fan_speed}%` : '-'} />
            </Col>
            <Col span={8}>
              <Statistic title={t('deviceDetail.health.invTemp')} value={sys.inverter_temperature != null ? `${sys.inverter_temperature}°C` : '-'} />
            </Col>
          </Row>
        </Space>
      </Card>
    )
  }

  const parallelCard = () => (
    <Card size="small" title={<Space><ApartmentOutlined /><span>{t('deviceDetail.health.parallelTitle')}</span></Space>} bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}>
      {paired == null ? (
        <Text type="secondary">{t('deviceDetail.health.noParallelData')}</Text>
      ) : (
        <Row gutter={16}>
          <Col span={8}><Statistic title={t('deviceDetail.health.paired')} value={paired} suffix={t('deviceDetail.health.units')} /></Col>
          <Col span={8}><Statistic title={t('deviceDetail.health.onlineCount')} value={online ?? 0} suffix={t('deviceDetail.health.units')} /></Col>
          <Col span={8}><Statistic title={t('deviceDetail.health.runningCount')} value={on ?? 0} suffix={t('deviceDetail.health.units')} /></Col>
          <Col span={24} style={{ marginTop: 8 }}>
            <Space>
              <Text type="secondary">{t('deviceDetail.health.role')}:</Text>
              <Tag color={parallelRole === 'master' ? 'geekblue' : 'default'}>{t(`deviceDetail.health.roleName.${parallelRole}`)}</Tag>
              {paired > 0 && online != null && online < paired && (
                <Tag color="orange">{t('deviceDetail.health.slaveOffline')}</Tag>
              )}
              {online != null && on != null && online > on && (
                <Tag color="gold">{t('deviceDetail.health.slaveNotRunning')}</Tag>
              )}
            </Space>
          </Col>
        </Row>
      )}
    </Card>
  )

  const maintenanceCard = () => (
    <Card size="small" title={<Space><ToolOutlined /><span>{t('deviceDetail.health.maintenanceTitle')}</span></Space>} bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}>
      <Row gutter={16}>
        <Col span={8}>
          <Statistic title={t('deviceDetail.health.workTime')} value={workHours ?? '-'} suffix={workHours ? t('deviceDetail.health.hours') : ''} />
        </Col>
        <Col span={8}>
          <Statistic title={t('deviceDetail.health.invCurrent')} value={diag.inv_current != null ? `${diag.inv_current} A` : '-'} />
        </Col>
        <Col span={8}>
          <Statistic title={t('deviceDetail.health.parallelChargeCurrent')} value={diag.parallel_charge_current != null ? `${diag.parallel_charge_current} A` : '-'} />
        </Col>
      </Row>
      {(diagnostics ?? []).some((e) => e.rule_code === 'MAINTENANCE_DUE' && e.status === 'active') && (
        <Alert type="warning" showIcon message={t('deviceDetail.health.maintenanceAlert')} style={{ marginTop: 12 }} />
      )}
    </Card>
  )

  return (
    <Spin spinning={loading}>
      {loadError && (
        <QueryErrorAlert error={loadError} onRetry={retryAll} style={{ marginBottom: 16 }} />
      )}

      <Row gutter={16}>
        {/* 健康度评分环 */}
        <Col xs={24} md={8}>
          <Card size="small" bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}>
            <div style={{ textAlign: 'center' }}>
              <AntTitle level={5}><HeartOutlined style={{ marginRight: 6, color: '#ff4d4f' }} />{t('deviceDetail.health.scoreTitle')}</AntTitle>
              {healthScore != null ? (
                <>
                  <Progress
                    type="dashboard"
                    size={150}
                    percent={Math.round(Number(healthScore))}
                    strokeColor={HEALTH_COLOR[healthLevel ?? 'maintenance'] ?? '#1677ff'}
                    format={(p) => <span style={{ fontSize: 28, fontWeight: 700 }}>{p}</span>}
                  />
                  <div>
                    <Tag color={HEALTH_COLOR[healthLevel ?? 'maintenance'] ?? 'default'}>
                      {t(HEALTH_LEVEL_KEY(healthLevel ?? 'maintenance'))}
                    </Tag>
                  </div>
                </>
              ) : (
                <Empty description={t('deviceDetail.status.noData')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
              )}
            </div>
          </Card>
        </Col>

        {/* 散热状态 */}
        <Col xs={24} md={16}>
          {thermalCard()}
          {parallelCard()}
          {maintenanceCard()}
        </Col>
      </Row>

      {/* 诊断事件列表 */}
      <Card
        size="small"
        title={<Space><ThunderboltOutlined /><span>{t('deviceDetail.health.diagEvents')}</span></Space>}
        bordered={false}
        style={{ borderRadius: 12 }}
      >
        <Table<DiagEvent>
          rowKey={(r) => `${r.rule_code}-${r.status}`}
          size="small"
          columns={diagColumns}
          dataSource={diagnostics ?? []}
          pagination={{ pageSize: 10, showSizeChanger: false }}
          locale={{ emptyText: <Empty description={t('deviceDetail.health.noDiagEvents')} image={Empty.PRESENTED_IMAGE_SIMPLE} /> }}
        />
      </Card>
    </Spin>
  )
}

export default HealthTab
