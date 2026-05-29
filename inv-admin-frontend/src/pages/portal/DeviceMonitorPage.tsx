import { useEffect, useState, useCallback, useMemo } from 'react'
import { useSearchParams } from 'react-router-dom'
import {
  Card, Table, Tag, Typography, Descriptions, Select, Spin, Empty,
  Row, Col, Statistic, Space, Drawer,
} from 'antd'
import { DesktopOutlined, ThunderboltOutlined, ReloadOutlined } from '@ant-design/icons'
import ReactEChartsCore from 'echarts-for-react/lib/core'
import * as echarts from 'echarts/core'
import { LineChart } from 'echarts/charts'
import { TooltipComponent, GridComponent, LegendComponent, DataZoomComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import { deviceApi } from '@/services/deviceApi'
import { modelApi } from '@/services/modelApi'
import { useModelFields, DynamicFieldRenderer, DynamicStatCards } from '@/components/dyna'

echarts.use([LineChart, TooltipComponent, GridComponent, LegendComponent, DataZoomComponent, CanvasRenderer])

const { Title, Text } = Typography

const DeviceMonitorPage: React.FC = () => {
  const [searchParams] = useSearchParams()
  const highlightSn = searchParams.get('sn') || ''

  const [loading, setLoading] = useState(true)
  const [devices, setDevices] = useState<any[]>([])
  const [selectedSn, setSelectedSn] = useState<string>(highlightSn)
  const [realtime, setRealtime] = useState<any>(null)
  const [telemetry, setTelemetry] = useState<any[]>([])
  const [detailOpen, setDetailOpen] = useState(false)

  const selectedDevice = devices.find((d: any) => d.sn === selectedSn)
  const modelFields = useModelFields(selectedDevice?.model)

  const fetchDevices = useCallback(async () => {
    try {
      const res = await deviceApi.getDevices({ pageSize: 100 })
      const list = res.data?.data?.items ?? res.data?.data ?? res.data ?? []
      setDevices(list)
      if (highlightSn && !selectedSn) {
        setSelectedSn(highlightSn)
        setDetailOpen(true)
      }
    } catch { /* ignore */ }
  }, [highlightSn, selectedSn])

  const fetchRealtime = useCallback(async (sn: string) => {
    try {
      const res = await deviceApi.getRealtime(sn)
      setRealtime(res.data?.data ?? res.data ?? null)
    } catch { setRealtime(null) }
  }, [])

  const fetchTelemetry = useCallback(async (sn: string) => {
    try {
      const res = await deviceApi.getTelemetry(sn, { pageSize: 100 })
      const rows = res.data?.data?.items ?? res.data?.data ?? res.data ?? []
      setTelemetry(rows)
    } catch { setTelemetry([]) }
  }, [])

  useEffect(() => {
    fetchDevices()
    const timer = setInterval(fetchDevices, 10000)
    return () => clearInterval(timer)
  }, [fetchDevices])

  useEffect(() => {
    if (selectedSn) {
      fetchRealtime(selectedSn)
      fetchTelemetry(selectedSn)
      const timer = setInterval(() => {
        fetchRealtime(selectedSn)
      }, 5000)
      return () => clearInterval(timer)
    }
  }, [selectedSn, fetchRealtime, fetchTelemetry])

  useEffect(() => {
    if (devices.length > 0) setLoading(false)
  }, [devices])

  const telemetryChartOption = useMemo(() => {
    const rows = telemetry || []
    const times = rows.map((r: any) => {
      const t = r.time ? new Date(r.time) : new Date()
      return t.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
    })
    const powers = rows.map((r: any) => {
      const d = r.data ?? {}
      return Number(d?.ac?.power ?? r.total_active_power ?? 0)
    })
    return {
      tooltip: { trigger: 'axis' as const },
      grid: { left: '3%', right: '5%', bottom: '3%', top: '5%', containLabel: true },
      xAxis: { type: 'category' as const, data: times },
      yAxis: { type: 'value' as const, name: 'W' },
      dataZoom: [{ type: 'inside' }],
      series: [{
        name: '有功功率',
        type: 'line',
        data: powers,
        smooth: true,
        lineStyle: { color: '#1677ff', width: 2 },
        itemStyle: { color: '#1677ff' },
        symbol: 'none',
        areaStyle: {
          color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
            { offset: 0, color: 'rgba(22,119,255,0.2)' },
            { offset: 1, color: 'rgba(22,119,255,0.02)' },
          ]),
        },
      }],
    }
  }, [telemetry])

  const columns = [
    {
      title: 'SN',
      dataIndex: 'sn',
      key: 'sn',
      width: 140,
      render: (sn: string) => <Text code>{sn}</Text>,
    },
    {
      title: '型号',
      dataIndex: 'model',
      key: 'model',
      width: 100,
      render: (v: string) => v || '-',
    },
    {
      title: '状态',
      dataIndex: 'status',
      key: 'status',
      width: 80,
      render: (status: any) => {
        const isOnline = status === 1 || status === 'online'
        const isFault = status === 2 || status === 'fault'
        return (
          <Tag color={isOnline ? 'green' : isFault ? 'red' : 'default'}>
            {isOnline ? '在线' : isFault ? '故障' : '离线'}
          </Tag>
        )
      },
    },
    {
      title: '额定功率(W)',
      dataIndex: 'ratedPower',
      key: 'ratedPower',
      width: 110,
      render: (v: number) => v != null ? v : '-',
    },
    {
      title: '固件版本',
      dataIndex: 'firmwareVersion',
      key: 'firmwareVersion',
      width: 110,
      render: (v: string) => v || '-',
    },
    {
      title: '最后上线',
      dataIndex: 'lastOnlineAt',
      key: 'lastOnlineAt',
      width: 160,
      render: (v: string) => v ? new Date(v).toLocaleString('zh-CN') : '-',
    },
    {
      title: '操作',
      key: 'action',
      width: 80,
      render: (_: any, record: any) => (
        <a onClick={() => { setSelectedSn(record.sn); setDetailOpen(true) }}>详情</a>
      ),
    },
  ]

  const rt = realtime?.data ? realtime.data : (realtime ?? {})
  const ac = rt?.ac ?? {}
  const pv = rt?.pv ?? {}
  const battery = rt?.battery ?? {}
  const sys = rt?.sys_status ?? {}
  const energy = rt?.energy ?? {}

  return (
    <div style={{ padding: '0 0 24px' }}>
      <Space style={{ marginBottom: 16, width: '100%', justifyContent: 'space-between' }}>
        <Title level={4} style={{ margin: 0 }}>📡 设备监控</Title>
        <Tag icon={<ReloadOutlined spin={loading} />} color="processing">
          10秒自动刷新
        </Tag>
      </Space>

      <Table
        columns={columns}
        dataSource={devices}
        rowKey="sn"
        loading={loading}
        size="middle"
        pagination={{ pageSize: 20, showSizeChanger: false }}
        onRow={(record) => ({
          onClick: () => { setSelectedSn(record.sn); setDetailOpen(true) },
          style: { cursor: 'pointer' },
        })}
      />

      <Drawer
        title={`设备详情 - ${selectedSn}`}
        open={detailOpen}
        onClose={() => setDetailOpen(false)}
        width={680}
        placement="right"
      >
        {realtime ? (
          <>
            {modelFields?.cache && modelFields.cache.showFields.length > 0 ? (
              <>
                <DynamicStatCards
                  fields={modelFields.cache.showFields.slice(0, 6)}
                  data={rt}
                />
                <DynamicFieldRenderer
                  fields={modelFields.cache.showFields}
                  data={rt}
                  column={2}
                  size="small"
                />
              </>
            ) : (
              <Row gutter={[12, 12]} style={{ marginBottom: 16 }}>
                <Col span={8}>
                  <Card size="small">
                    <Statistic title="有功功率" value={ac?.power ?? 0} suffix="W" valueStyle={{ color: '#1677ff', fontSize: 20 }} />
                  </Card>
                </Col>
                <Col span={8}>
                  <Card size="small">
                    <Statistic title="光伏功率" value={pv?.power ?? pv?.pvPower ?? 0} suffix="W" valueStyle={{ color: '#fa8c16', fontSize: 20 }} />
                  </Card>
                </Col>
                <Col span={8}>
                  <Card size="small">
                    <Statistic title="电池 SOC" value={battery?.soc ?? battery?.batterySoc ?? 0} suffix="%" valueStyle={{ color: '#52c41a', fontSize: 20 }} />
                  </Card>
                </Col>
              </Row>
            )}
            {!modelFields?.cache && (
              <Descriptions column={2} size="small" bordered style={{ marginBottom: 16 }}>
                <Descriptions.Item label="交流电压">{ac?.voltage ?? '-'} V</Descriptions.Item>
                <Descriptions.Item label="交流电流">{ac?.current ?? '-'} A</Descriptions.Item>
                <Descriptions.Item label="电网频率">{ac?.frequency ?? '-'} Hz</Descriptions.Item>
                <Descriptions.Item label="功率因数">{ac?.powerFactor ?? '-'}</Descriptions.Item>
                <Descriptions.Item label="当日发电">{energy?.daily_pv ?? realtime?.daily_energy ?? '-'} kWh</Descriptions.Item>
                <Descriptions.Item label="累计发电">{energy?.total_pv ?? '-'} kWh</Descriptions.Item>
                <Descriptions.Item label="电池电压">{battery?.voltage ?? '-'} V</Descriptions.Item>
                <Descriptions.Item label="电池电流">{battery?.current ?? '-'} A</Descriptions.Item>
                <Descriptions.Item label="逆变器温度">{sys?.temp_inv ?? realtime?.internal_temperature ?? '-'} °C</Descriptions.Item>
                <Descriptions.Item label="工作状态">{sys?.state ?? realtime?.work_state ?? '-'}</Descriptions.Item>
              </Descriptions>
            )}
            <Card title="功率趋势" size="small">
              {telemetry.length > 0 ? (
                <ReactEChartsCore option={telemetryChartOption} style={{ height: 250 }} echarts={echarts} />
              ) : (
                <Empty description="暂无遥测数据" />
              )}
            </Card>
          </>
        ) : (
          <Spin tip="加载中..." />
        )}
      </Drawer>
    </div>
  )
}

export default DeviceMonitorPage
