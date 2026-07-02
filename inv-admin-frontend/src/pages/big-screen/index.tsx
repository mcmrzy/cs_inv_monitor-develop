import './big-screen.css'
import { useEffect, useMemo, useCallback, useRef, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import ReactECharts from 'echarts-for-react'
import { Tag, Progress, Tooltip } from 'antd'
import {
  FullscreenOutlined,
  FullscreenExitOutlined,
  WifiOutlined,
  ExclamationCircleOutlined,
  DashboardOutlined,
  EnvironmentOutlined,
  ThunderboltOutlined,
  BarChartOutlined,
  AlertOutlined,
  RocketOutlined,
} from '@ant-design/icons'
import { MapContainer, TileLayer, Marker, Tooltip as LeafletTooltip, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { dashboardApi } from '@/services/dashboardApi'
import api from '@/services/api'
import useTranslation from '@/hooks/useTranslation'
import { getAlarmLevelDisplay, parseFaultCode, ALARM_CODE_LEVEL, TASK_STATUS_MAP } from '@/utils/constants'
import { StatCard, PanelHeader, GaugeChart, ScrollingList, RankingList } from './components'

// ──────────────────────────────────────────────────────────
// Types
// ──────────────────────────────────────────────────────────
interface DeviceStats { total: number; online: number; offline: number; fault: number }
interface PowerFlow { pvPower: number; gridPower: number; batteryPower: number; loadPower: number }
interface TrendPoint { timeLabel: string; energy: number; loadEnergy?: number }
interface AlarmItem {
  id: number; device_sn: string; alarm_level: number; fault_code: string
  fault_message: string; status: string; occurred_at: string
}
interface OtaTask {
  id: number; firmwareVersion: string; status: string; progress: number
  totalDevices: number; successCount: number; failedCount: number; createdAt: string
}
interface SystemHealth { uptimeSeconds: number; database: boolean; redis: boolean; mqtt: boolean; version: string }
interface CarbonReduction { co2: number; trees: number }
interface BigScreenData {
  deviceStats: DeviceStats; todayEnergy: number; totalEnergy: number
  recentAlarms: AlarmItem[]; stationRanking: any[]
  powerFlow: PowerFlow; trendData: TrendPoint[]
  otaTasks: OtaTask[]; systemHealth: SystemHealth
  onlineRate: number; carbonReduction: CarbonReduction
}
interface StationListItem {
  id: number; name: string; latitude: number; longitude: number
  capacity: number; status: number; province: string; city: string
}
interface StationSummaryStation {
  station_id: number; station_name: string; device_count: number; online_count: number
  fault_count: number; total_power: number; today_energy: number; total_energy: number
}
interface StationSummary {
  stations: StationSummaryStation[]
  summary: { totalStations: number; totalDevices: number; onlineDevices: number; todayGeneration: number; totalGeneration: number; faultDevices: number; totalIncome: number }
}

// ──────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────
function createColoredIcon(color: string) {
  return L.divIcon({
    className: 'custom-marker',
    html: `<div style="width:14px;height:14px;border-radius:50%;background:${color};border:2px solid rgba(255,255,255,0.7);box-shadow:0 0 8px ${color}99;"></div>`,
    iconSize: [14, 14],
    iconAnchor: [7, 7],
  })
}

function getStationColor(onlineCount: number, deviceCount: number): string {
  if (!deviceCount) return '#666'
  if (onlineCount >= deviceCount) return '#52c41a'
  if (onlineCount === 0) return '#ff4d4f'
  return '#fa8c16'
}

function formatUptime(seconds: number): string {
  const d = Math.floor(seconds / 86400)
  const h = Math.floor((seconds % 86400) / 3600)
  return d > 0 ? `${d}d ${h}h` : `${h}h`
}

// ──────────────────────────────────────────────────────────
// MapAutoRotate — cycles through stations every 30s
// ──────────────────────────────────────────────────────────
function MapAutoRotate({ stations }: { stations: StationListItem[] }) {
  const map = useMap()
  const indexRef = useRef(0)

  useEffect(() => {
    const validStations = stations.filter(
      s => s.latitude != null && s.longitude != null && !(s.latitude === 0 && s.longitude === 0),
    )
    if (validStations.length === 0) return

    const timer = setInterval(() => {
      const s = validStations[indexRef.current % validStations.length]
      map.flyTo([s.latitude, s.longitude], 8, { duration: 1.5 })
      indexRef.current += 1
    }, 30000)

    return () => clearInterval(timer)
  }, [map, stations])

  return null
}

// ──────────────────────────────────────────────────────────
// ClockDisplay — isolated, updates via DOM ref (no React re-render)
// ──────────────────────────────────────────────────────────
function ClockDisplay() {
  const spanRef = useRef<HTMLSpanElement>(null)
  useEffect(() => {
    const tick = () => {
      if (!spanRef.current) return
      const now = new Date()
      const h = String(now.getHours()).padStart(2, '0')
      const m = String(now.getMinutes()).padStart(2, '0')
      const s = String(now.getSeconds()).padStart(2, '0')
      spanRef.current.textContent = `${h}:${m}:${s}`
    }
    tick()
    const timer = setInterval(tick, 1000)
    return () => clearInterval(timer)
  }, [])
  return <span ref={spanRef} className="bs-header-time" />
}

// ──────────────────────────────────────────────────────────
// StatusDot
// ──────────────────────────────────────────────────────────
function StatusDot({ ok, label }: { ok: boolean; label: string }) {
  return (
    <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
      <span style={{
        width: 6, height: 6, borderRadius: '50%',
        background: ok ? '#52c41a' : '#ff4d4f',
        boxShadow: ok ? '0 0 4px #52c41a' : '0 0 4px #ff4d4f',
      }} />
      {label}
    </span>
  )
}

// ──────────────────────────────────────────────────────────
// BigScreenPage
// ──────────────────────────────────────────────────────────
const BigScreenPage: React.FC = () => {
  const { t } = useTranslation()
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [todayDate, setTodayDate] = useState('')

  // ── Fullscreen ──────────────────────────────────────────
  useEffect(() => {
    const handleFsChange = () => setIsFullscreen(!!document.fullscreenElement)
    document.addEventListener('fullscreenchange', handleFsChange)
    return () => document.removeEventListener('fullscreenchange', handleFsChange)
  }, [])

  useEffect(() => {
    const now = new Date()
    setTodayDate(`${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`)
  }, [])

  const toggleFullscreen = useCallback(() => {
    if (document.fullscreenElement) document.exitFullscreen()
    else document.documentElement.requestFullscreen()
  }, [])

  // ── Data fetching (parallel) ────────────────────────────
  const { data: mainData } = useQuery({
    queryKey: ['big-screen'],
    queryFn: () => dashboardApi.getBigScreen().then(res => (res.data?.data ?? res.data) as BigScreenData),
    refetchInterval: 10000,
  })

  const { data: stationsData } = useQuery({
    queryKey: ['stations-list'],
    queryFn: () => api.get('/stations').then(res => (res.data?.data ?? res.data) as StationListItem[]),
    refetchInterval: 30000,
  })

  const { data: rankingData } = useQuery({
    queryKey: ['station-ranking'],
    queryFn: () => dashboardApi.getStationRanking({ period: 'today', limit: 5 }).then(res => res.data?.data ?? res.data),
    refetchInterval: 30000,
  })

  const { data: stationSummary } = useQuery({
    queryKey: ['stations-summary'],
    queryFn: () => api.get('/stations/summary').then(res => (res.data?.data ?? res.data) as StationSummary),
    refetchInterval: 30000,
  })

  // ── Null-safe data extraction ───────────────────────────
  const deviceStats: DeviceStats = mainData?.deviceStats ?? { total: 0, online: 0, offline: 0, fault: 0 }
  const onlineRate = mainData?.onlineRate ?? 0
  const carbon = mainData?.carbonReduction ?? { co2: 0, trees: 0 }
  const powerFlow: PowerFlow = mainData?.powerFlow ?? { pvPower: 0, gridPower: 0, batteryPower: 0, loadPower: 0 }
  const trendData: TrendPoint[] = mainData?.trendData ?? []
  const alerts: AlarmItem[] = mainData?.recentAlarms ?? []
  const otaTasks: OtaTask[] = mainData?.otaTasks ?? []
  const systemHealth: SystemHealth = mainData?.systemHealth ?? { uptimeSeconds: 0, database: true, redis: true, mqtt: true, version: '' }
  const stations: StationListItem[] = Array.isArray(stationsData) ? stationsData : []
  const summary = stationSummary?.summary ?? { totalStations: 0, totalDevices: 0, onlineDevices: 0, todayGeneration: 0, totalGeneration: 0, faultDevices: 0, totalIncome: 0 }

  // Build ranking items
  const rankingItems = useMemo(() => {
    const raw = Array.isArray(rankingData) ? rankingData : []
    return raw.map((r: any) => ({
      name: r.stationName ?? r.station_name ?? '',
      value: r.todayEnergy ?? r.today_energy ?? 0,
      unit: 'kWh',
    }))
  }, [rankingData])

  // Build map summary lookup
  const summaryMap = useMemo(() => {
    const map = new Map<number, StationSummaryStation>()
    ;(stationSummary?.stations ?? []).forEach(s => map.set(s.station_id, s))
    return map
  }, [stationSummary])

  // ── Critical alert count ────────────────────────────────
  const criticalCount = useMemo(() => {
    return alerts.filter(a => {
      const code = parseFaultCode(a.fault_code)
      const level = code >= 0 ? ALARM_CODE_LEVEL[code] : undefined
      return level === 3 || (level == null && (String(a.alarm_level) === '3' || a.alarm_level === 3))
    }).length
  }, [alerts])

  // ── ECharts options ─────────────────────────────────────
  const sankeyOption = useMemo(() => ({
    backgroundColor: 'transparent',
    tooltip: { trigger: 'item' as const, triggerOn: 'mousemove' as const },
    series: [{
      type: 'sankey' as const,
      layout: 'none' as const,
      emphasis: { focus: 'adjacency' as const },
      nodeAlign: 'left' as const,
      lineStyle: { color: 'gradient' as const, curveness: 0.5 },
      label: { color: '#aab', fontSize: 9 },
      data: [
        { name: t('bigScreen.pv'), itemStyle: { color: '#ffa726' } },
        { name: t('bigScreen.inverter'), itemStyle: { color: '#42a5f5' } },
        { name: t('bigScreen.grid'), itemStyle: { color: '#66bb6a' } },
        { name: t('bigScreen.storage'), itemStyle: { color: '#ab47bc' } },
        { name: t('bigScreen.load'), itemStyle: { color: '#ef5350' } },
      ],
      links: [
        { source: t('bigScreen.pv'), target: t('bigScreen.inverter'), value: Math.max(powerFlow.pvPower, 0.1) },
        { source: t('bigScreen.inverter'), target: t('bigScreen.grid'), value: Math.max(powerFlow.gridPower, 0.1) },
        { source: t('bigScreen.inverter'), target: t('bigScreen.storage'), value: Math.max(powerFlow.batteryPower, 0.1) },
        { source: t('bigScreen.inverter'), target: t('bigScreen.load'), value: Math.max(powerFlow.loadPower, 0.1) },
      ],
    }],
  }), [powerFlow, t])

  const trendOption = useMemo(() => ({
    backgroundColor: 'transparent',
    tooltip: { trigger: 'axis' as const },
    legend: {
      data: [t('bigScreen.generation_kWh'), t('bigScreen.load')],
      textStyle: { color: '#aab', fontSize: 10 },
      top: 0,
    },
    grid: { left: 40, right: 20, top: 28, bottom: 24 },
    xAxis: {
      type: 'category' as const,
      data: trendData.map(d => d.timeLabel),
      axisLine: { lineStyle: { color: '#334' } },
      axisLabel: { color: '#889', fontSize: 10 },
    },
    yAxis: {
      type: 'value' as const,
      name: 'kWh',
      nameTextStyle: { color: '#889', fontSize: 10 },
      axisLine: { lineStyle: { color: '#334' } },
      axisLabel: { color: '#889', fontSize: 10 },
      splitLine: { lineStyle: { color: '#1a1a2e' } },
    },
    series: [
      {
        name: t('bigScreen.generation_kWh'),
        type: 'bar' as const,
        data: trendData.map(d => d.energy),
        itemStyle: {
          borderRadius: [3, 3, 0, 0],
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: '#4fc3f7' },
              { offset: 1, color: '#0288d1' },
            ],
          },
        },
        barWidth: '50%',
      },
      {
        name: t('bigScreen.load'),
        type: 'line' as const,
        data: trendData.map(d => d.loadEnergy ?? 0),
        smooth: true,
        lineStyle: { color: '#ffa726', width: 2 },
        itemStyle: { color: '#ffa726' },
        symbol: 'circle',
        symbolSize: 4,
      },
    ],
  }), [trendData, t])

  const pieOption = useMemo(() => ({
    backgroundColor: 'transparent',
    tooltip: { trigger: 'item' as const, formatter: '{b}: {c} ({d}%)' },
    legend: {
      bottom: 0,
      textStyle: { color: '#aab', fontSize: 10 },
      data: [t('bigScreen.online'), t('bigScreen.offline'), t('bigScreen.fault')],
    },
    color: ['#52c41a', '#666', '#ff4d4f'],
    series: [{
      type: 'pie' as const,
      radius: ['50%', '70%'],
      center: ['50%', '43%'],
      label: { show: false },
      emphasis: { label: { show: true, fontSize: 13, fontWeight: 'bold', color: '#fff' } },
      data: [
        { value: deviceStats.online, name: t('bigScreen.online') },
        { value: deviceStats.offline, name: t('bigScreen.offline') },
        { value: deviceStats.fault, name: t('bigScreen.fault') },
      ],
    }],
  }), [deviceStats.online, deviceStats.offline, deviceStats.fault, t])

  // ── Map center ──────────────────────────────────────────
  const defaultCenter: [number, number] = [35.86, 104.19]
  const mapCenter: [number, number] = stations.length > 0
    ? [stations[0].latitude ?? 35.86, stations[0].longitude ?? 104.19]
    : defaultCenter

  // ── Alert renderItem ────────────────────────────────────
  const renderAlertItem = useCallback((alert: AlarmItem) => {
    const config = getAlarmLevelDisplay(alert.fault_code, alert.alarm_level)
    const dotClass = config.color === '#ff4d4f'
      ? 'bs-alert-item-dot bs-alert-item-dot--danger'
      : config.color === '#fa8c16'
        ? 'bs-alert-item-dot bs-alert-item-dot--warning'
        : 'bs-alert-item-dot bs-alert-item-dot--info'
    return (
      <div className="bs-alert-item" key={alert.id}>
        <div className={dotClass} />
        <div className="bs-alert-item-content">
          <div className="bs-alert-item-title">
            <Tag color={config.color} style={{ fontSize: 10, margin: 0, marginRight: 4 }}>{config.label}</Tag>
            {alert.device_sn} — {alert.fault_message}
          </div>
          <div className="bs-alert-item-time">
            {alert.occurred_at?.replace('T', ' ').substring(0, 19)}
          </div>
        </div>
      </div>
    )
  }, [])

  // ── RENDER ──────────────────────────────────────────────
  return (
    <div className="bs-container bs-animate-fade-in">
      {/* ── Header ───────────────────────────────────────── */}
      <div className="bs-header">
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div className="bs-animate-pulse" style={{
            width: 32, height: 32, borderRadius: '50%',
            background: 'radial-gradient(circle, #00d4ff, #0077b6)',
            boxShadow: '0 0 12px rgba(0,180,255,0.6)',
            flexShrink: 0,
          }} />
          <span className="bs-header-title">{t('bigScreen.title')}</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 20 }}>
          <span style={{ color: '#889', fontSize: 12 }}>{todayDate}</span>
          <ClockDisplay />
          <div style={{
            background: 'rgba(0,0,0,0.3)', borderRadius: 4, padding: '4px 12px',
            border: '1px solid rgba(255,255,255,0.1)', display: 'flex', alignItems: 'center', gap: 6,
          }}>
            <WifiOutlined style={{ color: '#52c41a', fontSize: 14 }} />
            <span style={{ color: '#52c41a', fontSize: 13, fontWeight: 600 }}>
              {t('bigScreen.onlineRate')} {onlineRate.toFixed(1)}%
            </span>
          </div>
          <Tooltip title={isFullscreen ? t('bigScreen.exitFullscreen') : t('bigScreen.enterFullscreen')}>
            <div onClick={toggleFullscreen} style={{ cursor: 'pointer', padding: '4px 8px', background: 'rgba(255,255,255,0.05)', borderRadius: 4, display: 'flex', alignItems: 'center' }}>
              {isFullscreen
                ? <FullscreenExitOutlined style={{ color: '#aaa', fontSize: 18 }} />
                : <FullscreenOutlined style={{ color: '#aaa', fontSize: 18 }} />}
            </div>
          </Tooltip>
        </div>
      </div>

      {/* ── Left Column ──────────────────────────────────── */}
      <div className="bs-left">
        {/* KPI 2x2 grid */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
          <StatCard icon={<DashboardOutlined />} label={t('bigScreen.deviceTotal')} value={deviceStats.total} color="#4fc3f7" />
          <StatCard icon={<WifiOutlined />} label={t('bigScreen.deviceOnline')} value={deviceStats.online} color="#52c41a" />
          <StatCard icon={<ExclamationCircleOutlined />} label={t('bigScreen.deviceFault')} value={deviceStats.fault} color="#ff4d4f" />
          <StatCard icon={<EnvironmentOutlined />} label={t('bigScreen.carbonReduction')} value={carbon.co2.toLocaleString()} unit="kg" color="#66bb6a" />
        </div>

        {/* Device Health panel */}
        <div className="bs-panel bs-panel-glow">
          <PanelHeader title={t('bigScreen.deviceHealth')} icon={<ThunderboltOutlined />} />
          <div className="bs-panel-body" style={{ display: 'flex', gap: 8 }}>
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
              <GaugeChart value={onlineRate} label={t('bigScreen.onlineRateGauge')} />
            </div>
            <div style={{ flex: 1 }}>
              <ReactECharts option={pieOption} style={{ height: '100%' }} />
            </div>
          </div>
        </div>

        {/* Station TOP5 */}
        <div className="bs-panel">
          <PanelHeader title={t('bigScreen.stationTop5')} icon={<BarChartOutlined />} />
          <div className="bs-panel-body">
            <RankingList items={rankingItems} emptyText={t('bigScreen.noStationRanking')} />
          </div>
        </div>
      </div>

      {/* ── Center Map ───────────────────────────────────── */}
      <div className="bs-center">
        <div className="bs-panel bs-panel-glow" style={{ height: '100%', position: 'relative' }}>
          {/* Map overlay stats */}
          <div style={{
            position: 'absolute', top: 12, left: 12, zIndex: 1000,
            background: 'rgba(10,15,30,0.85)', padding: '6px 12px', borderRadius: 4,
            border: '1px solid rgba(255,255,255,0.1)', display: 'flex', gap: 16,
          }}>
            <div>
              <div style={{ color: '#889', fontSize: 10 }}>{t('bigScreen.totalStations')}</div>
              <div style={{ color: '#00d4ff', fontSize: 16, fontWeight: 700 }}>{summary.totalStations}</div>
            </div>
            <div>
              <div style={{ color: '#889', fontSize: 10 }}>{t('bigScreen.totalPower')}</div>
              <div style={{ color: '#ffa726', fontSize: 16, fontWeight: 700 }}>
                {((summary.totalDevices ?? 0) > 0
                  ? (stationSummary?.stations ?? []).reduce((sum, s) => sum + (s.total_power ?? 0), 0) / 1000
                  : 0
                ).toFixed(1)} <span style={{ fontSize: 10, fontWeight: 400 }}>kW</span>
              </div>
            </div>
          </div>
          <MapContainer
            center={mapCenter}
            zoom={5}
            style={{ width: '100%', height: '100%', background: '#0d1b2a' }}
            zoomControl={false}
            attributionControl={false}
          >
            <TileLayer url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png" />
            <MapAutoRotate stations={stations} />
            {stations
              .filter(s => s.latitude != null && s.longitude != null && !(s.latitude === 0 && s.longitude === 0))
              .map(station => {
                const sInfo = summaryMap.get(station.id)
                const onlineCount = sInfo?.online_count ?? 0
                const deviceCount = sInfo?.device_count ?? 0
                const color = getStationColor(onlineCount, deviceCount)
                return (
                  <Marker
                    key={station.id}
                    position={[station.latitude, station.longitude]}
                    icon={createColoredIcon(color)}
                  >
                    <LeafletTooltip direction="top" offset={[0, -8]}>
                      <div style={{ fontSize: 12, minWidth: 120 }}>
                        <div style={{ fontWeight: 700, marginBottom: 3, color: '#e0e0e0' }}>{station.name}</div>
                        <div style={{ color: '#aab' }}>{t('bigScreen.deviceCount')}: {deviceCount}</div>
                        <div style={{ color: '#52c41a' }}>{t('bigScreen.onlineCount')}: {onlineCount}</div>
                        {sInfo && <div style={{ color: '#ffa726' }}>{t('bigScreen.power')}: {(sInfo.total_power / 1000).toFixed(1)} kW</div>}
                      </div>
                    </LeafletTooltip>
                  </Marker>
                )
              })}
          </MapContainer>
        </div>
      </div>

      {/* ── Right Column ─────────────────────────────────── */}
      <div className="bs-right">
        {/* Power Flow Sankey */}
        <div className="bs-panel">
          <PanelHeader title={t('bigScreen.powerFlow')} icon={<ThunderboltOutlined />} />
          <div className="bs-panel-body">
            <ReactECharts option={sankeyOption} style={{ height: '100%' }} />
          </div>
        </div>

        {/* 7-Day Trend */}
        <div className="bs-panel">
          <PanelHeader title={t('bigScreen.sevenDayTrend')} icon={<BarChartOutlined />} />
          <div className="bs-panel-body">
            <ReactECharts option={trendOption} style={{ height: '100%' }} />
          </div>
        </div>

        {/* Realtime Alerts */}
        <div className="bs-panel">
          <PanelHeader
            title={t('bigScreen.realtimeAlerts')}
            icon={<AlertOutlined />}
            extra={<span style={{ color: '#ff4d4f', fontSize: 11 }}>{criticalCount} {t('bigScreen.criticalCount')}</span>}
          />
          <div className="bs-panel-body">
            <ScrollingList
              items={alerts}
              renderItem={renderAlertItem}
              speed={20}
              emptyText={t('bigScreen.noAlerts')}
            />
          </div>
        </div>

        {/* OTA Tasks */}
        <div className="bs-panel">
          <PanelHeader title={t('bigScreen.otaTask')} icon={<RocketOutlined />} />
          <div className="bs-panel-body" style={{ overflowY: 'auto' }}>
            {otaTasks.length === 0 ? (
              <div className="bs-alert-empty">{t('bigScreen.noOtaTasks')}</div>
            ) : (
              otaTasks.map(task => {
                const statusCfg = TASK_STATUS_MAP[task.status] ?? { label: task.status, color: '#d9d9d9' }
                return (
                  <div key={task.id} className="bs-alert-item" style={{ marginBottom: 4 }}>
                    <div className="bs-alert-item-content">
                      <div className="bs-alert-item-title" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                        <Tag color={statusCfg.color} style={{ fontSize: 10, margin: 0 }}>{statusCfg.label}</Tag>
                        <span style={{ fontSize: 11, color: '#ccc' }}>{task.firmwareVersion}</span>
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 4 }}>
                        <Progress
                          percent={task.progress ?? 0}
                          size="small"
                          strokeColor={task.status === 'failed' ? '#ff4d4f' : task.status === 'completed' ? '#52c41a' : '#1677ff'}
                          style={{ flex: 1, margin: 0 }}
                          format={p => <span style={{ color: '#aaa', fontSize: 10 }}>{p}%</span>}
                        />
                        <span style={{ color: '#889', fontSize: 10, flexShrink: 0 }}>
                          {task.successCount}/{task.totalDevices}
                        </span>
                      </div>
                    </div>
                  </div>
                )
              })
            )}
          </div>
        </div>
      </div>

      {/* ── Footer ───────────────────────────────────────── */}
      <div className="bs-footer">
        <div style={{ display: 'flex', alignItems: 'center', gap: 20 }}>
          <span>{t('bigScreen.systemRun')}: {formatUptime(systemHealth.uptimeSeconds)}</span>
          <StatusDot ok={systemHealth.database} label={t('bigScreen.database')} />
          <StatusDot ok={systemHealth.redis} label={t('bigScreen.redisLabel')} />
          <StatusDot ok={systemHealth.mqtt} label={t('bigScreen.mqttLabel')} />
          {systemHealth.version && <span style={{ color: '#556' }}>v{systemHealth.version}</span>}
        </div>
        <div>
          {t('bigScreen.refreshInterval')}: 10s · {t('bigScreen.currentOnlineRate')}: {onlineRate.toFixed(1)}%
        </div>
      </div>
    </div>
  )
}

export default BigScreenPage
