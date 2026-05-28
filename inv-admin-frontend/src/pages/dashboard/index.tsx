import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Row, Col, Card, Statistic, Table, Space, Tag, Typography, Select, DatePicker, Button } from 'antd'
import {
  DashboardOutlined,
  WifiOutlined,
  ExclamationCircleOutlined,
  ThunderboltOutlined,
  LineChartOutlined,
  PercentageOutlined,
} from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import ReactECharts from 'echarts-for-react'
import { dashboardApi } from '@/services/dashboardApi'
import { deviceApi } from '@/services/deviceApi'
import { ALARM_LEVEL_MAP } from '@/utils/constants'
import type { ColumnsType } from 'antd/es/table'
import dayjs from 'dayjs'

const { Title } = Typography

interface AlertItem {
  id: string | number
  device_sn: string
  alarm_level: number | string
  fault_message: string
  occurred_at: string
}

const DashboardPage: React.FC = () => {
  const navigate = useNavigate()

  const { data: statsRes, isLoading: statsLoading } = useQuery({
    queryKey: ['dashboard', 'statistics'],
    queryFn: () => dashboardApi.getStatistics().then((res) => res.data),
    refetchInterval: 10000,
  })

  const { data: distRes, isLoading: distLoading } = useQuery({
    queryKey: ['dashboard', 'deviceDistribution'],
    queryFn: () => dashboardApi.getDeviceDistribution().then((res) => res.data),
    refetchInterval: 10000,
  })

  const { data: trendRes, isLoading: trendLoading } = useQuery({
    queryKey: ['dashboard', 'trend', 'day'],
    queryFn: () => dashboardApi.getTrend('day').then((res) => res.data),
    refetchInterval: 10000,
  })

  const { data: alertsRes, isLoading: alertsLoading } = useQuery({
    queryKey: ['dashboard', 'recentAlerts'],
    queryFn: () =>
      dashboardApi.getStatistics().then((res) => {
        return (res.data as any)?.data?.recentAlerts ?? []
      }),
    refetchInterval: 10000,
  })

  const [compareDeviceSns, setCompareDeviceSns] = useState<string[]>([])
  const [compareMetric, setCompareMetric] = useState<string>('total_active_power')
  const [compareRange, setCompareRange] = useState<[dayjs.Dayjs, dayjs.Dayjs]>([
    dayjs().subtract(1, 'day'),
    dayjs(),
  ])
  const [compareEnabled, setCompareEnabled] = useState(false)

  const { data: allDevicesRes } = useQuery({
    queryKey: ['allDevices'],
    queryFn: () =>
      deviceApi.getAll().then((res) => {
        const d = res.data
        const inner = d?.data ?? d
        return (inner?.items ?? []) as { sn: string; model: string }[]
      }),
  })

  const { data: compareRes } = useQuery({
    queryKey: ['dashboard', 'compare', compareDeviceSns, compareMetric, compareRange],
    queryFn: () =>
      dashboardApi
        .compareDevices({
          devices: compareDeviceSns.join(','),
          metric: compareMetric,
          startTime: compareRange[0].toISOString(),
          endTime: compareRange[1].toISOString(),
        })
        .then((res) => res.data),
    enabled: compareEnabled && compareDeviceSns.length > 0,
  })

  const stats = (statsRes?.data ?? statsRes ?? {}) as any
  const distribution = (distRes?.data ?? distRes ?? {}) as any
  const trendData = (Array.isArray(trendRes?.data) ? trendRes?.data : trendRes?.data?.data ?? []) as any[]
  const recentAlerts = (alertsRes ?? []) as AlertItem[]

  const ds = stats?.deviceStats ?? stats
  const onlineCount = ds?.online ?? distribution?.online ?? stats?.onlineDevices ?? 0
  const offlineCount = ds?.offline ?? distribution?.offline ?? 0
  const faultCount = ds?.fault ?? distribution?.fault ?? stats?.faultDevices ?? 0
  const totalDevices = ds?.total ?? stats?.totalDevices ?? (onlineCount + offlineCount + faultCount)

  const onlineRate = totalDevices > 0 ? ((onlineCount / totalDevices) * 100).toFixed(1) : '0.0'

  const pieOption = useMemo(
    () => ({
      tooltip: {
        trigger: 'item' as const,
        formatter: '{b}: {c} ({d}%)',
      },
      legend: {
        bottom: 0,
        data: ['在线', '离线', '故障'],
      },
      color: ['#52c41a', '#d9d9d9', '#ff4d4f'],
      series: [
        {
          type: 'pie' as const,
          radius: ['45%', '70%'],
          center: ['50%', '45%'],
          avoidLabelOverlap: false,
          itemStyle: {
            borderRadius: 4,
            borderColor: '#fff',
            borderWidth: 2,
          },
          label: {
            show: false,
          },
          emphasis: {
            label: {
              show: true,
              fontSize: 16,
              fontWeight: 'bold',
            },
          },
          data: [
            { value: onlineCount, name: '在线' },
            { value: offlineCount, name: '离线' },
            { value: faultCount, name: '故障' },
          ],
        },
      ],
    }),
    [onlineCount, offlineCount, faultCount],
  )

  const trendOption = useMemo(() => {
    const dates = trendData.map((item: any) => item.date ?? item.label ?? '')
    const energies = trendData.map((item: any) => item.energy ?? item.value ?? 0)
    const cumulatives = trendData.map((item: any) => item.cumulative ?? item.cumulativeEnergy ?? 0)

    return {
      tooltip: {
        trigger: 'axis' as const,
        axisPointer: {
          type: 'cross' as const,
          crossStyle: { color: '#999' },
        },
      },
      legend: {
        data: ['日发电量(kWh)', '累计发电量(kWh)'],
      },
      grid: {
        left: '3%',
        right: '4%',
        bottom: '3%',
        top: '15%',
        containLabel: true,
      },
      xAxis: {
        type: 'category' as const,
        data: dates,
        axisPointer: { type: 'line' as const },
      },
      yAxis: [
        {
          type: 'value' as const,
          name: '日发电量(kWh)',
          axisLabel: { formatter: '{value}' },
        },
        {
          type: 'value' as const,
          name: '累计(kWh)',
          axisLabel: { formatter: '{value}' },
        },
      ],
      series: [
        {
          name: '日发电量(kWh)',
          type: 'line' as const,
          data: energies,
          smooth: true,
          lineStyle: { color: '#1677ff', width: 2 },
          itemStyle: { color: '#1677ff' },
          symbol: 'circle',
          symbolSize: 6,
          areaStyle: {
            color: {
              type: 'linear',
              x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: 'rgba(22, 119, 255, 0.25)' },
                { offset: 1, color: 'rgba(22, 119, 255, 0.02)' },
              ],
            },
          },
        },
        {
          name: '累计发电量(kWh)',
          type: 'line' as const,
          yAxisIndex: 1,
          data: cumulatives,
          smooth: true,
          lineStyle: { color: '#fa8c16', width: 2 },
          itemStyle: { color: '#fa8c16' },
          symbol: 'circle',
          symbolSize: 6,
          areaStyle: {
            color: {
              type: 'linear',
              x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: 'rgba(250, 140, 22, 0.25)' },
                { offset: 1, color: 'rgba(250, 140, 22, 0.02)' },
              ],
            },
          },
        },
      ],
    }
  }, [trendData])

  const compareData = (compareRes?.data ?? compareRes ?? {}) as any
  const compareSeriesData = (compareData?.series ?? []) as any[]
  const compareDevices = (compareData?.devices ?? compareDeviceSns) as string[]

  const compareOption = useMemo(() => {
    if (!compareSeriesData || compareSeriesData.length === 0) return {}

    const times = compareSeriesData.map((item: any) =>
      dayjs(item.time).format('MM-DD HH:mm'),
    )

    const colors = ['#1677ff', '#52c41a', '#fa8c16', '#722ed1']
    const seriesConfig = compareDevices.map((sn: string, idx: number) => ({
      name: sn,
      type: 'line' as const,
      data: compareSeriesData.map((item: any) => item[sn] ?? 0),
      smooth: true,
      symbol: 'none' as const,
      lineStyle: { color: colors[idx % colors.length], width: 2 },
    }))

    return {
      tooltip: {
        trigger: 'axis' as const,
      },
      legend: {
        data: compareDevices,
      },
      grid: {
        left: '3%',
        right: '4%',
        bottom: '3%',
        containLabel: true,
      },
      xAxis: {
        type: 'category' as const,
        data: times,
        boundaryGap: false,
      },
      yAxis: {
        type: 'value' as const,
      },
      series: seriesConfig,
    }
  }, [compareSeriesData, compareDevices])

  const metricLabels: Record<string, string> = {
    total_active_power: '有功功率(W)',
    daily_energy: '日发电量(kWh)',
    internal_temperature: '内部温度(°C)',
    work_state: '工作状态',
    fault_code: '故障码',
  }

  const alertColumns: ColumnsType<AlertItem> = [
    {
      title: '设备序列号',
      dataIndex: 'device_sn',
      key: 'device_sn',
      width: 160,
      ellipsis: true,
    },
    {
      title: '告警级别',
      dataIndex: 'alarm_level',
      key: 'alarm_level',
      width: 100,
      render: (level: number | string) => {
        const key = typeof level === 'number' ? String(level) : level
        const config = ALARM_LEVEL_MAP[key] ?? { label: String(level), color: '#d9d9d9' }
        return <Tag color={config.color}>{config.label}</Tag>
      },
    },
    {
      title: '故障信息',
      dataIndex: 'fault_message',
      key: 'fault_message',
      ellipsis: true,
    },
    {
      title: '发生时间',
      dataIndex: 'occurred_at',
      key: 'occurred_at',
      width: 170,
      render: (val: string) => val ? dayjs(val).format('YYYY-MM-DD HH:mm:ss') : '-',
    },
  ]

  return (
    <div>
      <Title level={4} style={{ marginBottom: 24 }}>
        仪表盘
      </Title>

      <Row gutter={[16, 16]}>
        <Col xs={24} sm={12} lg={6}>
          <Card hoverable>
            <Statistic
              title="设备总数"
              value={totalDevices}
              loading={statsLoading}
              prefix={<DashboardOutlined />}
              valueStyle={{ color: '#1677ff' }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card hoverable>
            <Statistic
              title="在线设备"
              value={onlineCount}
              loading={statsLoading}
              prefix={<WifiOutlined />}
              valueStyle={{ color: '#52c41a' }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card hoverable>
            <Statistic
              title="故障设备"
              value={faultCount}
              loading={statsLoading}
              prefix={<ExclamationCircleOutlined />}
              valueStyle={{ color: '#ff4d4f' }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card hoverable>
            <Statistic
              title="今日发电量"
              value={stats.todayEnergy ?? 0}
              loading={statsLoading}
              suffix="kWh"
              prefix={<ThunderboltOutlined />}
              valueStyle={{ color: '#1677ff' }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card hoverable>
            <Statistic
              title="累计发电量"
              value={stats.totalEnergy ?? 0}
              loading={statsLoading}
              suffix="kWh"
              prefix={<LineChartOutlined />}
              valueStyle={{ color: '#fa8c16' }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card hoverable>
            <Statistic
              title="在线率"
              value={onlineRate}
              loading={statsLoading}
              suffix="%"
              prefix={<PercentageOutlined />}
              valueStyle={{ color: '#722ed1' }}
            />
          </Card>
        </Col>
      </Row>

      <Row gutter={[16, 16]} style={{ marginTop: 16 }}>
        <Col xs={24} lg={8}>
          <Card title="设备状态分布" loading={distLoading} style={{ height: 400 }}>
            <ReactECharts option={pieOption} style={{ height: 320 }} />
          </Card>
        </Col>
        <Col xs={24} lg={16}>
          <Card
            title="近期告警"
            loading={alertsLoading}
            extra={
              <a onClick={() => navigate('/alerts')}>查看全部</a>
            }
            style={{ height: 400 }}
          >
            <Table
              columns={alertColumns}
              dataSource={recentAlerts.slice(0, 5)}
              rowKey="id"
              pagination={false}
              size="small"
              scroll={{ x: 500 }}
            />
          </Card>
        </Col>
      </Row>

      <Row gutter={[16, 16]} style={{ marginTop: 16 }}>
        <Col span={24}>
          <Card title="发电量趋势" loading={trendLoading}>
            <ReactECharts option={trendOption} style={{ height: 360 }} />
          </Card>
        </Col>
      </Row>

      <Row gutter={[16, 16]} style={{ marginTop: 16 }}>
        <Col span={24}>
          <Card
            title="设备对比"
            extra={
              <Space wrap>
                <Select
                  mode="multiple"
                  maxCount={4}
                  placeholder="选择设备(最多4个)"
                  style={{ minWidth: 200 }}
                  value={compareDeviceSns}
                  onChange={(vals) => {
                    setCompareDeviceSns(vals)
                    setCompareEnabled(false)
                  }}
                  options={(allDevicesRes ?? []).map((d: any) => ({
                    label: `${d.sn} (${d.model || '-'})`,
                    value: d.sn,
                  }))}
                  filterOption={(input, option) =>
                    (option?.label as string)?.toLowerCase().includes(input.toLowerCase())
                  }
                />
                <Select
                  style={{ minWidth: 130 }}
                  value={compareMetric}
                  onChange={(v) => {
                    setCompareMetric(v)
                    setCompareEnabled(false)
                  }}
                  options={Object.entries(metricLabels).map(([value, label]) => ({
                    value,
                    label,
                  }))}
                />
                <DatePicker.RangePicker
                  showTime
                  value={compareRange}
                  onChange={(dates) => {
                    if (dates && dates[0] && dates[1]) {
                      setCompareRange([dates[0], dates[1]])
                      setCompareEnabled(false)
                    }
                  }}
                />
                <Button
                  type="primary"
                  disabled={compareDeviceSns.length === 0}
                  onClick={() => setCompareEnabled(true)}
                >
                  对比
                </Button>
              </Space>
            }
          >
            {compareEnabled && compareSeriesData.length > 0 ? (
              <ReactECharts option={compareOption} style={{ height: 400 }} />
            ) : (
              <div
                style={{
                  height: 200,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: '#999',
                }}
              >
                请选择设备和指标后点击"对比"
              </div>
            )}
          </Card>
        </Col>
      </Row>
    </div>
  )
}

export default DashboardPage
