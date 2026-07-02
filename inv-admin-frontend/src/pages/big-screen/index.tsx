import './big-screen.css'
import { useState, useEffect, useRef, useCallback } from 'react'
import { useQuery } from '@tanstack/react-query'
import { FullscreenOutlined, FullscreenExitOutlined } from '@ant-design/icons'
import { dashboardApi } from '@/services/dashboardApi'
import api from '@/services/api'
import { KPIPanel, MapPanel, TrendPanel } from './components'

// ──────────────────────────────────────────────────────────
// Types
// ──────────────────────────────────────────────────────────
interface DeviceStats {
  total: number
  online: number
  offline: number
  fault: number
}

interface TrendPoint {
  timeLabel: string
  energy: number
  loadEnergy?: number
}

interface AlarmItem {
  id: number
  device_sn: string
  alarm_level: number
  fault_code: string
  fault_message: string
  status: string
  occurred_at: string
}

interface CarbonReduction {
  co2: number
  trees: number
}

interface BigScreenData {
  deviceStats: DeviceStats
  todayEnergy: number
  totalEnergy: number
  recentAlarms: AlarmItem[]
  stationRanking: unknown[]
  trendData: TrendPoint[]
  onlineRate: number
  carbonReduction: CarbonReduction
}

interface StationListItem {
  id: number
  station_id?: number
  name: string
  station_name?: string
  latitude: number
  longitude: number
  capacity: number
  total_power?: number
  status: number
  province: string
  city: string
  online_count?: number
  fault_count?: number
}

interface StationSummary {
  stations: StationListItem[]
  summary: {
    totalStations: number
    totalDevices: number
    onlineDevices: number
    todayGeneration: number
    totalGeneration: number
    faultDevices: number
  }
}

// ──────────────────────────────────────────────────────────
// Component
// ──────────────────────────────────────────────────────────
const BigScreenPage: React.FC = () => {
  // 1. 全屏状态
  const [isFullscreen, setIsFullscreen] = useState(false)
  const containerRef = useRef<HTMLDivElement>(null)

  // 2. 时钟（useRef + setInterval 避免 re-render）
  const clockRef = useRef<HTMLSpanElement>(null)
  useEffect(() => {
    const update = () => {
      if (clockRef.current) {
        clockRef.current.textContent = new Date().toLocaleTimeString('zh-CN', { hour12: false })
      }
    }
    update()
    const timer = setInterval(update, 1000)
    return () => clearInterval(timer)
  }, [])

  // 3. 监听 fullscreenchange 同步状态
  useEffect(() => {
    const handler = () => setIsFullscreen(!!document.fullscreenElement)
    document.addEventListener('fullscreenchange', handler)
    return () => document.removeEventListener('fullscreenchange', handler)
  }, [])

  // 4. 数据查询
  const { data: mainData } = useQuery<BigScreenData>({
    queryKey: ['big-screen'],
    queryFn: () => dashboardApi.getBigScreen().then(r => r.data),
    refetchInterval: 10000,
  })

  const { data: stationsRes } = useQuery<StationSummary>({
    queryKey: ['big-screen-stations'],
    queryFn: () => api.get('/stations/summary').then(r => r.data),
    refetchInterval: 30000,
  })

  // 5. 全屏切换
  const toggleFullscreen = useCallback(() => {
    if (!document.fullscreenElement) {
      containerRef.current?.requestFullscreen()
    } else {
      document.exitFullscreen()
    }
  }, [])

  // 6. 数据提取（安全取值）
  const deviceStats = mainData?.deviceStats ?? { total: 0, online: 0, offline: 0, fault: 0 }
  const todayEnergy = mainData?.todayEnergy ?? 0
  const onlineRate = mainData?.onlineRate ?? 0
  const alarmCount = mainData?.recentAlarms?.length ?? 0
  const trendData = mainData?.trendData ?? []
  const recentAlarms = mainData?.recentAlarms ?? []
  const totalCapacity = mainData?.totalEnergy ?? 0

  const stations = stationsRes?.stations?.map((s) => ({
    id: s.station_id ?? s.id,
    name: s.station_name ?? s.name,
    latitude: s.latitude ?? 0,
    longitude: s.longitude ?? 0,
    capacity: s.total_power ?? s.capacity ?? 0,
    status: (s.fault_count ?? 0) > 0 ? 2 : (s.online_count ?? 0) > 0 ? 1 : 0,
  })) ?? []

  const summary = stationsRes?.summary ?? {
    totalStations: 0,
    totalDevices: 0,
    onlineDevices: 0,
  }

  // ──────────────────────────────────────────────────────────
  // Render
  // ──────────────────────────────────────────────────────────
  return (
    <div className="bs-container" ref={containerRef}>
      {/* Header */}
      <header className="bs-header">
        <div className="bs-header-left">
          <img src="/csergylogo.png" className="bs-logo" alt="logo" />
          <span className="bs-header-title">光伏监控大屏</span>
        </div>
        <div className="bs-header-center">
          <span ref={clockRef} className="bs-clock" />
        </div>
        <div className="bs-header-right">
          <span className="bs-online-badge">
            在线率 <strong>{onlineRate.toFixed(1)}%</strong>
          </span>
          <button className="bs-fullscreen-btn" onClick={toggleFullscreen}>
            {isFullscreen ? <FullscreenExitOutlined /> : <FullscreenOutlined />}
          </button>
        </div>
      </header>

      {/* 三栏内容 */}
      <KPIPanel
        todayEnergy={todayEnergy}
        totalCapacity={totalCapacity}
        onlineRate={onlineRate}
        alarmCount={alarmCount}
        deviceStats={deviceStats}
      />

      <MapPanel
        stations={stations}
        summary={summary}
      />

      <TrendPanel
        trendData={trendData}
        recentAlarms={recentAlarms}
      />
    </div>
  )
}

export default BigScreenPage
