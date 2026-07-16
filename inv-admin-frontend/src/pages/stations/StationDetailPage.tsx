import { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import {
  Card, Tag, Button, Space, Spin, Tabs, Table, Row, Col, Empty, Progress, Typography,
} from 'antd'
import {
  ArrowLeftOutlined, DesktopOutlined, CheckCircleOutlined,
  SunOutlined, WarningOutlined, ThunderboltOutlined,
  ReloadOutlined, EditOutlined, CloudOutlined, HomeOutlined, TableOutlined,
} from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import api from '@/services/api'
import { deviceApi } from '@/services/deviceApi'
import { getAlarmLevelDisplay, getAlarmMessageI18nKey } from '@/utils/constants'
import { formatInTimezone } from '@/utils/timezone'
import { safeNum } from '@/utils/format'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import useLocaleStore from '@/stores/localeStore'
import EnergyFlowDiagram from './components/EnergyFlowDiagram'
import SocialContribution from './components/SocialContribution'
import StationStatisticsTab from './components/StationStatisticsTab'
import StationDevicesTab from './components/StationDevicesTab'
import StationHistoryTab from './components/StationHistoryTab'

const { Title, Text } = Typography

interface StationDetail {
  id: number
  name?: string
  station_name?: string
  province?: string
  city?: string
  district?: string
  address?: string
  capacity?: number
  panel_count?: number
  battery_capacity?: number
  contact_name?: string
  contact_phone?: string
  install_date?: string
  timezone?: string
  status: number
  user_id?: number
  device_count?: number
  online_count?: number
  fault_count?: number
  today_generation?: number
  total_generation?: number
  today_energy?: number
  total_energy?: number
  month_energy?: number
  year_energy?: number
  pv_power?: number
  load_power?: number
  grid_power?: number
  batt_power?: number
  batt_soc?: number
  today_discharge?: number
  total_discharge?: number
  today_grid_export?: number
  total_grid_export?: number
  today_consumption?: number
  total_consumption?: number
  created_at?: string
}

interface AlarmItem {
  id: string | number
  device_sn?: string
  alarm_level: number | string
  fault_code?: string
  fault_message?: string
  status?: string
  occurred_at?: string
  created_at?: string
}

const extractList = (res: any): any[] => {
  const d = res?.data?.data ?? res?.data ?? []
  if (Array.isArray(d)) return d
  return d?.items ?? d?.list ?? []
}

const ENERGY_CARD_ICONS: Record<string, React.ReactNode> = {
  pv: (
    <div style={{ width: 48, height: 48, borderRadius: 12, background: '#3B82F615', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <SunOutlined style={{ fontSize: 24, color: '#3B82F6' }} />
    </div>
  ),
  battery: (
    <div style={{ width: 48, height: 48, borderRadius: 12, background: '#EC489915', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <ThunderboltOutlined style={{ fontSize: 24, color: '#EC4899' }} />
    </div>
  ),
  grid: (
    <div style={{ width: 48, height: 48, borderRadius: 12, background: '#F59E0B15', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <CloudOutlined style={{ fontSize: 24, color: '#F59E0B' }} />
    </div>
  ),
  load: (
    <div style={{ width: 48, height: 48, borderRadius: 12, background: '#22C55E15', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <HomeOutlined style={{ fontSize: 24, color: '#22C55E' }} />
    </div>
  ),
}

const StationDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { t } = useTranslation()
  const { lang } = useLocaleStore()
  const { timezone } = useTimezoneStore()
  const [activeTab, setActiveTab] = useState('overview')

  const { data: station, isLoading: stationLoading, refetch: refetchStation } = useQuery({
    queryKey: ['station', id],
    queryFn: () => api.get(`/stations/${id}`).then(res => {
      const payload = res?.data?.data ?? res?.data
      // Backend GetByID wraps response in { station: {...}, devices: [...] }
      return payload?.station ?? payload
    }),
    enabled: !!id,
  })

  // 设备列表（用于实时数据汇总）
  const { data: devices = [] } = useQuery({
    queryKey: ['station-devices-overview', id],
    queryFn: () => api.get('/devices', { params: { station_id: id, page_size: 999 }, expectedDataShape: 'page' }).then(extractList),
    enabled: !!id,
  })

  // 实时数据批量获取（用于概览Tab功率/能量展示）
  const { data: realtimeData } = useQuery({
    queryKey: ['station-rt-overview', id],
    queryFn: async () => {
      const results: Record<string, any> = {}
      await Promise.allSettled(
        devices.map(async (dev: any) => {
          try {
            const res = await deviceApi.getRealtime(dev.sn)
            results[dev.sn] = res.data?.data ?? res.data ?? {}
          } catch { /* ignore */ }
        })
      )
      return results
    },
    enabled: !!devices?.length,
    refetchInterval: () => document.visibilityState === 'visible' ? 15000 : false,
  })

  // 告警数据（概览Tab显示最近5条）
  const { data: alarms = [], isLoading: alarmsLoading } = useQuery({
    queryKey: ['station-alarms-overview', id],
    queryFn: () => api.get('/alarms', { params: { station_id: id, page_size: 20 }, expectedDataShape: 'page' }).then(extractList),
    enabled: !!id,
  })

  // 统计数据（用于概览Tab的EnergySummaryCards）
  const { data: statsSummary } = useQuery({
    queryKey: ['station-stats-summary', id],
    queryFn: async () => {
      const res = await api.get(`/stations/${id}/statistics`, {
        expectedDataShape: 'array',
        params: {
          start_date: (() => { const d = new Date(); d.setFullYear(d.getFullYear() - 1); return d.toISOString().split('T')[0] })(),
          end_date: new Date().toISOString().split('T')[0],
          period: 'day',
        }
      })
      const raw = res?.data?.data ?? res?.data ?? []
      const arr = Array.isArray(raw) ? raw : []
      const todayStr = new Date().toISOString().split('T')[0]
      const monthStr = todayStr.substring(0, 7)
      const yearStr = todayStr.substring(0, 4)
      let todayVal = 0, monthVal = 0, yearVal = 0, totalVal = 0
      arr.forEach((item: any) => {
        const v = safeNum(item?.daily_pv ?? item?.value ?? item?.energy_produce ?? 0)
        const date = item.time || item.date || ''
        totalVal += v
        if (date.startsWith(todayStr)) todayVal = v
        if (date.startsWith(monthStr)) monthVal += v
        if (date.startsWith(yearStr)) yearVal += v
      })
      return { today: todayVal, month: monthVal, year: yearVal, total: totalVal }
    },
    enabled: !!id,
  })

  if (stationLoading) {
    return (
      <div style={{ textAlign: 'center', padding: 100 }}>
        <Spin size="large" />
      </div>
    )
  }

  if (!station) {
    return <Empty description={t('station.notFound')} />
  }

  // 兼容后端返回 station_name 或 name
  const stationName = station.name || station.station_name || ''
  // 兼容后端返回 today_energy/total_energy 或 today_generation/total_generation（0视为无数据）
  const todayEnergy = statsSummary?.today || station.today_energy || station.today_generation || 0
  const totalEnergy = statsSummary?.total || station.total_energy || station.total_generation || 0

  // 从设备列表计算 fault_count（后端 GetByID 未返回此字段）
  const faultCount = station.fault_count ?? devices.filter((d: any) => d.status === 2).length

  // 汇总实时功率（优先使用 station 级别的实时功率字段，0视为无数据回退到设备聚合）
  const totalRealtimePower = (station.pv_power || 0) > 0
    ? station.pv_power!
    : Object.values(realtimeData ?? {}).reduce((sum, rt) => {
        const p = safeNum(rt?.total_active_power ?? rt?.ac_power ?? rt?.power ?? 0)
        return sum + p
      }, 0)

  // 汇总实时 PV 功率、负载功率、电池功率、电网功率（0视为无数据，回退到设备聚合）
  const aggregatedPv = (station.pv_power || 0) > 0 ? station.pv_power! : Object.values(realtimeData ?? {}).reduce((sum, rt) => sum + safeNum(rt?.pv_total_power ?? rt?.pv_power_total ?? rt?.pv1_power ?? 0), 0)
  const aggregatedLoad = (station.load_power || 0) > 0 ? station.load_power! : Object.values(realtimeData ?? {}).reduce((sum, rt) => sum + safeNum(rt?.load_power ?? rt?.ac_power ?? rt?.energy_consume ?? 0), 0)
  const aggregatedBatt = (station.batt_power || 0) !== 0 ? station.batt_power! : Object.values(realtimeData ?? {}).reduce((sum, rt) => sum + safeNum(rt?.battery_power ?? (safeNum(rt?.battery_charge ?? rt?.charge_power ?? 0) - safeNum(rt?.battery_discharge ?? rt?.discharge_power ?? 0))), 0)
  const aggregatedGrid = (station.grid_power || 0) !== 0 ? station.grid_power! : Object.values(realtimeData ?? {}).reduce((sum, rt) => sum + safeNum(rt?.grid_power ?? rt?.ac_power ?? 0), 0)
  const avgSoc = (() => {
    const stationSoc = station.batt_soc || 0
    if (stationSoc > 0) return stationSoc
    const socs = Object.values(realtimeData ?? {}).map(rt => safeNum(rt?.soc ?? rt?.battery_soc ?? 0)).filter(v => v > 0)
    return socs.length > 0 ? socs.reduce((a, b) => a + b, 0) / socs.length : 0
  })()

  // 从设备实时数据中提取 PV1/PV2 分路、电池电压、电网电压/频率（数据已被 normalizeRealtimeData 展平）
  const firstDeviceRt = Object.values(realtimeData ?? {})[0] as any
  const pvPower1 = safeNum(firstDeviceRt?.pv1_power ?? 0)
  const pvVoltage1 = safeNum(firstDeviceRt?.pv1_voltage ?? 0)
  const pvPower2 = safeNum(firstDeviceRt?.pv2_power ?? 0)
  const pvVoltage2 = safeNum(firstDeviceRt?.pv2_voltage ?? 0)
  const battVoltage = safeNum(firstDeviceRt?.battery_voltage ?? firstDeviceRt?.voltage ?? 0)
  const gridVoltage = safeNum(firstDeviceRt?.grid_voltage ?? firstDeviceRt?.ac_voltage ?? 0)
  const gridFreq = safeNum(firstDeviceRt?.grid_frequency ?? firstDeviceRt?.ac_frequency ?? 0)

  // 最后更新时间
  const lastUpdateTime = realtimeData ? new Date().toLocaleTimeString(lang === 'zh' ? 'zh-CN' : 'en-US', { hour: '2-digit', minute: '2-digit' }) : '--'

  // 4宫格能量卡片数据
  const energyCards: Array<{
    key: string; label: string; color: string;
    today: number | undefined; total: number | undefined;
    todayLabel: string; totalLabel: string; unit: string;
    todayDisplay?: string; totalDisplay?: string;
  }> = [
    {
      key: 'pv',
      label: t('station.solarProduction'),
      color: '#3B82F6',
      today: todayEnergy,
      total: totalEnergy,
      todayLabel: t('station.todayGeneration'),
      totalLabel: t('station.cumulative'),
      unit: 'kWh',
    },
    {
      key: 'battery',
      label: t('station.batteryDischarge'),
      color: '#EC4899',
      today: station.today_discharge,
      total: station.total_discharge,
      todayLabel: t('station.power'),
      totalLabel: 'SOC',
      unit: 'kWh',
      // 后端不返回 today_discharge/total_discharge，改为展示实时功率和SOC
      todayDisplay: station.today_discharge != null ? `${(station.today_discharge ?? 0).toFixed(1)} kWh` : `${Math.abs(aggregatedBatt).toFixed(0)} W`,
      totalDisplay: station.total_discharge != null ? `${(station.total_discharge ?? 0).toFixed(0)} kWh` : `${Math.round(avgSoc)}%`,
    },
    {
      key: 'grid',
      label: t('station.gridExport'),
      color: '#F59E0B',
      today: station.today_grid_export,
      total: station.total_grid_export,
      todayLabel: t('station.power'),
      totalLabel: t('station.cumulative'),
      unit: 'kWh',
      todayDisplay: station.today_grid_export != null ? `${(station.today_grid_export ?? 0).toFixed(1)} kWh` : `${aggregatedGrid.toFixed(0)} W`,
      totalDisplay: station.total_grid_export != null ? `${(station.total_grid_export ?? 0).toFixed(0)} kWh` : '--',
    },
    {
      key: 'load',
      label: t('station.loadConsumption'),
      color: '#22C55E',
      today: station.today_consumption,
      total: station.total_consumption,
      todayLabel: t('station.power'),
      totalLabel: t('station.cumulative'),
      unit: 'kWh',
      todayDisplay: station.today_consumption != null ? `${(station.today_consumption ?? 0).toFixed(1)} kWh` : `${aggregatedLoad.toFixed(0)} W`,
      totalDisplay: station.total_consumption != null ? `${(station.total_consumption ?? 0).toFixed(0)} kWh` : '--',
    },
  ]

  // 告警列表列定义
  const alarmColumns: ColumnsType<AlarmItem> = [
    {
      title: t('common.time'),
      dataIndex: 'occurred_at',
      width: 160,
      render: (v: string, r: AlarmItem) => {
        const time = v || r.created_at
        return time ? formatInTimezone(time, timezone, 'YYYY-MM-DD HH:mm:ss') : '-'
      },
    },
    { title: t('common.deviceSN'), dataIndex: 'device_sn', width: 140 },
    {
      title: t('station.alertLevel'),
      dataIndex: 'alarm_level',
      width: 80,
      render: (v: number | string, record: any) => {
        const cfg = getAlarmLevelDisplay(record.fault_code, v)
        return <Tag color={cfg.color}>{cfg.i18nKey ? t(cfg.i18nKey) : cfg.label}</Tag>
      },
    },
    {
      title: t('station.faultMessage'),
      dataIndex: 'fault_message',
      ellipsis: true,
      render: (message: string, record: AlarmItem) => {
        const key = getAlarmMessageI18nKey(record.fault_code)
        return key ? t(key) : message
      },
    },
  ]

  const recentAlarms = alarms.slice(0, 5)

  /* ==================== 概览 Tab ==================== */
  const renderOverviewTab = () => (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* 4 宫格能量卡片 */}
      <Row gutter={[16, 16]} style={{ marginBottom: 0 }}>
        {energyCards.map((card) => (
          <Col xs={24} sm={12} md={6} key={card.key}>
            <Card bordered={false} style={{ borderRadius: 12, borderLeft: `4px solid ${card.color}`, height: '100%' }} bodyStyle={{ padding: '16px 20px' }}>
              <Row align="middle" gutter={12}>
                <Col>
                  {ENERGY_CARD_ICONS[card.key]}
                </Col>
                <Col flex={1}>
                  <Text type="secondary" style={{ fontSize: 13 }}>{card.label}</Text>
                  <div>
                    <Text strong style={{ fontSize: 20 }}>
                      {card.todayDisplay ?? `${(card.today ?? 0).toFixed(1)} ${card.unit}`}
                    </Text>
                  </div>
                  <Text type="secondary" style={{ fontSize: 12 }}>
                    {card.totalLabel}: {card.totalDisplay ?? `${(card.total ?? 0).toFixed(0)} ${card.unit}`}
                  </Text>
                </Col>
              </Row>
            </Card>
          </Col>
        ))}
      </Row>

      {/* 两列布局：左列能量流图 + 右列系统信息 */}
      <Row gutter={[16, 16]}>
        {/* 左列：能量流图 */}
        <Col xs={24} lg={14}>
          <Card bordered={false} style={{ borderRadius: 12, height: '100%' }} title={
            <Space><ThunderboltOutlined /> {t('station.energyFlow')}</Space>
          } size="small">
            <EnergyFlowDiagram
              pvPower={aggregatedPv}
              loadPower={aggregatedLoad}
              battPower={aggregatedBatt}
              gridPower={aggregatedGrid}
              battSoc={avgSoc}
            />
          </Card>
        </Col>

        {/* 右列：系统详细信息 */}
        <Col xs={24} lg={10}>
          <Card
            bordered={false}
            style={{ borderRadius: 12, marginBottom: 16 }}
            title={<><ThunderboltOutlined /> {t('station.systemInfo')}</>}
            extra={<Text type="secondary" style={{ fontSize: 12 }}>{lastUpdateTime}</Text>}
          >
            {/* PV 输入 */}
            <div style={{ marginBottom: 16, paddingBottom: 16, borderBottom: '1px solid #f0f0f0' }}>
              <Text strong style={{ color: '#3B82F6' }}>{t('station.pvInput')}</Text>
              <Row gutter={16} style={{ marginTop: 8 }}>
                <Col span={12}>
                  <Text type="secondary">PV1:</Text>
                  <Text strong style={{ marginLeft: 8 }}>{pvPower1 > 0 ? `${pvPower1} W` : '--'}</Text>
                  <Text type="secondary" style={{ marginLeft: 8 }}>{pvVoltage1 > 0 ? `${pvVoltage1} V` : ''}</Text>
                </Col>
                <Col span={12}>
                  <Text type="secondary">PV2:</Text>
                  <Text strong style={{ marginLeft: 8 }}>{pvPower2 > 0 ? `${pvPower2} W` : '--'}</Text>
                  <Text type="secondary" style={{ marginLeft: 8 }}>{pvVoltage2 > 0 ? `${pvVoltage2} V` : ''}</Text>
                </Col>
              </Row>
              <Row style={{ marginTop: 4 }}>
                <Col span={24}>
                  <Text type="secondary">{t('station.systemStatus')}: </Text>
                  <Tag color={station.status === 1 ? 'green' : 'red'} style={{ marginLeft: 4 }}>
                    {station.status === 1 ? t('station.normal') : t('station.stopped')}
                  </Tag>
                </Col>
              </Row>
            </div>

            {/* 电池 */}
            <div style={{ marginBottom: 16, paddingBottom: 16, borderBottom: '1px solid #f0f0f0' }}>
              <Row align="middle">
                <Col flex={1}>
                  <Text strong style={{ color: '#EC4899' }}>{t('station.battery')}</Text>
                </Col>
                <Col>
                  <Progress
                    type="circle"
                    percent={Math.round(avgSoc)}
                    size={40}
                    strokeColor={avgSoc > 20 ? '#22c55e' : '#ef4444'}
                  />
                </Col>
              </Row>
              <Row gutter={16} style={{ marginTop: 8 }}>
                <Col span={8}>
                  <Text type="secondary">{t('station.power')}:</Text>{' '}
                  <Text strong>{aggregatedBatt ?? 0} W</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">{t('station.voltage')}:</Text>{' '}
                  <Text strong>{battVoltage > 0 ? `${battVoltage} V` : '--'}</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">SOC:</Text>{' '}
                  <Text strong>{Math.round(avgSoc)}%</Text>
                </Col>
              </Row>
            </div>

            {/* 电网 */}
            <div style={{ marginBottom: 16, paddingBottom: 16, borderBottom: '1px solid #f0f0f0' }}>
              <Text strong style={{ color: '#F59E0B' }}>{t('station.grid')}</Text>
              <Row gutter={16} style={{ marginTop: 8 }}>
                <Col span={8}>
                  <Text type="secondary">{t('station.power')}:</Text>{' '}
                  <Text strong>{aggregatedGrid ?? 0} W</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">{t('station.voltage')}:</Text>{' '}
                  <Text strong>{gridVoltage > 0 ? `${gridVoltage} V` : '--'}</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">{t('station.frequency')}:</Text>{' '}
                  <Text strong>{gridFreq > 0 ? `${gridFreq} Hz` : '--'}</Text>
                </Col>
              </Row>
            </div>

            {/* 负载 */}
            <div>
              <Text strong style={{ color: '#22C55E' }}>{t('station.load')}</Text>
              <Row style={{ marginTop: 8 }}>
                <Col span={12}>
                  <Text type="secondary">{t('station.consumptionPower')}:</Text>{' '}
                  <Text strong>{aggregatedLoad ?? 0} W</Text>
                </Col>
              </Row>
            </div>
          </Card>
        </Col>
      </Row>

      {/* 底部：社会贡献 + 最近告警 */}
      <Row gutter={[16, 16]}>
        <Col xs={24} lg={14}>
          <SocialContribution totalEnergy={statsSummary?.total ?? station.total_generation ?? station.total_energy ?? 0} />
        </Col>
        <Col xs={24} lg={10}>
          <Card bordered={false} style={{ borderRadius: 12 }} size="small" title={
            <Space><WarningOutlined style={{ color: '#ff4d4f' }} /> {t('station.recentAlarms')}</Space>
          } extra={alarms.length > 5 && <a onClick={() => setActiveTab('overview')}>{t('station.viewAll')}</a>}>
            {recentAlarms.length > 0 ? (
              <Table<AlarmItem>
                columns={alarmColumns}
                dataSource={recentAlarms}
                rowKey="id"
                size="small"
                pagination={false}
                scroll={{ x: 600 }}
              />
            ) : (
              <Empty description={t('station.noAlarms')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
            )}
          </Card>
        </Col>
      </Row>
    </div>
  )

  return (
    <div style={{ padding: '0 0 24px' }}>
      {/* 顶部导航栏 */}
      <Row align="middle" gutter={16} style={{ marginBottom: 16 }}>
        <Col flex="auto">
          <Space>
            <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/stations')}>
              {t('common.back')}
            </Button>
            <Title level={4} style={{ margin: 0 }}>{stationName}</Title>
            <Tag color={station.status === 1 ? 'green' : 'red'}>
              {station.status === 1 ? t('station.normal') : t('station.stopped')}
            </Tag>
            <Text type="secondary" style={{ fontSize: 13 }}>
              <DesktopOutlined style={{ marginRight: 4 }} />
              {t('station.deviceCount')}: {station.device_count ?? 0} / {t('station.onlineCount')}: {station.online_count ?? 0}
            </Text>
            {(faultCount ?? 0) > 0 && (
              <Tag color="red" icon={<WarningOutlined />}>{faultCount} {t('station.fault')}</Tag>
            )}
          </Space>
        </Col>
        <Col>
          <Space>
            <Button icon={<EditOutlined />} size="small" onClick={() => navigate(`/stations/${id}/edit`)}>
              {t('common.edit')}
            </Button>
            <Button icon={<ReloadOutlined />} size="small" onClick={() => refetchStation()}>
              {t('common.refresh')}
            </Button>
          </Space>
        </Col>
      </Row>

      {/* 四 Tab：概览 / 统计 / 关联设备 / 历史数据 */}
      <Card bordered={false} style={{ borderRadius: 12 }}>
        <Tabs
          activeKey={activeTab}
          onChange={setActiveTab}
          items={[
            {
              key: 'overview',
              label: t('station.overview'),
              children: renderOverviewTab(),
            },
            {
              key: 'statistics',
              label: t('station.genStats'),
              children: (
                <StationStatisticsTab stationId={station.id} timezone={station.timezone || 'Asia/Shanghai'} />
              ),
            },
            {
              key: 'devices',
              label: `${t('station.deviceList')} (${devices.length || station.device_count || 0})`,
              children: (
                <StationDevicesTab stationId={station.id} timezone={station.timezone || 'Asia/Shanghai'} />
              ),
            },
            {
              key: 'history',
              label: <span><TableOutlined /> {t('station.historyData')}</span>,
              children: <StationHistoryTab stationId={station.id} timezone={station.timezone || 'Asia/Shanghai'} />,
            },
          ]}
        />
      </Card>
    </div>
  )
}

export default StationDetailPage
