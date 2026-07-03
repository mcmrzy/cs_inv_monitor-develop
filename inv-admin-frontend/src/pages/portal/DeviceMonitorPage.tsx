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
import dayjs from 'dayjs'
import { formatInTimezone } from '@/utils/timezone'
import { useModelFields, DynamicFieldRenderer, DynamicStatCards } from '@/components/dyna'
import useTranslation from '@/hooks/useTranslation'

echarts.use([LineChart, TooltipComponent, GridComponent, LegendComponent, DataZoomComponent, CanvasRenderer])

const { Title, Text } = Typography

const DeviceMonitorPage: React.FC = () => {
  const { t } = useTranslation()
  const [searchParams] = useSearchParams()
  const highlightSn = searchParams.get('sn') || ''

  const [loading, setLoading] = useState(true)
  const [devices, setDevices] = useState<any[]>([])
  const [selectedSn, setSelectedSn] = useState<string>(highlightSn)
  const [realtime, setRealtime] = useState<any>(null)
  const [deviceDetail, setDeviceDetail] = useState<any>(null)
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

  const fetchDeviceDetail = useCallback(async (sn: string) => {
    try {
      const res = await deviceApi.getDeviceBySn(sn)
      const d = res.data?.data ?? res.data ?? {}
      setDeviceDetail(d.device ?? d)
    } catch { setDeviceDetail(null) }
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
      fetchDeviceDetail(selectedSn)
      fetchTelemetry(selectedSn)
      const timer = setInterval(() => {
        fetchRealtime(selectedSn)
      }, 5000)
      return () => clearInterval(timer)
    }
  }, [selectedSn, fetchRealtime, fetchDeviceDetail, fetchTelemetry])

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
        name: t('portal.activePower'),
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
      title: t('common.model'),
      dataIndex: 'model',
      key: 'model',
      width: 100,
      render: (v: string) => v || '-',
    },
    {
      title: t('common.status'),
      dataIndex: 'status',
      key: 'status',
      width: 80,
      render: (status: any) => {
        const isOnline = status === 1 || status === 'online'
        const isFault = status === 2 || status === 'fault'
        return (
          <Tag color={isOnline ? 'green' : isFault ? 'red' : 'default'}>
            {isOnline ? t('common.online') : isFault ? t('common.fault') : t('common.offline')}
          </Tag>
        )
      },
    },
    {
      title: `${t('portal.ratedPower')}(W)`,
      dataIndex: 'ratedPower',
      key: 'ratedPower',
      width: 110,
      render: (v: number) => v != null ? v : '-',
    },
    {
      title: t('common.firmware'),
      dataIndex: 'firmware_arm',
      key: 'firmware_arm',
      width: 110,
      render: (v: string) => v || '-',
    },
    {
      title: t('common.lastOnline'),
      dataIndex: 'lastOnlineAt',
      key: 'lastOnlineAt',
      width: 160,
      render: (v: string, record: any) => formatInTimezone(v, record.timezone, 'YYYY-MM-DD HH:mm:ss'),
    },
    {
      title: t('common.operation'),
      key: 'action',
      width: 80,
      render: (_: any, record: any) => (
        <a onClick={() => { setSelectedSn(record.sn); setDetailOpen(true) }}>{t('common.detail')}</a>
      ),
    },
  ]

  const rt = realtime?.realtime ?? realtime?.data?.realtime ?? realtime?.data ?? realtime ?? {}
  const ac = rt?.ac ?? {}
  const pv = rt?.pv ?? {}
  const battery = rt?.battery ?? rt?.batt ?? {}
  const sys = rt?.sys_status ?? rt?.sys ?? {}
  const energy = rt?.energy ?? {}

  // 合并设备详情数据到rt中（设备信息存储在数据库，不在Redis实时数据中）
  const mergedData = {
    ...rt,
    ...(deviceDetail ? {
      model: deviceDetail.model || rt.model,
      manufacturer: deviceDetail.manufacturer || rt.manufacturer,
      firmware_arm: deviceDetail.firmware_arm || rt.firmware_arm,
      firmware_esp: deviceDetail.firmware_esp || rt.firmware_esp,
      rated_power: deviceDetail.rated_power || rt.rated_power,
      rated_voltage: deviceDetail.rated_voltage || rt.rated_voltage,
      battery_voltage: deviceDetail.battery_voltage || rt.battery_voltage,
      battery_type: deviceDetail.battery_type || rt.battery_type,
      cell_count: deviceDetail.cell_count || rt.cell_count,
    } : {}),
  }

  return (
    <div style={{ padding: '0 0 24px' }}>
      <Space style={{ marginBottom: 16, width: '100%', justifyContent: 'space-between' }}>
        <Title level={4} style={{ margin: 0 }}>📡 {t('portal.deviceMonitor')}</Title>
        <Tag icon={<ReloadOutlined spin={loading} />} color="processing">
          {t('portal.autoRefresh')}
        </Tag>
      </Space>

      <Table
        columns={columns}
        dataSource={devices}
        rowKey="sn"
        loading={loading}
        size="small"
        pagination={{ pageSize: 20, showSizeChanger: false }}
        onRow={(record) => ({
          onClick: () => { setSelectedSn(record.sn); setDetailOpen(true) },
          style: { cursor: 'pointer' },
        })}
      />

      <Drawer
        title={`${t('portal.deviceDetail')} - ${selectedSn}`}
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
                  data={mergedData}
                />
                <DynamicFieldRenderer
                  fields={modelFields.cache.showFields}
                  data={mergedData}
                  column={2}
                  size="small"
                />
              </>
            ) : (
              <Row gutter={[12, 12]} style={{ marginBottom: 16 }}>
                <Col span={8}>
                  <Card size="small">
                    <Statistic title={t('portal.activePower')} value={ac?.power ?? 0} suffix="W" valueStyle={{ color: '#1677ff', fontSize: 20 }} />
                  </Card>
                </Col>
                <Col span={8}>
                  <Card size="small">
                    <Statistic title={t('portal.pvPower')} value={pv?.power ?? pv?.pvPower ?? 0} suffix="W" valueStyle={{ color: '#fa8c16', fontSize: 20 }} />
                  </Card>
                </Col>
                <Col span={8}>
                  <Card size="small">
                    <Statistic title={t('portal.batterySOC')} value={battery?.soc ?? battery?.batterySoc ?? 0} suffix="%" valueStyle={{ color: '#52c41a', fontSize: 20 }} />
                  </Card>
                </Col>
              </Row>
            )}
            {!modelFields?.cache && (
              <Descriptions column={2} size="small" bordered style={{ marginBottom: 16 }}>
                <Descriptions.Item label={t('portal.acVoltage')}>{ac?.voltage ?? '-'} V</Descriptions.Item>
                <Descriptions.Item label={t('portal.acCurrent')}>{ac?.current ?? '-'} A</Descriptions.Item>
                <Descriptions.Item label={t('portal.gridFreq')}>{ac?.frequency ?? '-'} Hz</Descriptions.Item>
                <Descriptions.Item label={t('portal.powerFactor')}>{ac?.powerFactor ?? '-'}</Descriptions.Item>
                <Descriptions.Item label={t('portal.todayGen')}>{energy?.daily_pv ?? realtime?.daily_energy ?? '-'} kWh</Descriptions.Item>
                <Descriptions.Item label={t('portal.totalGen')}>{energy?.total_pv ?? '-'} kWh</Descriptions.Item>
                <Descriptions.Item label={t('portal.batteryVoltage')}>{battery?.voltage ?? '-'} V</Descriptions.Item>
                <Descriptions.Item label={t('portal.batteryCurrent')}>{battery?.current ?? '-'} A</Descriptions.Item>
                <Descriptions.Item label={t('portal.inverterTemp')}>{sys?.temp_inv ?? realtime?.internal_temperature ?? '-'} °C</Descriptions.Item>
                <Descriptions.Item label={t('portal.workStatus')}>{sys?.state ?? realtime?.work_state ?? '-'}</Descriptions.Item>
              </Descriptions>
            )}
            <Card title={t('portal.powerTrend')} size="small">
              {telemetry.length > 0 ? (
                <ReactEChartsCore option={telemetryChartOption} style={{ height: 250 }} echarts={echarts} />
              ) : (
                <Empty description={t('portal.noTelemetry')} />
              )}
            </Card>
          </>
        ) : (
          <Spin tip={t('portal.loading')} />
        )}
      </Drawer>
    </div>
  )
}

export default DeviceMonitorPage
