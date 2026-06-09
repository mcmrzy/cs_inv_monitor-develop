import { useEffect, useState, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { Row, Col, Card, Statistic, Typography, Space, Tag, Spin, Empty } from 'antd'
import { ThunderboltOutlined, DashboardOutlined, SunOutlined, CheckCircleOutlined } from '@ant-design/icons'
import ReactEChartsCore from 'echarts-for-react/lib/core'
import * as echarts from 'echarts/core'
import { LineChart, BarChart } from 'echarts/charts'
import { TooltipComponent, GridComponent, LegendComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import { dashboardApi } from '@/services/dashboardApi'
import { deviceApi } from '@/services/deviceApi'
import useAuthStore from '@/stores/authStore'

echarts.use([LineChart, BarChart, TooltipComponent, GridComponent, LegendComponent, CanvasRenderer])

const { Title, Text } = Typography

const OverviewPage: React.FC = () => {
  const navigate = useNavigate()
  const { user } = useAuthStore()
  const [loading, setLoading] = useState(true)
  const [stats, setStats] = useState<any>({})
  const [devices, setDevices] = useState<any[]>([])
  const [trendData, setTrendData] = useState<any[]>([])

  const fetchData = useCallback(async () => {
    try {
      setLoading(true)
      const [statsRes, trendRes, deviceRes] = await Promise.all([
        dashboardApi.getStatistics(),
        dashboardApi.getTrend('month'),
        deviceApi.getDevices({ pageSize: 100 }),
      ])
      setStats(statsRes.data?.data ?? statsRes.data ?? {})
      setTrendData((trendRes.data?.data?.data ?? trendRes.data?.data ?? []).slice(-30))
      setDevices(deviceRes.data?.data?.items ?? deviceRes.data?.data ?? [])
    } catch {
      // ignore
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchData()
    const timer = setInterval(fetchData, 15000)
    return () => clearInterval(timer)
  }, [fetchData])

  const onlineDevices = devices.filter((d: any) => d.status === 1 || d.status === 'online')
  const faultDevices = devices.filter((d: any) => d.status === 2 || d.status === 'fault')

  const trendOption = {
    tooltip: { trigger: 'axis' as const },
    grid: { left: '3%', right: '5%', bottom: '3%', top: '8%', containLabel: true },
    xAxis: {
      type: 'category' as const,
      data: trendData.map((i: any) => i.label ?? ''),
      axisLabel: { fontSize: 10 },
    },
    yAxis: {
      type: 'value' as const,
      name: 'kWh',
      axisLabel: { fontSize: 10 },
    },
    series: [{
      name: '日发电量',
      type: 'line',
      data: trendData.map((i: any) => i.energy ?? 0),
      smooth: true,
      lineStyle: { color: '#1677ff', width: 2 },
      itemStyle: { color: '#1677ff' },
      symbol: 'none',
      areaStyle: {
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          { offset: 0, color: 'rgba(22, 119, 255, 0.2)' },
          { offset: 1, color: 'rgba(22, 119, 255, 0.02)' },
        ]),
      },
    }],
  }

  if (loading) {
    return <div style={{ textAlign: 'center', padding: 80 }}><Spin size="large" /></div>
  }

  const todayEnergy = stats.todayEnergy ?? 0
  const totalEnergy = stats.totalEnergy ?? 0
  const deviceStats = stats.deviceStats ?? {}

  return (
    <div style={{ padding: '0 0 24px' }}>
      <Title level={4} style={{ marginBottom: 24 }}>
        🏠 我的电站
        <Text type="secondary" style={{ fontSize: 14, marginLeft: 12 }}>
          {user?.nickname || '用户'}
        </Text>
      </Title>

      <Row gutter={[16, 16]}>
        <Col xs={24} sm={12} lg={6}>
          <Card hoverable onClick={() => navigate('/portal/devices')}>
            <Statistic
              title="设备总数"
              value={deviceStats.total ?? devices.length}
              prefix={<DashboardOutlined />}
              valueStyle={{ color: '#1677ff' }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card hoverable onClick={() => navigate('/portal/devices')}>
            <Statistic
              title="在线设备"
              value={deviceStats.online ?? onlineDevices.length}
              suffix={`/ ${deviceStats.total ?? devices.length}`}
              prefix={<CheckCircleOutlined />}
              valueStyle={{ color: '#52c41a' }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card>
            <Statistic
              title="今日发电量"
              value={todayEnergy.toFixed(1)}
              suffix="kWh"
              prefix={<SunOutlined />}
              valueStyle={{ color: '#fa8c16' }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card>
            <Statistic
              title="累计发电量"
              value={totalEnergy.toFixed(0)}
              suffix="kWh"
              prefix={<ThunderboltOutlined />}
              valueStyle={{ color: '#1677ff' }}
            />
          </Card>
        </Col>
      </Row>

      <Card title="近30日发电量趋势" style={{ marginTop: 16 }}>
        {trendData.length > 0 ? (
          <ReactEChartsCore option={trendOption} style={{ height: 280 }} echarts={echarts} />
        ) : (
          <Empty description="暂无数据" />
        )}
      </Card>

      <Card title="设备概览" style={{ marginTop: 16 }}>
        {devices.length > 0 ? (
          <Row gutter={[12, 12]}>
            {devices.slice(0, 12).map((device: any) => {
              const isOnline = device.status === 1 || device.status === 'online'
              const isFault = device.status === 2 || device.status === 'fault'
              return (
                <Col xs={24} sm={12} md={8} lg={6} key={device.sn}>
                  <Card
                    size="small"
                    hoverable
                    onClick={() => navigate(`/portal/devices?sn=${device.sn}`)}
                  >
                    <Space direction="vertical" size={4} style={{ width: '100%' }}>
                      <Space>
                        <Tag color={isOnline ? 'green' : isFault ? 'red' : 'default'}>
                          {isOnline ? '在线' : isFault ? '故障' : '离线'}
                        </Tag>
                        <Text strong>{device.model || '-'}</Text>
                      </Space>
                      <Text type="secondary" style={{ fontSize: 12 }}>
                        SN: {device.sn}
                      </Text>
                      {device.ratedPower != null && (
                        <Text type="secondary" style={{ fontSize: 12 }}>
                          额定功率: {device.ratedPower}W
                        </Text>
                      )}
                    </Space>
                  </Card>
                </Col>
              )
            })}
          </Row>
        ) : (
          <Empty description="暂无设备" />
        )}
      </Card>
    </div>
  )
}

export default OverviewPage
