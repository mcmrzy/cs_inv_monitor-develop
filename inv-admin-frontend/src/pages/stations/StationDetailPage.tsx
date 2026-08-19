import { useState, useMemo } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import {
  Tag, Button, Space, Spin, Tabs, Row, Col, Empty, Progress, Typography, Select, Statistic,
} from 'antd'
import { ProTable, ProCard } from '@ant-design/pro-components'
import type { ProColumns } from '@ant-design/pro-components'
import {
  ArrowLeftOutlined, DesktopOutlined, CheckCircleOutlined,
  SunOutlined, WarningOutlined, ThunderboltOutlined,
  ReloadOutlined, EditOutlined, CloudOutlined, HomeOutlined, TableOutlined,
} from '@ant-design/icons'
import api from '@/services/api'
import { deviceApi } from '@/services/deviceApi'
import { getAlarmLevelDisplay, getAlarmMessageI18nKey } from '@/utils/constants'
import { formatInTimezone } from '@/utils/timezone'
import { safeNum } from '@/utils/format'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import EnergyFlowDiagram from './components/EnergyFlowDiagram'
import SocialContribution from './components/SocialContribution'
import StationStatisticsTab from './components/StationStatisticsTab'
import StationDevicesTab from './components/StationDevicesTab'
import StationHistoryTab from './components/StationHistoryTab'
import DeviceRealtimeModal from './components/DeviceRealtimeModal'
import DeviceStatsCard from './components/DeviceStatsCard'
import type { DeviceEnergyData } from './components/DeviceStatsCard'

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

/** 实时数据新鲜度窗口：后端 Redis 会在设备离线时回退到“最后有效数据”缓存，
 *  陈旧数据不能当作实时值展示，需按在线状态 + 数据时间戳双重判断 */
const REALTIME_FRESH_WINDOW_MS = 10 * 60 * 1000

interface RtEnvelope {
  online: boolean
  dataTime: unknown
  realtime: Record<string, any>
}

/** 解析数据时间戳（兼容秒/毫秒数字与字符串），无效返回 NaN */
const parseRtTimestamp = (raw: unknown): number => {
  if (raw == null || raw === '') return NaN
  if (typeof raw === 'number') return raw > 1e12 ? raw : raw * 1000
  return Date.parse(String(raw))
}

