import { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import {
  Card, Tag, Button, Space, Spin, Tabs, Table, Row, Col, Empty, Alert, List, Typography,
} from 'antd'
import {
  ArrowLeftOutlined, DesktopOutlined, CheckCircleOutlined,
  SunOutlined, WarningOutlined, ThunderboltOutlined,
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
import PowerMetricCards from './components/PowerMetricCards'
import EnergySummaryCards from './components/EnergySummaryCards'
import SocialContribution from './components/SocialContribution'
import StationStatisticsTab from './components/StationStatisticsTab'
import StationDevicesTab from './components/StationDevicesTab'

const { Title, Text } = Typography

interface StationDetail {
  id: number
  name?: string
  station_name?: string   // 后端详情 API 可能返回 station_name 而非 name
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
  today_energy?: number   // 后端详情 API 返回 today_energy
  total_energy?: number   // 后端详情 API 返回 total_energy
  month_energy?: number
  year_energy?: number
  pv_power?: number
  load_power?: number
  grid_power?: number
  batt_power?: number
  batt_soc?: number
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

const StationDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { t } = useTranslation()
  const { lang } = useLocaleStore()
  const { timezone } = useTimezoneStore()
  const [activeTab, setActiveTab] = useState('overview')

  const { data: station, isLoading: stationLoading } = useQuery({
    queryKey: ['station', id],
    queryFn: () => api.get(`/stations/${id}`).then(res => res?.data?.data ?? res?.data),
    enabled: !!id,
  })

  // 设备列表（用于实时数据汇总）
  const { data: devices = [] } = useQuery({
    queryKey: ['station-devices-overview', id],
    queryFn: () => api.get('/devices', { params: { station_id: id, pageSize: 999 }, expectedDataShape: 'page' }).then(extractList),
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
    queryFn: () => api.get('/alarms', { params: { station_id: id, pageSize: 20 }, expectedDataShape: 'page' }).then(extractList),
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
  // 兼容后端返回 today_energy/total_energy 或 today_generation/total_generation
  const todayEnergy = statsSummary?.today ?? station.today_generation ?? station.today_energy ?? 0
  const totalEnergy = statsSummary?.total ?? station.total_generation ?? station.total_energy ?? 0

  // 汇总实时功率（优先使用 station 级别的实时功率字段）
  const totalRealtimePower = station.pv_power
    ? (station.pv_power ?? 0)
    : Object.values(realtimeData ?? {}).reduce((sum, rt) => {
        const p = safeNum(rt?.total_active_power ?? rt?.ac_power ?? rt?.power ?? 0)
        return sum + p
      }, 0)

  // 汇总实时 PV 功率、负载功率、电池功率、电网功率
  const aggregatedPv = station.pv_power ?? Object.values(realtimeData ?? {}).reduce((sum, rt) => sum + safeNum(rt?.pv_total_power ?? rt?.pv?.data?.pv_total_power ?? 0), 0)
  const aggregatedLoad = station.load_power ?? Object.values(realtimeData ?? {}).reduce((sum, rt) => sum + safeNum(rt?.load_power ?? rt?.energy_consume ?? 0), 0)
  const aggregatedBatt = station.batt_power ?? Object.values(realtimeData ?? {}).reduce((sum, rt) => sum + safeNum(rt?.battery_power ?? (safeNum(rt?.battery_charge ?? 0) - safeNum(rt?.battery_discharge ?? 0))), 0)
  const aggregatedGrid = station.grid_power ?? Object.values(realtimeData ?? {}).reduce((sum, rt) => sum + safeNum(rt?.grid_power ?? 0), 0)
  const avgSoc = (() => {
    const stationSoc = station.batt_soc ?? 0
    if (stationSoc > 0) return stationSoc
    const socs = Object.values(realtimeData ?? {}).map(rt => safeNum(rt?.soc ?? rt?.batt?.data?.soc ?? 0)).filter(v => v > 0)
    return socs.length > 0 ? socs.reduce((a, b) => a + b, 0) / socs.length : 0
  })()

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
    <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
      {/* a) 天气/容量信息条 */}
      <Card bordered={false} style={{ borderRadius: 12, background: 'linear-gradient(135deg, #eff6ff 0%, #f5f3ff 100%)' }}>
        <Row gutter={[16, 12]} align="middle">
          <Col xs={12} sm={6}>
            <Space><SunOutlined style={{ color: '#f59e0b', fontSize: 18 }} /><Text>{t('station.capacity_kW')}: <strong>{station.capacity ?? '-'} kW</strong></Text></Space>
          </Col>
          <Col xs={12} sm={6}>
            <Space><DesktopOutlined style={{ color: '#1677ff', fontSize: 18 }} /><Text>{t('station.deviceCount')}: <strong>{station.device_count ?? 0}</strong></Text></Space>
          </Col>
          <Col xs={12} sm={6}>
            <Space><CheckCircleOutlined style={{ color: '#52c41a', fontSize: 18 }} /><Text>{t('station.onlineCount')}: <strong style={{ color: '#52c41a' }}>{station.online_count ?? 0}</strong></Text></Space>
          </Col>
          <Col xs={12} sm={6}>
            <Space>
              <WarningOutlined style={{ color: (station.fault_count ?? 0) > 0 ? '#ff4d4f' : '#8c8c8c', fontSize: 18 }} />
              <Text>{t('station.faultCount')}: <strong style={{ color: (station.fault_count ?? 0) > 0 ? '#ff4d4f' : undefined }}>{station.fault_count ?? 0}</strong></Text>
            </Space>
          </Col>
        </Row>
      </Card>

      {/* b) 能量流图 */}
      <Card bordered={false} style={{ borderRadius: 12 }} title={
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

      {/* c) 功率指标 */}
      <PowerMetricCards totalPower={totalRealtimePower} todayEnergy={todayEnergy} />

      {/* d) 发电量汇总 */}
      <EnergySummaryCards
        monthEnergy={statsSummary?.month ?? station.month_energy ?? 0}
        yearEnergy={statsSummary?.year ?? station.year_energy ?? 0}
        totalEnergy={totalEnergy}
      />

      {/* e) 最近告警（5条） */}
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

      {/* f) 社会贡献 */}
      <SocialContribution totalEnergy={statsSummary?.total ?? station.total_generation ?? station.total_energy ?? 0} />
    </div>
  )

  return (
    <div style={{ padding: '0 0 24px' }}>
      {/* 顶部导航栏 */}
      <Space style={{ marginBottom: 16 }}>
        <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/stations')}>
          {t('common.back')}
        </Button>
        <Title level={4} style={{ margin: 0 }}>{stationName}</Title>
        <Tag color={station.status === 1 ? 'green' : 'red'}>
          {station.status === 1 ? t('station.normal') : t('station.stopped')}
        </Tag>
      </Space>

      {/* 三 Tab：概览 / 统计 / 关联设备 */}
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
          ]}
        />
      </Card>
    </div>
  )
}

export default StationDetailPage
