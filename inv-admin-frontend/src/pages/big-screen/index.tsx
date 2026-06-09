import { useState, useEffect, useMemo, useCallback, useRef } from 'react'
import { useQuery } from '@tanstack/react-query'
import ReactECharts from 'echarts-for-react'
import { Table, Tag, Progress, Typography } from 'antd'
import {
  FullscreenOutlined,
  FullscreenExitOutlined,
  WifiOutlined,
  ExclamationCircleOutlined,
  DashboardOutlined,
  EnvironmentOutlined,
} from '@ant-design/icons'
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { io, Socket } from 'socket.io-client'
import { dashboardApi } from '@/services/dashboardApi'
import { ALARM_LEVEL_MAP, TASK_STATUS_MAP } from '@/utils/constants'
import type { ColumnsType } from 'antd/es/table'

const { Text } = Typography

interface StationItem {
  id: number
  name: string
  lat: number
  lng: number
  deviceCount: number
  onlineCount: number
  power: number
}

interface AlertItem {
  id: number
  deviceSn: string
  alarmLevel: string
  faultCode: string
  faultMessage: string
  status: string
  occurredAt: string
}

interface OtaItem {
  id: string
  name: string
  status: string
  totalDevices: number
  successCount: number
  failedCount: number
  progress: number
  createdAt: string
}

interface TrendItem {
  label: string
  energy: number
}

interface BigScreenData {
  totals: { devices: number; online: number; offline: number; fault: number }
  energy: { today: number; total: number; todayIncome: number }
  carbonReduction: { co2: number; trees: number }
  onlineRate: number
  stations: StationItem[]
  recentAlerts: AlertItem[]
  powerFlow: { pv: number; grid: number; battery: number; load: number }
  trend: TrendItem[]
  otaTasks: OtaItem[]
  systemHealth: { uptime: string; db: boolean; redis: boolean; mqtt: boolean }
}

function createColoredIcon(color: string) {
  return L.divIcon({
    className: 'custom-marker',
    html: `<div style="
      width:14px;height:14px;border-radius:50%;
      background:${color};border:2px solid #fff;
      box-shadow: 0 0 6px ${color}88;
    "></div>`,
    iconSize: [14, 14],
    iconAnchor: [7, 7],
  })
}

function getStationColor(station: StationItem): string {
  if (station.deviceCount === 0) return '#d9d9d9'
  if (station.onlineCount === station.deviceCount) return '#52c41a'
  if (station.onlineCount === 0) return '#ff4d4f'
  return '#fa8c16'
}

function MapFlyTo({ center }: { center: [number, number] }) {
  const map = useMap()
  useEffect(() => {
    map.setView(center, map.getZoom(), { animate: true })
  }, [map, center])
  return null
}

