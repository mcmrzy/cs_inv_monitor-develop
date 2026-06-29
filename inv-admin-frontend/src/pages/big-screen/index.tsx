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
import { dashboardApi } from '@/services/dashboardApi'
import { ALARM_LEVEL_MAP, TASK_STATUS_MAP, getAlarmLevelDisplay, parseFaultCode, FAULT_CODE_SEVERITY } from '@/utils/constants'
import type { ColumnsType } from 'antd/es/table'
import useTranslation from '@/hooks/useTranslation'

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
  recentAlarms: AlertItem[]
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
  const { t } = useTranslation()
  const [currentTime, setCurrentTime] = useState('')
  const [isFullscreen, setIsFullscreen] = useState(false)
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

  // 大屏数据通过 HTTP 轮询获取，每 10 秒刷新
  // 注：后端使用原生 WebSocket (/ws/device/:sn)，不支持 Socket.IO 协议

  const alerts = useMemo(() => {
    return data?.recentAlarms ?? []
  }, [data?.recentAlarms])

  const powerFlow = useMemo(() => {
    return data?.powerFlow ?? { pv: 0, grid: 0, battery: 0, load: 0 }
  }, [data?.powerFlow])

  const otaTasks = useMemo(() => {
    return data?.otaTasks ?? []
  }, [data?.otaTasks])

  const trends = data?.trend ?? []
  const totals = data?.totals ?? { devices: 0, online: 0, offline: 0, fault: 0 }
  const energy = data?.energy ?? { today: 0, total: 0, todayIncome: 0 }
  const carbon = data?.carbonReduction ?? { co2: 0, trees: 0 }
  const onlineRate = data?.onlineRate ?? 0
  const systemHealth = data?.systemHealth ?? { uptime: '0h', db: true, redis: true, mqtt: true }

  const trendOption = useMemo(() => ({
    backgroundColor: 'transparent',
    tooltip: { trigger: 'axis' as const },
    legend: { data: [t('bigScreen.generation_kWh')], textStyle: { color: '#aab' }, top: 0 },
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
        name: t('bigScreen.generation_kWh'),
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
      data: [t('bigScreen.online'), t('bigScreen.offline'), t('bigScreen.fault')],
    },
    color: ['#52c41a', '#666', '#ff4d4f'],
    series: [{
      type: 'pie' as const,
      radius: ['50%', '70%'],
      center: ['50%', '43%'],
      label: { show: false },
      emphasis: { label: { show: true, fontSize: 14, fontWeight: 'bold', color: '#fff' } },
      data: [
        { value: totals.online, name: t('bigScreen.online') },
        { value: totals.offline, name: t('bigScreen.offline') },
        { value: totals.fault, name: t('bigScreen.fault') },
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
        { name: t('bigScreen.pv'), itemStyle: { color: '#ffa726' } },
        { name: t('bigScreen.inverter'), itemStyle: { color: '#42a5f5' } },
        { name: t('bigScreen.grid'), itemStyle: { color: '#66bb6a' } },
        { name: t('bigScreen.storage'), itemStyle: { color: '#ab47bc' } },
        { name: t('bigScreen.load'), itemStyle: { color: '#ef5350' } },
      ],
      links: [
        { source: t('bigScreen.pv'), target: t('bigScreen.inverter'), value: powerFlow.pv || 1 },
        { source: t('bigScreen.inverter'), target: t('bigScreen.grid'), value: powerFlow.grid || 1 },
        { source: t('bigScreen.inverter'), target: t('bigScreen.storage'), value: powerFlow.battery || 1 },
        { source: t('bigScreen.inverter'), target: t('bigScreen.load'), value: powerFlow.load || 1 },
      ],
    }],
  }), [powerFlow])

  const alertColumns: ColumnsType<AlertItem> = [
    {
      title: t('bigScreen.device'),
      key: 'deviceSn',
      width: 100,
      ellipsis: true,
      render: (v: string) => <Text style={{ color: '#ccc', fontSize: 11 }}>{v}</Text>,
    },
    {
      title: t('bigScreen.level'),
      key: 'alarmLevel',
      width: 55,
      render: (_: any, record: any) => {
        const config = getAlarmLevelDisplay(record.fault_code ?? record.faultCode, record.alarm_level ?? record.alarmLevel)
        return <Tag color={config.color} style={{ fontSize: 10, margin: 0 }}>{config.label}</Tag>
      },
    },
    {
      title: t('bigScreen.info'),
      key: 'faultMessage',
      ellipsis: true,
      render: (v: string) => <Text style={{ color: '#bbb', fontSize: 11 }}>{v}</Text>,
    },
    {
      title: t('logs.time'),
      key: 'occurredAt',
      width: 130,
      render: (v: string) => <Text style={{ color: '#999', fontSize: 11 }}>{v?.replace('T', ' ').substring(0, 19)}</Text>,
    },
  ]

  const otaColumns: ColumnsType<OtaItem> = [
    {
      title: t('bigScreen.task'),
      key: 'name',
      width: 90,
      ellipsis: true,
      render: (v: string) => <Text style={{ color: '#ccc', fontSize: 11 }}>{v}</Text>,
    },
    {
      title: t('bigScreen.progress'),
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
      title: t('bigScreen.status'),
      render: (s: string) => {
        const config = TASK_STATUS_MAP[s] ?? { label: s, color: '#d9d9d9' }
        return <Tag color={config.color} style={{ fontSize: 10, margin: 0 }}>{config.label}</Tag>
      },
    },
    {
      title: t('bigScreen.progressCount'),
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
            {t('bigScreen.title')}
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
              {t('bigScreen.onlineRate')} {(onlineRate ?? 0).toFixed(1)}%
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
            { label: t('bigScreen.deviceTotal'), val: totals.devices, icon: <DashboardOutlined />, color: '#4fc3f7' },
            { label: t('bigScreen.deviceOnline'), val: totals.online, icon: <WifiOutlined />, color: '#52c41a' },
            { label: t('bigScreen.deviceFault'), val: totals.fault, icon: <ExclamationCircleOutlined />, color: '#ff4d4f' },
            {
              label: t('bigScreen.carbonReduction'), val: `${carbon.co2.toLocaleString()}kg`, icon: <EnvironmentOutlined />, color: '#66bb6a',
              sub: `≈ ${carbon.trees.toLocaleString()} ${t('bigScreen.trees')}`,
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
          <div style={{ color: '#aab', fontSize: 11, fontWeight: 600, marginBottom: 2 }}>{t('bigScreen.powerFlow')}</div>
          <div style={{ flex: 1, minHeight: 0 }}>
            <ReactECharts option={sankeyOption} style={{ height: '100%' }} />
          </div>
        </div>

        {/* Device Pie */}
        <div style={{
          background: 'rgba(255,255,255,0.03)', borderRadius: 4,
          border: '1px solid rgba(255,255,255,0.06)', padding: 6,
        }}>
          <div style={{ color: '#aab', fontSize: 11, fontWeight: 600, marginBottom: 2 }}>{t('bigScreen.deviceStatus')}</div>
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
          {t('bigScreen.stationMap')}
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
                  <div>{t('bigScreen.deviceInfo', { count: station.deviceCount })}</div>
                  <div>{t('bigScreen.onlineInfo', { count: station.onlineCount })}</div>
                  <div>{t('bigScreen.powerInfo', { power: station.power.toFixed(2) })}</div>
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
            { label: t('bigScreen.todayGeneration'), val: `${energy.today.toLocaleString()} kWh`, color: '#ffa726' },
            { label: t('bigScreen.totalGeneration'), val: `${energy.total.toLocaleString()} kWh`, color: '#42a5f5' },
            { label: t('bigScreen.todayRevenue'), val: `¥${energy.todayIncome.toLocaleString()}`, color: '#66bb6a' },
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
          <div style={{ color: '#aab', fontSize: 11, fontWeight: 600, paddingLeft: 4 }}>{t('bigScreen.todayTrend')}</div>
          <ReactECharts option={trendOption} style={{ height: 'calc(100% - 20px)' }} />
        </div>

        {/* Alert Scrolling */}
        <div style={{
          background: 'rgba(255,255,255,0.03)', borderRadius: 4,
          border: '1px solid rgba(255,255,255,0.06)', padding: 6,
          display: 'flex', flexDirection: 'column', overflow: 'hidden',
        }}>
          <div style={{ color: '#aab', fontSize: 11, fontWeight: 600, marginBottom: 4, display: 'flex', justifyContent: 'space-between' }}>
            <span>{t('bigScreen.realtimeAlerts')}</span>
            <span style={{ color: '#ff4d4f', fontSize: 10 }}>
              {alerts.filter((a) => {
                const code = parseFaultCode(a.faultCode)
                const severity = code >= 0 ? FAULT_CODE_SEVERITY[code] : undefined
                return severity === 'critical' || (severity == null && a.alarmLevel === 'critical')
              }).length} {t('bigScreen.criticalCount')}
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
            rowClassName={(record: AlertItem) => {
              const code = parseFaultCode(record.faultCode)
              const severity = code >= 0 ? FAULT_CODE_SEVERITY[code] : undefined
              const isCritical = severity === 'critical' || (severity == null && record.alarmLevel === 'critical')
              return isCritical ? 'big-screen-alert-critical' : ''
            }}
          />
        </div>

        {/* OTA Tasks */}
        <div style={{
          background: 'rgba(255,255,255,0.03)', borderRadius: 4,
          border: '1px solid rgba(255,255,255,0.06)', padding: 6,
          display: 'flex', flexDirection: 'column', overflow: 'hidden',
        }}>
          <div style={{ color: '#aab', fontSize: 11, fontWeight: 600, marginBottom: 4 }}>{t('bigScreen.otaTask')}</div>
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
          <span>{t('bigScreen.systemRun')}: {systemHealth.uptime}</span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{
              width: 6, height: 6, borderRadius: '50%',
              background: systemHealth.db ? '#52c41a' : '#ff4d4f',
              boxShadow: systemHealth.db ? '0 0 4px #52c41a' : '0 0 4px #ff4d4f',
            }} />
            {t('bigScreen.database')}
          </span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{
              width: 6, height: 6, borderRadius: '50%',
              background: systemHealth.redis ? '#52c41a' : '#ff4d4f',
              boxShadow: systemHealth.redis ? '0 0 4px #52c41a' : '0 0 4px #ff4d4f',
            }} />
            {t('bigScreen.redisLabel')}
          </span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{
              width: 6, height: 6, borderRadius: '50%',
              background: systemHealth.mqtt ? '#52c41a' : '#ff4d4f',
              boxShadow: systemHealth.mqtt ? '0 0 4px #52c41a' : '0 0 4px #ff4d4f',
            }} />
            {t('bigScreen.mqttLabel')}
          </span>
        </div>
        <div>
          {t('bigScreen.refreshInterval')}: 10s · {t('bigScreen.currentOnlineRate')}: {(onlineRate ?? 0).toFixed(1)}%
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
