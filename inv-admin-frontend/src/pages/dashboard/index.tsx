import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Row, Col, Card, Table, Space, Tag, Typography,
  Segmented, Empty, Grid, Badge, Button, DatePicker, Spin,
} from 'antd'
import {
  DashboardOutlined, WifiOutlined, ExclamationCircleOutlined, ThunderboltOutlined,
  LineChartOutlined, PercentageOutlined, BarChartOutlined,
  DesktopOutlined,
} from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import ReactECharts from 'echarts-for-react'
import { dashboardApi } from '@/services/dashboardApi'
import { ALARM_LEVEL_MAP, HERO_GRADIENTS, getAlarmLevelDisplay } from '@/utils/constants'
import { safeNum } from '@/utils/format'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'
import type { ColumnsType } from 'antd/es/table'
import dayjs from 'dayjs'

const { Title, Text } = Typography

/* ==================== 类型定义 ==================== */

interface AlertItem {
  id: string | number
  device_sn: string
  alarm_level: number | string
  fault_code?: string
  fault_message: string
  occurred_at: string
}

interface StationRankItem {
  stationId: number
  stationName: string
  energy: number
  deviceCount: number
}

/* ==================== 主组件 ==================== */

const DashboardPage: React.FC = () => {
  const navigate = useNavigate()
  const screens = Grid.useBreakpoint()
  const isMobile = !screens.md
  const { t } = useTranslation()

  /* ---------- 全局数据 ---------- */
  const { data: statsRes, isLoading: statsLoading } = useQuery({
    queryKey: ['dashboard', 'statistics'],
    queryFn: () => dashboardApi.getStatistics().then((r) => r.data),
    refetchInterval: 15000,
  })

  const { data: distRes, isLoading: distLoading } = useQuery({
    queryKey: ['dashboard', 'deviceDistribution'],
    queryFn: () => dashboardApi.getDeviceDistribution().then((r) => r.data),
    refetchInterval: 15000,
  })

  const { data: trendRes, isLoading: trendLoading } = useQuery({
    queryKey: ['dashboard', 'trend', 'day'],
    queryFn: () => dashboardApi.getTrend('day').then((r) => r.data),
    refetchInterval: 15000,
  })

  const stats = (statsRes?.data ?? statsRes ?? {}) as any
  const distribution = (distRes?.data ?? distRes ?? {}) as any
  const trendData = Array.isArray(trendRes?.data)
    ? trendRes.data
    : (Array.isArray(trendRes?.data?.data) ? trendRes.data.data : []) as any[]

  /* ---------- 功率趋势 ---------- */
  const user = useAuthStore((s) => s.user)
  const userTimezone = user?.timezone || 'Asia/Shanghai'
  const [flowDate, setFlowDate] = useState(dayjs().format('YYYY-MM-DD'))

  const { data: flowRes, isLoading: flowLoading } = useQuery({
    queryKey: ['dashboard', 'energyFlow', flowDate, userTimezone],
    queryFn: () => dashboardApi.getEnergyFlow({ date: flowDate }).then((r) => r.data?.data ?? r.data ?? []),
    staleTime: 0,
    refetchOnMount: true,
  })
  const flowData = (Array.isArray(flowRes) ? flowRes : (flowRes?.data ?? [])) as any[]

  /* ---------- 电量概览 ---------- */
  const [energyOverviewPeriod, setEnergyOverviewPeriod] = useState('day')

  const { data: energyStatsRes, isLoading: energyStatsLoading } = useQuery({
    queryKey: ['dashboard', 'energyOverview', energyOverviewPeriod],
    queryFn: () => dashboardApi.getEnergyStats({ type: energyOverviewPeriod }).then((r) => r.data),
    refetchInterval: 15000,
  })
  const energyStatsRaw = (energyStatsRes?.data ?? energyStatsRes ?? {}) as any

  const { data: energyTrendRes } = useQuery({
    queryKey: ['dashboard', 'energyTrend', energyOverviewPeriod],
    queryFn: () => dashboardApi.getTrend(energyOverviewPeriod).then((r) => r.data),
    refetchInterval: 15000,
  })
  const energyTrendData = Array.isArray(energyTrendRes?.data)
    ? energyTrendRes.data
    : (Array.isArray(energyTrendRes?.data?.data) ? energyTrendRes.data.data : []) as any[]
  const recentAlerts = ((stats?.recentAlarms ?? []) as AlertItem[])

  const ds = stats?.deviceStats ?? stats
  const onlineCount = safeNum(ds?.online ?? distribution?.online ?? stats?.onlineDevices)
  const offlineCount = safeNum(ds?.offline ?? distribution?.offline)
  const faultCount = safeNum(ds?.fault ?? distribution?.fault ?? stats?.faultDevices)
  const totalDevices = safeNum(ds?.total ?? stats?.totalDevices ?? (onlineCount + offlineCount + faultCount))
  const onlineRate = totalDevices > 0 ? ((onlineCount / totalDevices) * 100).toFixed(1) : '0.0'

  /* ============================================================
   *  Tab 1: 总览
   * ============================================================ */

  const pieOption = useMemo(() => ({
    tooltip: { trigger: 'item' as const, formatter: '{b}: {c} ({d}%)' },
    legend: { bottom: 0, data: [t('common.online'), t('common.offline'), t('common.fault')] },
    color: ['#52c41a', '#d9d9d9', '#ff4d4f'],
    series: [{
      type: 'pie' as const,
      radius: ['48%', '72%'],
      center: ['50%', '42%'],
      avoidLabelOverlap: false,
      itemStyle: { borderRadius: 6, borderColor: '#fff', borderWidth: 3 },
      label: { show: false },
      emphasis: { label: { show: true, fontSize: 15, fontWeight: 'bold' as const } },
      data: [
        { value: onlineCount, name: t('common.online') },
        { value: offlineCount, name: t('common.offline') },
        { value: faultCount, name: t('common.fault') },
      ],
    }],
  }), [onlineCount, offlineCount, faultCount])

  /* 功率趋势图配置 */
  const energyFlowOption = useMemo(() => {
    if (!flowData || flowData.length === 0) return {}
    const times = flowData.map((d: any) => d.time)
    const pvData = flowData.map((d: any) => safeNum(d.pvPower))
    const battChargeData = flowData.map((d: any) => safeNum(d.batteryCharge))
    const battDischargeData = flowData.map((d: any) => -safeNum(d.batteryDischarge))
    const loadData = flowData.map((d: any) => -safeNum(d.loadPower))
    return {
      tooltip: {
        trigger: 'axis' as const,
        axisPointer: { type: 'cross' as const },
        formatter: (params: any) => {
          let html = `<div style="font-weight:600;margin-bottom:4px">${params[0].axisValue}</div>`
          params.forEach((p: any) => {
            const val = Math.abs(p.value)
            html += `<div>${p.marker} ${p.seriesName}: ${val.toFixed(0)} W</div>`
          })
          return html
        },
      },
      legend: { data: ['光伏功率', '电池充电', '电池放电', '负载功率'], top: 0, itemGap: 16 },
      grid: { left: '3%', right: '4%', bottom: '12%', top: '45', containLabel: true },
      xAxis: { type: 'category' as const, data: times, axisLabel: { fontSize: 11 } },
      yAxis: {
        type: 'value' as const, name: '功率 (W)',
        axisLabel: { formatter: (v: number) => Math.abs(v) >= 1000 ? (Math.abs(v) / 1000).toFixed(1) + 'k' : Math.abs(v).toString() },
      },
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        { type: 'slider', start: 0, end: 100, height: 20, bottom: 8 },
      ],
      series: [
        {
          name: '光伏功率', type: 'line' as const, data: pvData, smooth: true, symbol: 'none',
          lineStyle: { color: '#f59e0b', width: 2 }, itemStyle: { color: '#f59e0b' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(245,158,11,0.3)' }, { offset: 1, color: 'rgba(245,158,11,0.02)' }] } },
        },
        {
          name: '电池充电', type: 'line' as const, data: battChargeData, smooth: true, symbol: 'none',
          lineStyle: { color: '#22c55e', width: 2 }, itemStyle: { color: '#22c55e' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(34,197,94,0.3)' }, { offset: 1, color: 'rgba(34,197,94,0.02)' }] } },
        },
        {
          name: '电池放电', type: 'line' as const, data: battDischargeData, smooth: true, symbol: 'none',
          lineStyle: { color: '#3b82f6', width: 2 }, itemStyle: { color: '#3b82f6' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(59,130,246,0.02)' }, { offset: 1, color: 'rgba(59,130,246,0.2)' }] } },
        },
        {
          name: '负载功率', type: 'line' as const, data: loadData, smooth: true, symbol: 'none',
          lineStyle: { color: '#ef4444', width: 2 }, itemStyle: { color: '#ef4444' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(239,68,68,0.02)' }, { offset: 1, color: 'rgba(239,68,68,0.2)' }] } },
        },
      ],
      markLine: { silent: true, lineStyle: { color: '#94a3b8', type: 'solid' as const, width: 1 }, data: [{ yAxis: 0 }], label: { show: false } },
    }
  }, [flowData])

  /* 电量概览柱状图配置 */
  const energyOverviewOption = useMemo(() => {
    const es = energyStatsRaw
    const dates = es?.dates ?? []
    if (dates.length === 0) return {}
    const pvArr = es.pv ?? []
    const chargeArr = es.batteryCharge ?? []
    const dischargeArr = es.batteryDischarge ?? []
    const loadMap: Record<string, number> = {}
    for (const item of energyTrendData) {
      loadMap[item.date] = safeNum(item.load)
    }
    const seriesConfig = [
      { name: t('dash.pvEnergy'), color: '#f59e0b', data: pvArr },
      { name: t('dash.battChargeEnergy'), color: '#22c55e', data: chargeArr },
      { name: t('dash.battDischargeEnergy'), color: '#3b82f6', data: dischargeArr },
      { name: t('dash.loadConsumption'), color: '#ef4444', data: dates.map((d: string) => loadMap[d] ?? 0) },
    ]
    return {
      tooltip: { trigger: 'axis' as const, axisPointer: { type: 'shadow' as const } },
      legend: { data: seriesConfig.map((s) => s.name), top: 0, itemGap: 16 },
      grid: { left: '3%', right: '4%', bottom: '12%', top: '45', containLabel: true },
      xAxis: { type: 'category' as const, data: dates, axisLabel: { fontSize: 11 } },
      yAxis: { type: 'value' as const, name: 'kWh' },
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        { type: 'slider', start: 0, end: 100, height: 20, bottom: 8 },
      ],
      series: seriesConfig.map((s) => ({
        name: s.name, type: 'bar' as const,
        data: s.data.map((v: any) => parseFloat(safeNum(v).toFixed(2))),
        itemStyle: { color: s.color, borderRadius: [3, 3, 0, 0] },
        barMaxWidth: 20,
      })),
    }
  }, [energyStatsRaw, energyTrendData, t])

  /* 电站排行 */
  const [rankingPeriod, setRankingPeriod] = useState('today')
  const { data: rankingRes } = useQuery({
    queryKey: ['dashboard', 'stationRanking', rankingPeriod],
    queryFn: () => dashboardApi.getStationRanking({ period: rankingPeriod, limit: 8 }).then((r) => r.data),
  })
  const rankingData: StationRankItem[] = (() => {
    const raw = rankingRes?.data ?? rankingRes
    return Array.isArray(raw) ? raw : []
  })()

  const rankingOption = useMemo(() => {
    if (!rankingData || rankingData.length === 0) return {}
    const names = rankingData.map((i) => i.stationName || `${t('dash.stationName')}${i.stationId}`)
    const values = rankingData.map((i) => safeNum(i.energy))
    return {
      tooltip: { trigger: 'axis' as const, axisPointer: { type: 'shadow' as const } },
      grid: { left: '3%', right: '8%', bottom: '3%', top: '8%', containLabel: true },
      xAxis: { type: 'value' as const, name: 'kWh' },
      yAxis: { type: 'category' as const, data: names.reverse(), axisLabel: { width: 80, overflow: 'truncate' as const } },
      series: [{
        type: 'bar' as const,
        data: values.reverse(),
        barWidth: 18,
        itemStyle: {
          borderRadius: [0, 4, 4, 0],
          color: { type: 'linear' as const, x: 0, y: 0, x2: 1, y2: 0,
            colorStops: [{ offset: 0, color: '#1677ff' }, { offset: 1, color: '#4facfe' }] },
        },
        label: { show: true, position: 'right' as const, formatter: '{c}', fontSize: 11 },
      }],
    }
  }, [rankingData])

  const alertColumns: ColumnsType<AlertItem> = [
    { title: t('dash.deviceSN'), dataIndex: 'device_sn', key: 'device_sn', width: 140, ellipsis: true },
    {
      title: t('dash.alertLevel'), dataIndex: 'alarm_level', key: 'alarm_level', width: 80,
      render: (level: number | string, record: any) => {
        const cfg = getAlarmLevelDisplay(record.fault_code, level)
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    { title: t('dash.faultMessage'), dataIndex: 'fault_message', key: 'fault_message', ellipsis: true },
    {
      title: t('common.time'), dataIndex: 'occurred_at', key: 'occurred_at', width: 150,
      render: (v: string) => v ? dayjs(v).format('MM-DD HH:mm:ss') : '-',
    },
  ]

  const renderOverview = () => (
    <>
      {/* Hero 卡片 */}
      <Row gutter={[16, 16]}>
        {[
          { title: t('dash.deviceTotal'), value: totalDevices, icon: <DashboardOutlined />, gradient: HERO_GRADIENTS[0] },
          { title: t('dash.deviceOnline'), value: onlineCount, icon: <WifiOutlined />, gradient: HERO_GRADIENTS[2] },
          { title: t('dash.deviceFault'), value: faultCount, icon: <ExclamationCircleOutlined />, gradient: HERO_GRADIENTS[1] },
          { title: t('dash.todayGeneration'), value: safeNum(stats.todayEnergy), suffix: 'kWh', icon: <ThunderboltOutlined />, gradient: HERO_GRADIENTS[3] },
          { title: t('dash.totalGeneration'), value: safeNum(stats.totalEnergy), suffix: 'kWh', icon: <LineChartOutlined />, gradient: HERO_GRADIENTS[4] },
          { title: t('dash.onlineRate'), value: onlineRate, suffix: '%', icon: <PercentageOutlined />, gradient: HERO_GRADIENTS[5] },
        ].map((item, idx) => (
          <Col xs={12} sm={8} lg={4} key={idx}>
            <Card
              bordered={false}
              style={{ background: item.gradient, borderRadius: 12 }}
              styles={{ body: { padding: isMobile ? '12px 10px' : '20px 16px' } }}
            >
              <div style={{ color: '#fff', fontSize: 13, opacity: 0.9, marginBottom: 8 }}>
                {item.icon} {item.title}
              </div>
              <div style={{ color: '#fff', fontSize: isMobile ? 22 : 28, fontWeight: 700, lineHeight: 1 }}>
                {statsLoading ? '-' : safeNum(item.value).toLocaleString()}
                {item.suffix && <span style={{ fontSize: 14, fontWeight: 400, marginLeft: 4 }}>{item.suffix}</span>}
              </div>
            </Card>
          </Col>
        ))}
      </Row>

      {/* 功率趋势 + 设备状态 */}
      <Row gutter={[16, 16]} style={{ marginTop: 16 }}>
        <Col xs={24} lg={16}>
          <Card bordered={false} style={{ borderRadius: 12 }}
            title={<Space><LineChartOutlined style={{ color: '#1677ff' }} /><span>{t('dash.powerTrend')}</span></Space>}
            extra={
              <Space>
                <DatePicker value={dayjs(flowDate)} onChange={(d) => d && setFlowDate(d.format('YYYY-MM-DD'))} allowClear={false} style={{ width: 150 }} />
                <Button size="small" onClick={() => setFlowDate(dayjs().subtract(1, 'day').format('YYYY-MM-DD'))}>昨天</Button>
                <Button size="small" onClick={() => setFlowDate(dayjs().format('YYYY-MM-DD'))}>今天</Button>
              </Space>
            }
          >
            {flowLoading ? (
              <div style={{ height: 340, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Spin /></div>
            ) : flowData.length > 0 ? (
              <ReactECharts option={energyFlowOption} style={{ height: 340 }} />
            ) : (
              <Empty description={t('dash.noEnergyData')} />
            )}
          </Card>
        </Col>
        <Col xs={24} lg={8}>
          <Card bordered={false} title={t('dash.deviceStatus')} loading={distLoading}
            style={{ borderRadius: 12 }}
            styles={{ body: { padding: '12px 16px' } }}
          >
            <ReactECharts option={pieOption} style={{ height: 260 }} />
            <Row gutter={16} style={{ textAlign: 'center', marginTop: 4 }}>
              {[
                { label: t('common.online'), value: onlineCount, color: '#52c41a' },
                { label: t('common.offline'), value: offlineCount, color: '#d9d9d9' },
                { label: t('common.fault'), value: faultCount, color: '#ff4d4f' },
              ].map((i) => (
                <Col span={8} key={i.label}>
                  <Badge color={i.color} text={<Text strong>{i.label} {i.value}</Text>} />
                </Col>
              ))}
            </Row>
          </Card>
        </Col>
      </Row>

      {/* 电量概览 */}
      <Card bordered={false} style={{ borderRadius: 12, marginTop: 16 }}
        title={<Space><BarChartOutlined style={{ color: '#722ed1' }} /><span>{t('dash.energyOverview')}</span></Space>}
        extra={
          <Segmented size="small" value={energyOverviewPeriod} onChange={(v) => setEnergyOverviewPeriod(v as string)}
            options={[
              { label: t('dash.last7Days'), value: 'day' },
              { label: t('dash.last4Weeks'), value: 'week' },
              { label: t('dash.last12Months'), value: 'month' },
            ]}
          />
        }
      >
        {energyStatsLoading ? (
          <div style={{ height: 300, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Spin /></div>
        ) : (energyStatsRaw?.dates?.length ?? 0) > 0 ? (
          <ReactECharts option={energyOverviewOption} style={{ height: 300 }} />
        ) : (
          <Empty description={t('dash.noEnergyData')} />
        )}
      </Card>

      {/* 电站排行 + 近期告警 */}
      <Row gutter={[16, 16]} style={{ marginTop: 16 }}>
        <Col xs={24} lg={10}>
          <Card bordered={false} style={{ borderRadius: 12 }}
            title={t('dash.stationRank')}
            extra={
              <Segmented size="small" value={rankingPeriod} onChange={(v) => setRankingPeriod(v as string)}
                options={[
                  { label: t('dash.today'), value: 'today' },
                  { label: t('dash.thisWeek'), value: 'week' },
                  { label: t('dash.thisMonth'), value: 'month' },
                ]}
              />
            }
          >
            {rankingData && rankingData.length > 0 ? (
              <ReactECharts option={rankingOption} style={{ height: 300 }} />
            ) : (
              <Empty description={t('dash.noStationData')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
            )}
          </Card>
        </Col>
        <Col xs={24} lg={14}>
          <Card bordered={false} title={t('dash.recentAlerts')} style={{ borderRadius: 12 }}
            extra={<a onClick={() => navigate('/alerts')}>{t('common.viewAll')}</a>}
          >
            <Table columns={alertColumns} dataSource={recentAlerts.slice(0, 6)} rowKey="id"
              pagination={false} size="small" scroll={{ x: 500 }} />
          </Card>
        </Col>
      </Row>

      {/* 快捷入口 */}
      <Row gutter={[16, 16]} style={{ marginTop: 16 }}>
        {[
          { title: t('dash.entryDevices'), desc: t('dash.entryDevicesDesc'), icon: <DesktopOutlined style={{ fontSize: 28 }} />, color: '#1677ff', path: '/devices' },
          { title: t('dash.entryAnalytics'), desc: t('dash.entryAnalyticsDesc'), icon: <BarChartOutlined style={{ fontSize: 28 }} />, color: '#722ed1', path: '/monitoring' },
          { title: t('dash.entryAlerts'), desc: t('dash.entryAlertsDesc'), icon: <ExclamationCircleOutlined style={{ fontSize: 28 }} />, color: '#fa541c', path: '/alerts' },
        ].map((item) => (
          <Col xs={24} sm={8} key={item.path}>
            <Card hoverable bordered={false} style={{ borderRadius: 12, textAlign: 'center' }}
              onClick={() => navigate(item.path)}
            >
              <div style={{ color: item.color, marginBottom: 8 }}>{item.icon}</div>
              <Text strong style={{ fontSize: 15 }}>{item.title}</Text>
              <br />
              <Text type="secondary" style={{ fontSize: 12 }}>{item.desc}</Text>
            </Card>
          </Col>
        ))}
      </Row>
    </>
  )

  /* ============================================================
   *  Tab 配置
   * ============================================================ */

  return (
    <div>
      <Title level={4} style={{ marginBottom: 16 }}>
        {t('dash.title')}
      </Title>
      {renderOverview()}
    </div>
  )
}

export default DashboardPage