/** 判断设备实时数据是否可用：设备在线且数据时间戳未过期（无时间戳时退化为仅凭在线状态） */
const isRealtimeFresh = (env?: RtEnvelope): env is RtEnvelope => {
  if (!env || !env.online) return false
  const ts = parseRtTimestamp(env.dataTime ?? env.realtime?.updated_at ?? env.realtime?.timestamp)
  if (!Number.isFinite(ts)) return true
  return Date.now() - ts <= REALTIME_FRESH_WINDOW_MS
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
  const { timezone } = useTimezoneStore()
  const [activeTab, setActiveTab] = useState('overview')
  const [selectedDeviceSn, setSelectedDeviceSn] = useState<string>('all')
  const [modalDeviceSn, setModalDeviceSn] = useState<string | null>(null)

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
      const results: Record<string, RtEnvelope> = {}
      await Promise.allSettled(
        devices.map(async (dev: any) => {
          try {
            const res = await deviceApi.getRealtime(dev.sn)
            // API returns { code:0, data: { device_sn, data_time, online, realtime: {...flattened} } }
            const body = res.data?.data ?? res.data ?? {}
            results[dev.sn] = {
              online: body?.online === true,
              dataTime: body?.data_time ?? null,
              realtime: body?.realtime ?? body ?? {},
            }
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

  // 从设备实时数据聚合能量值 + 实时功率（normalizeRealtimeData 展平后同时存在扁平和嵌套字段）
  // NOTE: useMemo 必须在条件早返回之前调用，否则违反 React Hooks 规则导致 #310 无限渲染
  const deviceEnergy = useMemo(() => {
    // 根据 selectedDeviceSn 决定取单台设备还是聚合全部；
    // 仅统计在线且数据未过期的设备，避免离线时展示 Redis 陈旧缓存值
    let rtList: any[] = []
    if (selectedDeviceSn === 'all') {
      rtList = Object.values(realtimeData ?? {}).filter(isRealtimeFresh).map(env => env.realtime)
    } else {
      const singleEnv = realtimeData?.[selectedDeviceSn]
      if (isRealtimeFresh(singleEnv)) rtList = [singleEnv.realtime]
    }
    if (rtList.length === 0) return null
    let dailyPv = 0, totalPv = 0
    let dailyDischarge = 0, totalDischarge = 0
    let dailyCharge = 0, totalCharge = 0
    let dailyLoad = 0, totalLoad = 0
    let pvPower = 0, loadPower = 0, battPower = 0, gridPowerSum = 0, genPowerSum = 0, battSoc = 0, socCount = 0
    rtList.forEach((rt: any) => {
      // 能量数据 - 扁平字段（已被 normalizeRealtimeData 展平）+ 嵌套回退
      dailyPv += safeNum(rt?.daily_pv ?? rt?.energy?.daily_pv)
      totalPv += safeNum(rt?.total_pv ?? rt?.energy?.total_pv)
      dailyDischarge += safeNum(rt?.daily_discharge ?? rt?.energy?.daily_discharge)
      totalDischarge += safeNum(rt?.total_discharge ?? rt?.energy?.total_discharge)
      dailyLoad += safeNum(rt?.daily_load ?? rt?.energy?.daily_load)
      totalLoad += safeNum(rt?.total_load ?? rt?.energy?.total_load)
      dailyCharge += safeNum(rt?.daily_charge ?? rt?.energy?.daily_charge)
      totalCharge += safeNum(rt?.total_charge ?? rt?.energy?.total_charge)
      // 实时功率
      pvPower += safeNum(rt?.pv_total_power ?? rt?.pv?.pv_power_total)
      loadPower += safeNum(rt?.ac_power ?? rt?.ac?.power)
      battPower += safeNum(rt?.charge_power ?? rt?.batt?.power ?? rt?.battery_power)
      gridPowerSum += safeNum(rt?.grid_power ?? rt?.meter_power)
      // 发电机功率（V2 型号上报 gen 功率或能量时聚合，无数据则为 0）
      genPowerSum += safeNum(rt?.gen_power ?? rt?.gen?.power ?? rt?.gen_energy_daily)
      const soc = safeNum(rt?.battery_soc ?? rt?.soc ?? rt?.batt?.soc)
      if (soc > 0) { battSoc += soc; socCount++ }
    })
    return {
      dailyPv, totalPv, dailyDischarge, totalDischarge,
      dailyLoad, totalLoad, dailyCharge, totalCharge,
      pvPower, loadPower, battPower, gridPower: gridPowerSum,
      genPower: genPowerSum,
      battSoc: socCount > 0 ? battSoc / socCount : 0,
    }
  }, [realtimeData, selectedDeviceSn])

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
  const stationTodayEnergy = statsSummary?.today || station.today_energy || station.today_generation || 0
  const stationTotalEnergy = statsSummary?.total || station.total_energy || station.total_generation || 0

  // 优先使用设备实时数据聚合的能量值，回退到 station 级别字段
  const todayEnergy = (deviceEnergy && deviceEnergy.dailyPv > 0) ? deviceEnergy.dailyPv : stationTodayEnergy
  const totalEnergy = (deviceEnergy && deviceEnergy.totalPv > 0) ? deviceEnergy.totalPv : stationTotalEnergy

  // 从设备列表计算 fault_count（后端 GetByID 未返回此字段）
  const faultCount = station.fault_count ?? devices.filter((d: any) => d.status === 2).length

  // 根据设备实际在线状态判定电站是否在线（而非仅依赖 station.status）
  const hasOnlineDevices = devices.length > 0 && devices.some((d: any) => Number(d.status) === 1)
  const effectiveStationStatus = devices.length > 0
    ? (hasOnlineDevices ? 1 : (faultCount > 0 ? 2 : 0))
    : station.status

  // 是否存在可用（在线且未过期）的实时数据；无则实时功率/能量流图不得展示陈旧缓存值
  const hasFreshRealtime = !!deviceEnergy

  // 汇总实时功率（station 级功率字段同样源自 Redis 缓存，仅在有新鲜实时数据时采信）
  const totalRealtimePower = !hasFreshRealtime
    ? 0
    : (station.pv_power || 0) > 0
      ? station.pv_power!
      : (deviceEnergy?.pvPower ?? 0)

  // 汇总实时 PV 功率、负载功率、电池功率、电网功率（使用 deviceEnergy 聚合，回退到 station 级别）
  const aggregatedPv = !hasFreshRealtime ? 0 : ((station.pv_power || 0) > 0 ? station.pv_power! : (deviceEnergy?.pvPower ?? 0))
  const aggregatedLoad = !hasFreshRealtime ? 0 : ((station.load_power || 0) > 0 ? station.load_power! : (deviceEnergy?.loadPower ?? 0))
  const aggregatedBatt = !hasFreshRealtime ? 0 : ((station.batt_power || 0) !== 0 ? station.batt_power! : (deviceEnergy?.battPower ?? 0))
  // 电网功率：仅使用实际数据，不使用能量守恒公式计算（离网设备无电网数据）
  const gridPowerRaw = !hasFreshRealtime
    ? 0
    : (station.grid_power != null && station.grid_power !== 0)
      ? station.grid_power
      : (deviceEnergy?.gridPower ?? 0)
  const hasGridData = gridPowerRaw !== 0
  const aggregatedGrid = hasGridData ? gridPowerRaw : 0
  // 发电机功率：仅使用实际上报数据（无数据时能量流图隐藏发电机路径）
  const aggregatedGen = deviceEnergy?.genPower ?? 0
  const avgSoc = (() => {
    if (!hasFreshRealtime) return 0
    const stationSoc = station.batt_soc || 0
    if (stationSoc > 0) return stationSoc
    return deviceEnergy?.battSoc ?? 0
  })()

  // 从第一台「在线且数据未过期」的设备实时数据中提取 PV1/PV2 分路、电池电压/电流（兼容扁平与嵌套字段）
  const freshEnvs = Object.entries(realtimeData ?? {}).filter(([, env]) => isRealtimeFresh(env))
  const firstFreshEnv = (devices.length > 0
    ? (freshEnvs.find(([sn]) => sn === devices[0]?.sn)?.[1] ?? freshEnvs[0]?.[1])
    : freshEnvs[0]?.[1])
  const firstDeviceRt = (firstFreshEnv?.realtime ?? {}) as any
  const pvPower1 = safeNum(firstDeviceRt?.pv1_power ?? firstDeviceRt?.pv?.pv1_power)
  const pvVoltage1 = safeNum(firstDeviceRt?.pv1_voltage ?? firstDeviceRt?.pv?.pv1_voltage)
  const pvPower2 = safeNum(firstDeviceRt?.pv2_power ?? firstDeviceRt?.pv?.pv2_power)
  const pvVoltage2 = safeNum(firstDeviceRt?.pv2_voltage ?? firstDeviceRt?.pv?.pv2_voltage)
  const battVoltage = safeNum(firstDeviceRt?.battery_voltage ?? firstDeviceRt?.battery?.voltage ?? firstDeviceRt?.batt?.voltage)
  const battCurrent = safeNum(firstDeviceRt?.battery_current ?? firstDeviceRt?.batt_current ?? firstDeviceRt?.battery?.current ?? firstDeviceRt?.batt?.current)
  // 电网电压/频率：仅使用 meter_/grid_ 前缀字段，不使用 ac_voltage/ac_frequency（那是逆变器输出）
  const gridVoltage = safeNum(firstDeviceRt?.meter_voltage ?? firstDeviceRt?.grid_voltage)
  const gridFreq = safeNum(firstDeviceRt?.meter_frequency ?? firstDeviceRt?.grid_frequency)

  // 最后更新时间：取在线设备上报数据的最新时间戳（而非本地时钟），离线时显示 '--'
  const lastUpdateTime = (() => {
    const stamps = Object.values(realtimeData ?? {})
      .filter(isRealtimeFresh)
      .map(env => parseRtTimestamp(env.dataTime ?? env.realtime?.updated_at ?? env.realtime?.timestamp))
      .filter(ts => Number.isFinite(ts))
    if (stamps.length === 0) return '--'
    return formatInTimezone(new Date(Math.max(...stamps)).toISOString(), timezone, 'HH:mm')
  })()

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
      label: t('station.energyStorageDischarge'),
      color: '#EC4899',
      today: (deviceEnergy?.dailyDischarge ?? 0) > 0 ? deviceEnergy!.dailyDischarge : station.today_discharge,
      total: (deviceEnergy?.totalDischarge ?? 0) > 0 ? deviceEnergy!.totalDischarge : station.total_discharge,
      todayLabel: (deviceEnergy?.dailyDischarge ?? 0) > 0 || station.today_discharge != null ? t('station.todayDischarge') : t('station.power'),
      totalLabel: (deviceEnergy?.totalDischarge ?? 0) > 0 || station.total_discharge != null ? t('station.cumulative') : 'SOC',
      unit: 'kWh',
      // 有能量数据时显示 kWh，否则回退到实时功率和 SOC
      todayDisplay: undefined, // 由 today 字段自动处理
      totalDisplay: (deviceEnergy?.totalDischarge ?? 0) > 0 || station.total_discharge != null ? undefined : `${Math.round(avgSoc)}%`,
    },
    {
      key: 'load',
      label: t('station.loadConsumption'),
      color: '#22C55E',
      today: (deviceEnergy?.dailyLoad ?? 0) > 0 ? deviceEnergy!.dailyLoad : station.today_consumption,
      total: (deviceEnergy?.totalLoad ?? 0) > 0 ? deviceEnergy!.totalLoad : station.total_consumption,
      todayLabel: (deviceEnergy?.dailyLoad ?? 0) > 0 || station.today_consumption != null ? t('station.todayConsumption') : t('station.power'),
      totalLabel: t('station.cumulative'),
      unit: 'kWh',
      todayDisplay: (deviceEnergy?.dailyLoad ?? 0) > 0 || station.today_consumption != null ? undefined : `${Math.round(aggregatedLoad)} W`,
      totalDisplay: (deviceEnergy?.totalLoad ?? 0) > 0 || station.total_consumption != null ? undefined : '--',
    },
    {
      key: 'grid',
      label: hasGridData ? t('station.gridExport') : t('station.grid'),
      color: '#F59E0B',
      today: hasGridData ? station.today_grid_export : undefined,
      total: hasGridData ? station.total_grid_export : undefined,
      todayLabel: hasGridData ? (station.today_grid_export != null ? t('station.todayExport') : t('station.power')) : '',
      totalLabel: hasGridData ? t('station.cumulative') : '',
      unit: 'kWh',
      // 离网设备无电网数据，显示"无电网"
      todayDisplay: hasGridData ? undefined : '--',
      totalDisplay: hasGridData ? (station.total_grid_export != null ? undefined : '--') : '--',
    },
  ]

  // 告警列表列定义
  const alarmColumns: ProColumns<AlarmItem>[] = [
    {
      title: t('common.time'),
      dataIndex: 'occurred_at',
      width: 160,
      render: (_, r: AlarmItem) => {
        const time = r.occurred_at || r.created_at
        return time ? formatInTimezone(time, timezone, 'YYYY-MM-DD HH:mm:ss') : '-'
      },
    },
    { title: t('common.deviceSN'), dataIndex: 'device_sn', width: 140 },
    {
      title: t('station.alertLevel'),
      dataIndex: 'alarm_level',
      width: 80,
      render: (_, record: AlarmItem) => {
        const cfg = getAlarmLevelDisplay(record.fault_code, record.alarm_level)
        return <Tag color={cfg.color}>{cfg.i18nKey ? t(cfg.i18nKey) : cfg.label}</Tag>
      },
    },
    {
      title: t('station.faultMessage'),
      dataIndex: 'fault_message',
      ellipsis: true,
      render: (_, record: AlarmItem) => {
        const key = getAlarmMessageI18nKey(record.fault_code)
        return key ? t(key) : record.fault_message
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
            <ProCard style={{ borderRadius: 12, borderLeft: `4px solid ${card.color}`, height: '100%' }} bodyStyle={{ padding: '16px 20px' }}>
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
            </ProCard>
          </Col>
        ))}
      </Row>

      {/* 两列布局：左列能量流图 + 右列系统信息 */}
      <Row gutter={[16, 16]}>
        {/* 左列：能量流图 */}
        <Col xs={24} lg={14}>
          <ProCard style={{ borderRadius: 12, height: '100%' }} title={
            <Space><ThunderboltOutlined /> {t('station.energyFlow')}</Space>
          } extra={
            <Select
              value={selectedDeviceSn}
              onChange={setSelectedDeviceSn}
              style={{ width: 160 }}
              size="small"
              options={[
                { value: 'all', label: t('station.allDevices') || '全部设备' }, ...devices.map((d: any) => ({ value: d.sn, label: d.sn }))
              ]}
            />
          } size="small">
            {hasFreshRealtime ? (
              <EnergyFlowDiagram
                pvPower={aggregatedPv}
                loadPower={aggregatedLoad}
                battPower={aggregatedBatt}
                gridPower={aggregatedGrid}
                battSoc={avgSoc}
                genPower={aggregatedGen}
              />
            ) : (
              <div style={{ textAlign: 'center', padding: '40px 0', color: '#999' }}>
                <DesktopOutlined style={{ fontSize: 32, marginBottom: 8, display: 'block' }} />
                {t('station.noRealtimeData')}
              </div>
            )}
          </ProCard>
        </Col>

        {/* 右列：系统详细信息 */}
        <Col xs={24} lg={10}>
          <ProCard
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
                  <Text strong style={{ marginLeft: 8 }}>{pvPower1 > 0 ? `${Math.round(pvPower1)} W` : '--'}</Text>
                  <Text type="secondary" style={{ marginLeft: 8 }}>{pvVoltage1 > 0 ? `${pvVoltage1.toFixed(1)} V` : ''}</Text>
                </Col>
                <Col span={12}>
                  <Text type="secondary">PV2:</Text>
                  <Text strong style={{ marginLeft: 8 }}>{pvPower2 > 0 ? `${Math.round(pvPower2)} W` : '--'}</Text>
                  <Text type="secondary" style={{ marginLeft: 8 }}>{pvVoltage2 > 0 ? `${pvVoltage2.toFixed(1)} V` : ''}</Text>
                </Col>
              </Row>
              <Row style={{ marginTop: 4 }}>
                <Col span={24}>
                  <Text type="secondary">{t('station.systemStatus')}: </Text>
                  <Tag color={effectiveStationStatus === 1 ? 'green' : effectiveStationStatus === 2 ? 'red' : 'default'} style={{ marginLeft: 4 }}>
                    {effectiveStationStatus === 1 ? t('station.normal') : effectiveStationStatus === 2 ? t('station.fault') : t('station.offline')}
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
                  <Text strong>{Math.round(aggregatedBatt ?? 0)} W</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">{t('station.voltage')}:</Text>{' '}
                  <Text strong>{battVoltage > 0 ? `${battVoltage.toFixed(1)} V` : '--'}</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">{t('station.current')}:</Text>{' '}
                  <Text strong>{battCurrent !== 0 ? `${battCurrent.toFixed(1)} A` : '--'}</Text>
                </Col>
              </Row>
            </div>

            {/* 电网 - 仅在有实际电网数据时显示数值（离网设备无电网数据） */}
            <div style={{ marginBottom: 16, paddingBottom: 16, borderBottom: '1px solid #f0f0f0' }}>
              <Text strong style={{ color: '#F59E0B' }}>{t('station.grid')}</Text>
              {!hasGridData && gridVoltage === 0 && gridFreq === 0 ? (
                <Row style={{ marginTop: 8 }}>
                  <Col span={24}>
                    <Text type="secondary">{t('station.offGridNoGrid')}</Text>
                  </Col>
                </Row>
              ) : (
                <Row gutter={16} style={{ marginTop: 8 }}>
                  <Col span={8}>
                    <Text type="secondary">{t('station.power')}:</Text>{' '}
                    <Text strong>{hasGridData ? `${Math.round(aggregatedGrid)} W` : '--'}</Text>
                  </Col>
                  <Col span={8}>
                    <Text type="secondary">{t('station.voltage')}:</Text>{' '}
                    <Text strong>{gridVoltage > 0 ? `${gridVoltage.toFixed(1)} V` : '--'}</Text>
                  </Col>
                  <Col span={8}>
                    <Text type="secondary">{t('station.frequency')}:</Text>{' '}
                    <Text strong>{gridFreq > 0 ? `${gridFreq.toFixed(2)} Hz` : '--'}</Text>
                  </Col>
                </Row>
              )}
            </div>

            {/* 负载 */}
            <div>
              <Text strong style={{ color: '#22C55E' }}>{t('station.load')}</Text>
              <Row style={{ marginTop: 8 }}>
                <Col span={12}>
                  <Text type="secondary">{t('station.consumptionPower')}:</Text>{' '}
                  <Text strong>{Math.round(aggregatedLoad ?? 0)} W</Text>
                </Col>
              </Row>
            </div>
          </ProCard>
        </Col>
      </Row>

      {/* 设备运行参数卡片：展示当日能量统计 + 运行时长 */}
      <Row gutter={[16, 16]} style={{ marginBottom: 0 }}>
        <Col span={24}>
          <ProCard 
            style={{ borderRadius: 12 }} 
            title={<><ThunderboltOutlined /> {t('station.deviceEnergyStats')}</>} 
            size="small"
          >
            <DeviceStatsCard data={{
              dailyPv: deviceEnergy?.dailyPv ?? 0,
              totalPv: deviceEnergy?.totalPv ?? 0,
              dailyCharge: deviceEnergy?.dailyCharge ?? 0,
              totalCharge: deviceEnergy?.totalCharge ?? 0,
              dailyDischarge: deviceEnergy?.dailyDischarge ?? 0,
              totalDischarge: deviceEnergy?.totalDischarge ?? 0,
              dailyLoad: deviceEnergy?.dailyLoad ?? 0,
              totalLoad: deviceEnergy?.totalLoad ?? 0,
              runtimeHours: safeNum(firstDeviceRt?.runtime_hours ?? firstDeviceRt?.energy?.runtime_hours),
            } satisfies DeviceEnergyData} />
          </ProCard>
        </Col>
      </Row>

      {/* 查看实时数据详情按钮 */}
      {hasFreshRealtime && (
        <Row gutter={[16, 16]} style={{ marginBottom: 0 }}>
          <Col span={24} style={{ textAlign: 'center' }}>
            <Button
              icon={<DesktopOutlined />}
              onClick={() => {
                if (devices?.[0]?.sn) setModalDeviceSn(devices[0].sn)
              }}
            >
              {t('station.viewRealtimeData')}
            </Button>
          </Col>
        </Row>
      )}

      {/* 底部：社会贡献 + 最近告警 */}
      <Row gutter={[16, 16]}>
        <Col xs={24} lg={14}>
          <SocialContribution totalEnergy={statsSummary?.total ?? station.total_generation ?? station.total_energy ?? 0} />
        </Col>
        <Col xs={24} lg={10}>
          <ProCard style={{ borderRadius: 12 }} size="small" title={
            <Space><WarningOutlined style={{ color: '#ff4d4f' }} /> {t('station.recentAlarms')}</Space>
          } extra={alarms.length > 5 && <a onClick={() => setActiveTab('overview')}>{t('station.viewAll')}</a>}>
            {recentAlarms.length > 0 ? (
              <ProTable<AlarmItem>
                columns={alarmColumns}
                dataSource={recentAlarms}
                rowKey="id"
                size="small"
                search={false}
                options={false}
                pagination={false}
                scroll={{ x: 600 }}
              />
            ) : (
              <Empty description={t('station.noAlarms')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
            )}
          </ProCard>
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
            <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/monitoring')}>
              {t('common.back')}
            </Button>
            <Title level={4} style={{ margin: 0 }}>{stationName}</Title>
            <Tag color={effectiveStationStatus === 1 ? 'green' : effectiveStationStatus === 2 ? 'red' : 'default'}>
              {effectiveStationStatus === 1 ? t('station.normal') : effectiveStationStatus === 2 ? t('station.fault') : t('station.offline')}
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
      <ProCard style={{ borderRadius: 12 }}>
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
      </ProCard>

      {/* 设备实时数据弹窗 */}
      <DeviceRealtimeModal
        open={!!modalDeviceSn}
        deviceSn={modalDeviceSn}
        onClose={() => setModalDeviceSn(null)}
      />
    </div>
  )
}

export default StationDetailPage