const BigScreenPage: React.FC = () => {
  const [currentTime, setCurrentTime] = useState('')
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [wsAlert, setWsAlert] = useState<AlertItem | null>(null)
  const [wsPower, setWsPower] = useState<{ pv: number; grid: number; battery: number; load: number } | null>(null)
  const [wsOta, setWsOta] = useState<Record<string, { progress: number; status: string }>>({})
  const socketRef = useRef<Socket | null>(null)
  const containerRef = useRef<HTMLDivElement>(null)

  const { data } = useQuery({
    queryKey: ['big-screen'],
    queryFn: () => dashboardApi.getBigScreen().then((res) => (res.data?.data ?? res.data) as BigScreenData),
    refetchInterval: 10000,
  })

  useEffect(() => {
    const tick = () => {
      const now = new Date()
      const h = String(now.getHours()).padStart(2, '0')
      const m = String(now.getMinutes()).padStart(2, '0')
      const s = String(now.getSeconds()).padStart(2, '0')
      setCurrentTime(`${h}:${m}:${s}`)
    }
    tick()
    const timer = setInterval(tick, 1000)
    return () => clearInterval(timer)
  }, [])

  useEffect(() => {
    const handleFsChange = () => setIsFullscreen(!!document.fullscreenElement)
    document.addEventListener('fullscreenchange', handleFsChange)
    return () => document.removeEventListener('fullscreenchange', handleFsChange)
  }, [])

  const toggleFullscreen = useCallback(() => {
    if (document.fullscreenElement) {
      document.exitFullscreen()
    } else {
      document.documentElement.requestFullscreen()
    }
  }, [])

  useEffect(() => {
    const token = (() => {
      try {
        const stored = localStorage.getItem('auth-storage')
        if (stored) {
          const parsed = JSON.parse(stored)
          return parsed?.state?.token ?? ''
        }
      } catch { /* ignore */ }
      return ''
    })()

    const socket = io({ path: '/ws/socket.io', auth: { token } })
    socketRef.current = socket

    socket.on('connect', () => console.log('[WS] big-screen connected'))
    socket.on('alert:new', (alert: AlertItem) => setWsAlert(alert))
    socket.on('telemetry:update', (payload: any) => {
      const d = payload?.data ?? payload
      setWsPower({
        pv: Number(d?.pv_power ?? d?.pvPower ?? 0),
        grid: Number(d?.grid_power ?? d?.gridPower ?? 0),
        battery: Number(d?.battery_power ?? d?.batteryPower ?? 0),
        load: Number(d?.load_power ?? d?.loadPower ?? 0),
      })
    })
    socket.on('ota:progress', (p: { taskId: string; progress: number; status: string }) => {
      setWsOta((prev) => ({ ...prev, [p.taskId]: { progress: p.progress, status: p.status } }))
    })

    return () => {
      socket.disconnect()
    }
  }, [])

  const alerts = useMemo(() => {
    const base = data?.recentAlerts ?? []
    if (wsAlert) {
      const exists = base.some((a) => a.id === wsAlert.id)
      if (!exists) return [wsAlert, ...base].slice(0, 10)
    }
    return base
  }, [data?.recentAlerts, wsAlert])

  const powerFlow = useMemo(() => {
    const base = data?.powerFlow ?? { pv: 0, grid: 0, battery: 0, load: 0 }
    if (wsPower) {
      return {
        pv: base.pv + wsPower.pv,
        grid: base.grid + wsPower.grid,
        battery: base.battery + wsPower.battery,
        load: base.load + wsPower.load,
      }
    }
    return base
  }, [data?.powerFlow, wsPower])

  const otaTasks = useMemo(() => {
    return (data?.otaTasks ?? []).map((t) => {
      const ws = wsOta[t.id]
      if (ws) {
        return { ...t, progress: ws.progress, status: ws.status }
      }
      return t
    })
  }, [data?.otaTasks, wsOta])

  const trends = data?.trend ?? []
  const totals = data?.totals ?? { devices: 0, online: 0, offline: 0, fault: 0 }
  const energy = data?.energy ?? { today: 0, total: 0, todayIncome: 0 }
  const carbon = data?.carbonReduction ?? { co2: 0, trees: 0 }
  const onlineRate = data?.onlineRate ?? 0
  const systemHealth = data?.systemHealth ?? { uptime: '0h', db: true, redis: true, mqtt: true }

  const trendOption = useMemo(() => ({
    backgroundColor: 'transparent',
    tooltip: { trigger: 'axis' as const },
    legend: { data: ['发电量(kWh)'], textStyle: { color: '#aab' }, top: 0 },
    grid: { left: 40, right: 20, top: 30, bottom: 30 },
    xAxis: {
      type: 'category' as const,
      data: trends.map((t) => t.label),
      axisLine: { lineStyle: { color: '#334' } },
      axisLabel: { color: '#889', fontSize: 10 },
    },
    yAxis: {
      type: 'value' as const,
      name: 'kWh',
      nameTextStyle: { color: '#889' },
      axisLine: { lineStyle: { color: '#334' } },
      axisLabel: { color: '#889', fontSize: 10 },
      splitLine: { lineStyle: { color: '#1a1a2e' } },
    },
    series: [
      {
        name: '发电量(kWh)',
        type: 'bar' as const,
        data: trends.map((t) => t.energy),
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
        barWidth: '60%',
      },
    ],
  }), [trends])

  const pieOption = useMemo(() => ({
    backgroundColor: 'transparent',
    tooltip: { trigger: 'item' as const, formatter: '{b}: {c} ({d}%)' },
    legend: {
      bottom: 0,
      textStyle: { color: '#aab', fontSize: 10 },
      data: ['在线', '离线', '故障'],
    },
    color: ['#52c41a', '#666', '#ff4d4f'],
    series: [{
      type: 'pie' as const,
      radius: ['50%', '70%'],
      center: ['50%', '43%'],
      label: { show: false },
      emphasis: { label: { show: true, fontSize: 14, fontWeight: 'bold', color: '#fff' } },
      data: [
        { value: totals.online, name: '在线' },
        { value: totals.offline, name: '离线' },
        { value: totals.fault, name: '故障' },
      ],
    }],
  }), [totals.online, totals.offline, totals.fault])

  const sankeyOption = useMemo(() => ({
    backgroundColor: 'transparent',
    tooltip: { trigger: 'item' as const, triggerOn: 'mousemove' as const },
    series: [{
      type: 'sankey' as const,
      layout: 'none' as const,
      emphasis: { focus: 'adjacency' as const },
      nodeAlign: 'left' as const,
      lineStyle: { color: 'gradient', curveness: 0.5 },
      label: { color: '#aab', fontSize: 9 },
      data: [
        { name: '光伏', itemStyle: { color: '#ffa726' } },
        { name: '逆变器', itemStyle: { color: '#42a5f5' } },
        { name: '电网', itemStyle: { color: '#66bb6a' } },
        { name: '储能', itemStyle: { color: '#ab47bc' } },
        { name: '负载', itemStyle: { color: '#ef5350' } },
      ],
      links: [
        { source: '光伏', target: '逆变器', value: powerFlow.pv || 1 },
        { source: '逆变器', target: '电网', value: powerFlow.grid || 1 },
        { source: '逆变器', target: '储能', value: powerFlow.battery || 1 },
        { source: '逆变器', target: '负载', value: powerFlow.load || 1 },
      ],
    }],
  }), [powerFlow])

  const alertColumns: ColumnsType<AlertItem> = [
    {
      title: '设备',
      dataIndex: 'deviceSn',
      key: 'deviceSn',
      width: 100,
      ellipsis: true,
      render: (v: string) => <Text style={{ color: '#ccc', fontSize: 11 }}>{v}</Text>,
    },
    {
      title: '级别',
      dataIndex: 'alarmLevel',
      key: 'alarmLevel',
      width: 55,
      render: (level: string) => {
        const config = ALARM_LEVEL_MAP[level] ?? { label: level, color: '#d9d9d9' }
        return <Tag color={config.color} style={{ fontSize: 10, margin: 0 }}>{config.label}</Tag>
      },
    },
    {
      title: '信息',
      dataIndex: 'faultMessage',
      key: 'faultMessage',
      ellipsis: true,
      render: (v: string) => <Text style={{ color: '#bbb', fontSize: 11 }}>{v}</Text>,
    },
    {
      title: '时间',
      dataIndex: 'occurredAt',
      key: 'occurredAt',
      width: 130,
      render: (v: string) => <Text style={{ color: '#999', fontSize: 11 }}>{v?.replace('T', ' ').substring(0, 19)}</Text>,
    },
  ]

  const otaColumns: ColumnsType<OtaItem> = [
    {
      title: '任务',
      dataIndex: 'name',
      key: 'name',
      width: 90,
      ellipsis: true,
      render: (v: string) => <Text style={{ color: '#ccc', fontSize: 11 }}>{v}</Text>,
    },
    {
      title: '进度',
      dataIndex: 'progress',
      key: 'progress',
      width: 80,
      render: (v: number, record: OtaItem) => (
        <Progress
          percent={v}
          size="small"
          strokeColor={record.status === 'failed' ? '#ff4d4f' : record.status === 'completed' ? '#52c41a' : '#1677ff'}
          style={{ width: 70, margin: 0 }}
          format={(p) => <span style={{ color: '#aaa', fontSize: 10 }}>{p}%</span>}
        />
      ),
    },
    {
      title: '状态',
      dataIndex: 'status',
      key: 'status',
      width: 55,
      render: (s: string) => {
        const config = TASK_STATUS_MAP[s] ?? { label: s, color: '#d9d9d9' }
        return <Tag color={config.color} style={{ fontSize: 10, margin: 0 }}>{config.label}</Tag>
      },
    },
    {
      title: '进度数',
      key: 'counts',
      width: 50,
      render: (_: any, record: OtaItem) => (
        <Text style={{ color: '#999', fontSize: 10 }}>
          {record.successCount}/{record.totalDevices}
        </Text>
      ),
    },
  ]

  const defaultCenter: [number, number] = [35.86, 104.19]
  const center: [number, number] = data?.stations?.length
    ? [data.stations[0].lat, data.stations[0].lng]
    : defaultCenter

  return (
    <div
      ref={containerRef}
      style={{
        width: '100vw',
        height: '100vh',
        background: 'linear-gradient(135deg, #0a0f1e 0%, #0d1b2a 50%, #1b2838 100%)',
        color: '#e0e0e0',
        overflow: 'hidden',
        fontFamily: "'PingFang SC', 'Microsoft YaHei', sans-serif",
        display: 'grid',
        gridTemplateRows: '56px 1fr 32px',
        gridTemplateColumns: 'repeat(24, 1fr)',
        gap: 6,
        padding: 6,
        boxSizing: 'border-box',
      }}
    >
      {/* ========== Title Bar ========== */}
      <div style={{
        gridRow: 1,
        gridColumn: '1 / -1',
        background: 'linear-gradient(90deg, #0d2137, #132a45, #0d2137)',
        borderRadius: 4,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '0 24px',
        borderBottom: '1px solid rgba(0,150,255,0.3)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{
            width: 32, height: 32, borderRadius: '50%',
            background: 'radial-gradient(circle, #00d4ff, #0077b6)',
            boxShadow: '0 0 12px rgba(0,180,255,0.6)',
          }} />
          <span style={{ fontSize: 20, fontWeight: 700, letterSpacing: 2, background: 'linear-gradient(90deg, #4fc3f7, #e0e0e0)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
            逆变器物联网监控平台
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
          <div style={{
            background: 'rgba(0,0,0,0.3)', borderRadius: 4, padding: '4px 12px',
            border: '1px solid rgba(255,255,255,0.1)',
          }}>
            <span style={{ color: '#00d4ff', fontSize: 22, fontFamily: 'monospace', fontWeight: 700 }}>
              {currentTime}
            </span>
          </div>
          <div style={{
            background: 'rgba(0,0,0,0.3)', borderRadius: 4, padding: '4px 12px',
            border: '1px solid rgba(255,255,255,0.1)', display: 'flex', alignItems: 'center', gap: 6,
          }}>
            <WifiOutlined style={{ color: '#52c41a', fontSize: 14 }} />
            <span style={{ color: '#52c41a', fontSize: 14, fontWeight: 600 }}>
              在线率 {(onlineRate ?? 0).toFixed(1)}%
            </span>
          </div>
          <div
            onClick={toggleFullscreen}
            style={{
              cursor: 'pointer', padding: '4px 8px',
              background: 'rgba(255,255,255,0.05)', borderRadius: 4,
              display: 'flex', alignItems: 'center',
            }}
          >
            {isFullscreen
              ? <FullscreenExitOutlined style={{ color: '#aaa', fontSize: 18 }} />
              : <FullscreenOutlined style={{ color: '#aaa', fontSize: 18 }} />
            }
          </div>
        </div>
      </div>

      {/* ========== Left Column ========== */}
      <div style={{
        gridRow: 2, gridColumn: '1 / 7', display: 'grid',
        gridTemplateRows: '1fr 2fr 2fr', gap: 6,
      }}>
        {/* Stats Cards */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6 }}>
          {[
            { label: '设备总数', val: totals.devices, icon: <DashboardOutlined />, color: '#4fc3f7' },
            { label: '在线设备', val: totals.online, icon: <WifiOutlined />, color: '#52c41a' },
            { label: '故障设备', val: totals.fault, icon: <ExclamationCircleOutlined />, color: '#ff4d4f' },
            {
              label: '碳减排', val: `${carbon.co2.toLocaleString()}kg`, icon: <EnvironmentOutlined />, color: '#66bb6a',
              sub: `≈ ${carbon.trees.toLocaleString()} 棵树`,
            },
          ].map((item, i) => (
            <div
              key={i}
              style={{
                background: 'rgba(255,255,255,0.03)', borderRadius: 4,
                border: '1px solid rgba(255,255,255,0.06)',
                padding: '8px 10px', display: 'flex', flexDirection: 'column', justifyContent: 'center',
                minHeight: 0,
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 4, marginBottom: 2 }}>
                <span style={{ color: item.color, fontSize: 12 }}>{item.icon}</span>
                <span style={{ color: '#889', fontSize: 10 }}>{item.label}</span>
              </div>
              <div style={{
                fontSize: 20, fontWeight: 700, color: item.color,
                lineHeight: 1.2,
              }}>
                {item.val}
              </div>
              {item.sub && (
                <div style={{ color: '#667', fontSize: 9, marginTop: 1 }}>{item.sub}</div>
              )}
            </div>
          ))}
        </div>

        {/* Power Flow Sankey */}
        <div style={{
          background: 'rgba(255,255,255,0.03)', borderRadius: 4,
          border: '1px solid rgba(255,255,255,0.06)', padding: 6,
          display: 'flex', flexDirection: 'column',
        }}>
          <div style={{ color: '#aab', fontSize: 11, fontWeight: 600, marginBottom: 2 }}>功率流向图 (W)</div>
          <div style={{ flex: 1, minHeight: 0 }}>
            <ReactECharts option={sankeyOption} style={{ height: '100%' }} />
          </div>
        </div>

        {/* Device Pie */}
        <div style={{
          background: 'rgba(255,255,255,0.03)', borderRadius: 4,
          border: '1px solid rgba(255,255,255,0.06)', padding: 6,
        }}>
          <div style={{ color: '#aab', fontSize: 11, fontWeight: 600, marginBottom: 2 }}>设备状态分布</div>
          <div style={{ height: 'calc(100% - 20px)' }}>
            <ReactECharts option={pieOption} style={{ height: '100%' }} />
          </div>
        </div>
      </div>

      {/* ========== Center Map ========== */}
      <div style={{
        gridRow: 2, gridColumn: '7 / 18',
        background: 'rgba(255,255,255,0.03)', borderRadius: 4,
        border: '1px solid rgba(255,255,255,0.06)',
        overflow: 'hidden', position: 'relative',
      }}>
        <div style={{
          position: 'absolute', top: 8, left: 12, zIndex: 1000,
          color: '#aab', fontSize: 11, fontWeight: 600,
          background: 'rgba(10,15,30,0.8)', padding: '2px 8px', borderRadius: 3,
        }}>
          电站分布图
        </div>
        <MapContainer
          center={center}
          zoom={5}
          style={{ width: '100%', height: '100%', background: '#0d1b2a' }}
          zoomControl={false}
          attributionControl={false}
        >
          <TileLayer
            url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
          />
          <MapFlyTo center={center} />
          {(data?.stations ?? [])
            .filter((s) => s.lat != null && s.lng != null && !(s.lat === 0 && s.lng === 0))
            .map((station) => (
            <Marker
              key={station.id}
              position={[station.lat, station.lng]}
              icon={createColoredIcon(getStationColor(station))}
            >
              <Popup>
                <div style={{ fontSize: 12, color: '#333' }}>
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>{station.name}</div>
                  <div>设备: {station.deviceCount} 台</div>
                  <div>在线: {station.onlineCount} 台</div>
                  <div>功率: {station.power.toFixed(2)} W</div>
                </div>
              </Popup>
            </Marker>
          ))}
        </MapContainer>
      </div>

      {/* ========== Right Column ========== */}
      <div style={{
        gridRow: 2, gridColumn: '18 / -1', display: 'grid',
        gridTemplateRows: 'auto auto 1fr 1fr', gap: 6,
      }}>
        {/* Energy Cards */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: 6 }}>
          {[
            { label: '今日发电量', val: `${energy.today.toLocaleString()} kWh`, color: '#ffa726' },
            { label: '累计发电量', val: `${energy.total.toLocaleString()} kWh`, color: '#42a5f5' },
            { label: '今日收益', val: `¥${energy.todayIncome.toLocaleString()}`, color: '#66bb6a' },
          ].map((item, i) => (
            <div
              key={i}
              style={{
                background: 'rgba(255,255,255,0.03)', borderRadius: 4,
                border: '1px solid rgba(255,255,255,0.06)',
                padding: '6px 10px', display: 'flex', justifyContent: 'space-between', alignItems: 'center',
              }}
            >
              <span style={{ color: '#889', fontSize: 11 }}>{item.label}</span>
              <span style={{ fontSize: 16, fontWeight: 700, color: item.color }}>{item.val}</span>
            </div>
          ))}
        </div>

        {/* Mini Trend */}
        <div style={{
          background: 'rgba(255,255,255,0.03)', borderRadius: 4,
          border: '1px solid rgba(255,255,255,0.06)', padding: 4,
          height: 160,
        }}>
          <div style={{ color: '#aab', fontSize: 11, fontWeight: 600, paddingLeft: 4 }}>今日发电趋势</div>
          <ReactECharts option={trendOption} style={{ height: 'calc(100% - 20px)' }} />
        </div>

        {/* Alert Scrolling */}
        <div style={{
          background: 'rgba(255,255,255,0.03)', borderRadius: 4,
          border: '1px solid rgba(255,255,255,0.06)', padding: 6,
          display: 'flex', flexDirection: 'column', overflow: 'hidden',
        }}>
          <div style={{ color: '#aab', fontSize: 11, fontWeight: 600, marginBottom: 4, display: 'flex', justifyContent: 'space-between' }}>
            <span>实时告警</span>
            <span style={{ color: '#ff4d4f', fontSize: 10 }}>
              {alerts.filter((a) => a.alarmLevel === 'critical').length} 条严重
            </span>
          </div>
          <Table<AlertItem>
            columns={alertColumns}
            dataSource={alerts}
            rowKey="id"
            pagination={false}
            size="small"
            showHeader={false}
            scroll={{ y: '100%' }}
            style={{ flex: 1, minHeight: 0 }}
            rowClassName={(record: AlertItem) =>
              record.alarmLevel === 'critical' ? 'big-screen-alert-critical' : ''
            }
          />
        </div>

        {/* OTA Tasks */}
        <div style={{
          background: 'rgba(255,255,255,0.03)', borderRadius: 4,
          border: '1px solid rgba(255,255,255,0.06)', padding: 6,
          display: 'flex', flexDirection: 'column', overflow: 'hidden',
        }}>
          <div style={{ color: '#aab', fontSize: 11, fontWeight: 600, marginBottom: 4 }}>OTA 任务</div>
          <Table<OtaItem>
            columns={otaColumns}
            dataSource={otaTasks}
            rowKey="id"
            pagination={false}
            size="small"
            showHeader={false}
            style={{ flex: 1, minHeight: 0 }}
          />
        </div>
      </div>

      {/* ========== Bottom Status Bar ========== */}
      <div style={{
        gridRow: 3, gridColumn: '1 / -1',
        background: 'rgba(255,255,255,0.03)', borderRadius: 4,
        border: '1px solid rgba(255,255,255,0.06)',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 24px', fontSize: 11, color: '#889',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 20 }}>
          <span>系统运行: {systemHealth.uptime}</span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{
              width: 6, height: 6, borderRadius: '50%',
              background: systemHealth.db ? '#52c41a' : '#ff4d4f',
              boxShadow: systemHealth.db ? '0 0 4px #52c41a' : '0 0 4px #ff4d4f',
            }} />
            数据库
          </span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{
              width: 6, height: 6, borderRadius: '50%',
              background: systemHealth.redis ? '#52c41a' : '#ff4d4f',
              boxShadow: systemHealth.redis ? '0 0 4px #52c41a' : '0 0 4px #ff4d4f',
            }} />
            Redis
          </span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{
              width: 6, height: 6, borderRadius: '50%',
              background: systemHealth.mqtt ? '#52c41a' : '#ff4d4f',
              boxShadow: systemHealth.mqtt ? '0 0 4px #52c41a' : '0 0 4px #ff4d4f',
            }} />
            MQTT
          </span>
        </div>
        <div>
          数据刷新间隔: 10s · 当前在线率: {(onlineRate ?? 0).toFixed(1)}%
        </div>
      </div>

      {/* Dark-themed Ant Table overrides via style tag */}
      <style>{`
        .big-screen-alert-critical td {
          background: rgba(255,77,79,0.12) !important;
        }
        .ant-table {
          background: transparent !important;
          color: #ccc !important;
          font-size: 11px !important;
        }
        .ant-table-wrapper .ant-table-thead > tr > th {
          background: rgba(255,255,255,0.04) !important;
          color: #889 !important;
          border-bottom: 1px solid rgba(255,255,255,0.08) !important;
          font-size: 10px !important;
          padding: 2px 6px !important;
        }
        .ant-table-wrapper .ant-table-tbody > tr > td {
          border-bottom: 1px solid rgba(255,255,255,0.04) !important;
          padding: 2px 6px !important;
          background: transparent !important;
          color: #ccc !important;
        }
        .ant-table-wrapper .ant-table-tbody > tr:hover > td {
          background: rgba(255,255,255,0.04) !important;
        }
        .ant-tag {
          font-size: 10px !important;
          line-height: 16px !important;
          padding: 0 4px !important;
        }
        .leaflet-container {
          background: #0d1b2a !important;
        }
        .leaflet-popup-content-wrapper {
          background: rgba(20,30,50,0.95) !important;
          color: #e0e0e0 !important;
          border-radius: 6px !important;
          border: 1px solid rgba(255,255,255,0.1) !important;
        }
        .leaflet-popup-tip {
          background: rgba(20,30,50,0.95) !important;
        }
        .leaflet-popup-content {
          color: #e0e0e0 !important;
          margin: 8px 12px !important;
        }
        .ant-progress-text {
          font-size: 10px !important;
        }
      `}</style>
    </div>
  )
}

export default BigScreenPage
