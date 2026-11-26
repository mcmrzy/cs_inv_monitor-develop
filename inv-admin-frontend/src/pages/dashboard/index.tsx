import { useMemo, useState } from 'react'
import { useIsFetching, useQuery, useQueryClient } from '@tanstack/react-query'
import { Button, DatePicker, Empty, Segmented, Space, Spin, Tag, Typography } from 'antd'
import { ProCard } from '@ant-design/pro-components'
import {
  ArrowRightOutlined, BarChartOutlined, BellOutlined, DesktopOutlined, ExclamationCircleOutlined,
  LineChartOutlined, ReloadOutlined, ThunderboltOutlined, WifiOutlined,
} from '@ant-design/icons'
import { Link } from 'react-router-dom'
import ReactECharts from '@/lib/echarts'
import { dashboardApi } from '@/services/dashboardApi'
import { getAlarmLevelDisplay, getAlarmMessageI18nKey } from '@/utils/constants'
import { safeNum } from '@/utils/format'
import { formatInTimezone } from '@/utils/timezone'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'
import useTimezoneStore from '@/stores/timezoneStore'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { getRoutePermissions } from '@/router/routeAccess'
import { queryKeys } from '@/utils/queryKeys'
import dayjs from 'dayjs'
import dayjsTimezone from 'dayjs/plugin/timezone'
import './dashboard.css'

const { Title, Text } = Typography

dayjs.extend(dayjsTimezone)

/* ==================== 类型定义 ==================== */

interface AlertItem {
  id: string | number
  device_sn: string
  alarm_level: number | string
  fault_code?: string
  fault_message: string
  occurred_at: string
}

interface StationRankItem {
  stationId: number
  stationName: string
  energy: number
  deviceCount: number
}

interface DeviceCounts {
  total?: number
  online?: number
  offline?: number
  fault?: number
}

interface DashboardStatistics extends DeviceCounts {
  deviceStats?: DeviceCounts
  totalDevices?: number
  onlineDevices?: number
  offlineDevices?: number
  faultDevices?: number
  todayEnergy?: number
  totalEnergy?: number
  recentAlarms?: AlertItem[]
}

interface TrendPoint {
  date: string
  energy?: number
  load?: number
}

type TrendResponse = TrendPoint[] | { data?: TrendPoint[] | { data?: TrendPoint[] } }

const EMPTY_TREND: TrendPoint[] = []
const DASHBOARD_KEY = ['dashboard'] as const
const LIVE_INTERVAL = 15_000
const ANALYSIS_INTERVAL = 60_000

function selectTrend(response: TrendResponse): TrendPoint[] {
  if (Array.isArray(response)) return response
  const data = response?.data
  if (Array.isArray(data)) return data
  return Array.isArray(data?.data) ? data.data : EMPTY_TREND
}

function useDashboardTrend(period: string) {
  return useQuery({
    queryKey: queryKeys.dashboard.trend(period),
    queryFn: () => dashboardApi.getTrend(period).then((r): TrendResponse => r.data),
    select: selectTrend,
    refetchInterval: ANALYSIS_INTERVAL,
    staleTime: ANALYSIS_INTERVAL,
  })
}

function knownNumber(value: unknown): number | undefined {
  if (typeof value !== 'number' && (typeof value !== 'string' || !value.trim())) return
  const number = Number(value)
  return Number.isFinite(number) ? number : undefined
}

const DashboardPage: React.FC = () => {
  const { t, lang } = useTranslation()
  const { timezone } = useTimezoneStore()
  const canViewAlerts = useAuthStore((s) => s.hasAnyPermission(...getRoutePermissions('/alerts')))
  const canViewDevices = useAuthStore((s) => s.hasAnyPermission(...getRoutePermissions('/devices')))
  const queryClient = useQueryClient()
  const isFetching = useIsFetching({ queryKey: DASHBOARD_KEY }) > 0
  const refreshDashboard = () => {
    void queryClient.refetchQueries({ queryKey: DASHBOARD_KEY, type: 'active' }, { cancelRefetch: false })
  }

  const {
    data: stats, dataUpdatedAt: statsUpdatedAt, isLoading: statsLoading, error: statsError,
  } = useQuery({
    queryKey: queryKeys.dashboard.statistics(),
    queryFn: () => dashboardApi.getStatistics().then((r): DashboardStatistics => r.data?.data ?? r.data),
    refetchInterval: LIVE_INTERVAL,
  })

  const ds = stats?.deviceStats ?? stats
  const statisticsOnline = knownNumber(ds?.online ?? stats?.onlineDevices)
  const statisticsOffline = knownNumber(ds?.offline ?? stats?.offlineDevices)
  const statisticsFault = knownNumber(ds?.fault ?? stats?.faultDevices)
  const needsDistribution = Boolean(statsError) || Boolean(stats && (
    statisticsOnline == null || statisticsOffline == null || statisticsFault == null
  ))
  const { data: distribution, error: distError } = useQuery({
    queryKey: queryKeys.dashboard.deviceDistribution(),
    queryFn: () => dashboardApi.getDeviceDistribution().then((r): DeviceCounts => r.data?.data ?? r.data),
    enabled: needsDistribution,
    refetchInterval: LIVE_INTERVAL,
  })

  const fallback = needsDistribution ? distribution : undefined
  const useFallbackSnapshot = Boolean(statsError && fallback)
  const onlineCount = useFallbackSnapshot ? knownNumber(fallback?.online) : statisticsOnline ?? knownNumber(fallback?.online)
  const offlineCount = useFallbackSnapshot ? knownNumber(fallback?.offline) : statisticsOffline ?? knownNumber(fallback?.offline)
  const faultCount = useFallbackSnapshot ? knownNumber(fallback?.fault) : statisticsFault ?? knownNumber(fallback?.fault)
  const sumOfCounts = onlineCount != null && offlineCount != null && faultCount != null
    ? onlineCount + offlineCount + faultCount
    : undefined
  const totalDevices = useFallbackSnapshot ? sumOfCounts : knownNumber(ds?.total ?? stats?.totalDevices) ?? sumOfCounts
  const onlineRate = totalDevices != null && totalDevices > 0 && onlineCount != null ? (onlineCount / totalDevices) * 100 : undefined
  const recentAlerts = Array.isArray(stats?.recentAlarms) ? stats.recentAlarms : undefined

  /* ---------- 功率趋势 ---------- */
  const [selectedFlowDate, setFlowDate] = useState<string | null>(null)
  const flowDate = selectedFlowDate ?? dayjs().tz(timezone).format('YYYY-MM-DD')

  const { data: flowRes, isLoading: flowLoading, error: flowError } = useQuery({
    queryKey: [...DASHBOARD_KEY, 'energyFlow', flowDate, timezone],
    queryFn: () => dashboardApi.getEnergyFlow({
      date: selectedFlowDate ?? dayjs().tz(timezone).format('YYYY-MM-DD'),
    }).then((r) => r.data?.data ?? r.data ?? []),
    refetchInterval: selectedFlowDate ? false : LIVE_INTERVAL,
    staleTime: 0,
    refetchOnMount: true,
  })
  const flowData = (Array.isArray(flowRes) ? flowRes : (flowRes?.data ?? [])) as any[]

  /* ---------- 电量概览 ---------- */
  const [energyOverviewPeriod, setEnergyOverviewPeriod] = useState('day')

  const { data: energyStatsRes, isLoading: energyStatsLoading, error: energyStatsError } = useQuery({
    queryKey: queryKeys.dashboard.energyStats(energyOverviewPeriod),
    queryFn: () => dashboardApi.getEnergyStats({ type: energyOverviewPeriod }).then((r) => r.data),
    refetchInterval: ANALYSIS_INTERVAL,
    staleTime: ANALYSIS_INTERVAL,
  })
  const energyStatsRaw = (energyStatsRes?.data ?? energyStatsRes ?? {}) as any

  const { data: energyTrendData = EMPTY_TREND, isLoading: energyTrendLoading, error: energyTrendError } =
    useDashboardTrend(energyOverviewPeriod)
  const { data: trend30DaysData = EMPTY_TREND, isLoading: trend30DaysLoading, error: trend30DaysError } =
    useDashboardTrend('30days')

  /* 功率趋势图配置 */
  const energyFlowOption = useMemo(() => {
    if (!flowData || flowData.length === 0) return {}
    const times = flowData.map((d: any) => formatInTimezone(d.time, timezone, 'HH:mm'))
    const pvData = flowData.map((d: any) => safeNum(d.pvPower))
    const battChargeData = flowData.map((d: any) => safeNum(d.batteryCharge))
    const battDischargeData = flowData.map((d: any) => -safeNum(d.batteryDischarge))
    const loadData = flowData.map((d: any) => -safeNum(d.loadPower))
    return {
      tooltip: {
        trigger: 'axis' as const,
        axisPointer: { type: 'cross' as const },
        formatter: (params: any) => {
          let html = `<div style="font-weight:600;margin-bottom:4px">${params[0].axisValue}</div>`
          params.forEach((p: any) => {
            const val = Math.abs(p.value)
            html += `<div>${p.marker} ${p.seriesName}: ${val.toFixed(0)} W</div>`
          })
          return html
        },
      },
      legend: { data: [t('dash.pvPower'), t('dash.batteryCharge'), t('dash.batteryDischarge'), t('dash.loadPower')], top: 0, itemGap: 16 },
      grid: { left: '3%', right: '4%', bottom: '12%', top: '45', containLabel: true },
      xAxis: { type: 'category' as const, data: times, axisLabel: { fontSize: 11 } },
      yAxis: {
        type: 'value' as const, name: t('dash.powerUnit'),
        axisLabel: { formatter: (v: number) => Math.abs(v) >= 1000 ? (Math.abs(v) / 1000).toFixed(1) + 'k' : Math.abs(v).toString() },
      },
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        { type: 'slider', start: 0, end: 100, height: 20, bottom: 8 },
      ],
      series: [
        {
          name: t('dash.pvPower'), type: 'line' as const, data: pvData, smooth: true, symbol: 'none',
          lineStyle: { color: '#f59e0b', width: 2 }, itemStyle: { color: '#f59e0b' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(245,158,11,0.3)' }, { offset: 1, color: 'rgba(245,158,11,0.02)' }] } },
        },
        {
          name: t('dash.batteryCharge'), type: 'line' as const, data: battChargeData, smooth: true, symbol: 'none',
          lineStyle: { color: '#22c55e', width: 2 }, itemStyle: { color: '#22c55e' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(34,197,94,0.3)' }, { offset: 1, color: 'rgba(34,197,94,0.02)' }] } },
        },
        {
          name: t('dash.batteryDischarge'), type: 'line' as const, data: battDischargeData, smooth: true, symbol: 'none',
          lineStyle: { color: '#3b82f6', width: 2 }, itemStyle: { color: '#3b82f6' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(59,130,246,0.02)' }, { offset: 1, color: 'rgba(59,130,246,0.2)' }] } },
        },
        {
          name: t('dash.loadPower'), type: 'line' as const, data: loadData, smooth: true, symbol: 'none',
          lineStyle: { color: '#ef4444', width: 2 }, itemStyle: { color: '#ef4444' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(239,68,68,0.02)' }, { offset: 1, color: 'rgba(239,68,68,0.2)' }] } },
        },
      ],
      markLine: { silent: true, lineStyle: { color: '#94a3b8', type: 'solid' as const, width: 1 }, data: [{ yAxis: 0 }], label: { show: false } },
    }
  }, [flowData, timezone, t])

  /* 电量概览柱状图配置 */
  const energyOverviewOption = useMemo(() => {
    const es = energyStatsRaw
    // 接口异常时字段可能缺失或非数组，统一降级为空数组避免 .map 崩溃
    const dates = Array.isArray(es?.dates) ? es.dates : []
    if (dates.length === 0) return {}
    const pvArr = Array.isArray(es?.pv) ? es.pv : []
    const chargeArr = Array.isArray(es?.batteryCharge) ? es.batteryCharge : []
    const dischargeArr = Array.isArray(es?.batteryDischarge) ? es.batteryDischarge : []
    const loadByDate = new Map(energyTrendData.map((item) => [item.date, knownNumber(item.load)]))
    const seriesConfig = [
      { name: t('dash.pvEnergy'), color: '#f59e0b', data: pvArr },
      { name: t('dash.battChargeEnergy'), color: '#22c55e', data: chargeArr },
      { name: t('dash.battDischargeEnergy'), color: '#3b82f6', data: dischargeArr },
      { name: t('dash.loadConsumption'), color: '#ef4444', data: dates.map((date: string) => loadByDate.get(date) ?? null) },
    ]
    return {
      tooltip: { trigger: 'axis' as const, axisPointer: { type: 'shadow' as const } },
      legend: { data: seriesConfig.map((s) => s.name), top: 0, itemGap: 16 },
      grid: { left: '3%', right: '4%', bottom: '12%', top: '45', containLabel: true },
      xAxis: { type: 'category' as const, data: dates, axisLabel: { fontSize: 11 } },
      yAxis: { type: 'value' as const, name: 'kWh' },
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        { type: 'slider', start: 0, end: 100, height: 20, bottom: 8 },
      ],
      series: seriesConfig.map((s) => ({
        name: s.name, type: 'bar' as const,
        data: s.data.map((v: unknown) => v == null ? null : Number(safeNum(v).toFixed(2))),
        itemStyle: { color: s.color, borderRadius: [3, 3, 0, 0] },
        barMaxWidth: 20,
      })),
    }
  }, [energyStatsRaw, energyTrendData, t])

  /* 30日发电趋势图表配置 */
  const trend30DaysOption = useMemo(() => {
    if (!trend30DaysData || trend30DaysData.length === 0) return {}
    return {
      tooltip: {
        trigger: 'axis' as const,
        formatter: (params: any) => {
          const p = Array.isArray(params) ? params[0] : params
          return `${p.axisValue}<br/>${p.marker} ${p.seriesName}: ${Number(p.value).toFixed(2)} kWh`
        },
      },
      grid: { left: '3%', right: '4%', bottom: '12%', top: '45', containLabel: true },
      xAxis: {
        type: 'category' as const,
        data: trend30DaysData.map((d) => dayjs(d.date).format('MM-DD')),
        axisLabel: { fontSize: 11, interval: 2 },
      },
      yAxis: { type: 'value' as const, name: 'kWh' },
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        { type: 'slider', start: 0, end: 100, height: 20, bottom: 8 },
      ],
      series: [{
        name: t('station.genEnergy'),
        type: 'line' as const,
        data: trend30DaysData.map((d) => knownNumber(d.energy) ?? null),
        smooth: true,
        symbol: 'none',
        lineStyle: { color: '#f59e0b', width: 2 },
        itemStyle: { color: '#f59e0b' },
        areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(245,158,11,0.3)' }, { offset: 1, color: 'rgba(245,158,11,0.02)' }] } },
      }],
    }
  }, [trend30DaysData, t])

  /* 电站排行 */
  const [rankingPeriod, setRankingPeriod] = useState('today')
  const { data: rankingRes, isLoading: rankingLoading, error: rankingError } = useQuery({
    queryKey: queryKeys.dashboard.stationRanking(rankingPeriod),
    queryFn: () => dashboardApi.getStationRanking({ period: rankingPeriod, limit: 8 }).then((r) => r.data),
  })
  const rankingData: StationRankItem[] = (() => {
    const raw = rankingRes?.data ?? rankingRes
    return Array.isArray(raw) ? raw : []
  })()

  const queryError = statsError || (needsDistribution && distError) || flowError
    || energyStatsError || energyTrendError || trend30DaysError || rankingError

  const rankingOption = useMemo(() => {
    if (!rankingData || rankingData.length === 0) return {}
    const names = rankingData.map((i) => i.stationName || `${t('dash.stationName')}${i.stationId}`)
    const values = rankingData.map((i) => safeNum(i.energy))
    return {
      tooltip: { trigger: 'axis' as const, axisPointer: { type: 'shadow' as const } },
      grid: { left: '3%', right: '8%', bottom: '3%', top: '8%', containLabel: true },
      xAxis: { type: 'value' as const, name: 'kWh' },
      yAxis: { type: 'category' as const, data: names.reverse(), axisLabel: { width: 80, overflow: 'truncate' as const } },
      series: [{
        type: 'bar' as const,
        data: values.reverse(),
        barWidth: 18,
        itemStyle: {
          borderRadius: [0, 4, 4, 0],
          color: { type: 'linear' as const, x: 0, y: 0, x2: 1, y2: 0,
            colorStops: [{ offset: 0, color: '#1677ff' }, { offset: 1, color: '#4facfe' }] },
        },
        label: { show: true, position: 'right' as const, formatter: (p: any) => Number(p.value).toFixed(1), fontSize: 11 },
      }],
    }
  }, [rankingData, t])

  const formatMetric = (value: number | undefined, digits = 0) => value == null ? '—' : value.toLocaleString(lang, {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  })
  const metrics = [
    {
      label: t('dash.todayGeneration'), value: knownNumber(stats?.todayEnergy), digits: 1, unit: 'kWh',
      icon: <ThunderboltOutlined />, tone: 'primary',
    },
    {
      label: t('dash.onlineRate'), value: onlineRate, digits: 1, unit: '%',
      icon: <WifiOutlined />, tone: 'online',
    },
    {
      label: t('dash.deviceFault'), value: faultCount,
      icon: <ExclamationCircleOutlined />, tone: faultCount ? 'fault' : 'neutral',
    },
    {
      label: t('dash.totalGeneration'), value: knownNumber(stats?.totalEnergy), digits: 1, unit: 'kWh',
      icon: <BarChartOutlined />, tone: 'neutral',
    },
  ]
  const statuses = [
    { key: 'online', label: t('common.online'), count: onlineCount },
    { key: 'offline', label: t('common.offline'), count: offlineCount },
    { key: 'fault', label: t('common.fault'), count: faultCount },
  ]

  return (
    <div className="dashboard">
      <header className="dashboard-header">
        <Typography.Title level={1}>{t('dash.title')}</Typography.Title>
        <div className="dashboard-header-actions">
          {statsUpdatedAt > 0 && (
            <span className="dashboard-updated">
              {t('dash.statisticsUpdated', {
                time: formatInTimezone(new Date(statsUpdatedAt).toISOString(), timezone, 'HH:mm:ss'),
              })}
            </span>
          )}
          <Button aria-label={t('common.refresh')} icon={<ReloadOutlined />} loading={isFetching} onClick={refreshDashboard}>
            {t('common.refresh')}
          </Button>
        </div>
      </header>

      {queryError && (
        <QueryErrorAlert
          error={queryError}
          message={statsError && stats ? t('dash.statisticsStale') : t('dash.dataUnavailable')}
        />
      )}

      <dl className="dashboard-metrics">
        {metrics.map(({ label, value, digits, unit, icon, tone }) => (
          <div key={label} className={`dashboard-metric dashboard-metric--${tone}`}>
            <dt><span className="dashboard-metric-icon" aria-hidden="true">{icon}</span><span className="dashboard-metric-label">{label}</span></dt>
            <dd>
              <span>{formatMetric(value, digits)}</span>
              {value != null && unit && <span className="dashboard-metric-unit">{unit}</span>}
            </dd>
          </div>
        ))}
      </dl>

      <div className="dashboard-operations">
        <section aria-labelledby="dashboard-device-status" className="dashboard-panel">
          <div className="dashboard-panel-heading">
            <h2 id="dashboard-device-status"><DesktopOutlined aria-hidden="true" />{t('dash.deviceStatus')}</h2>
            {canViewDevices && <Link to="/devices" className="dashboard-panel-link">{t('dash.viewDevices')} <ArrowRightOutlined aria-hidden="true" /></Link>}
          </div>
          <div className="dashboard-device-total">
            <strong>{formatMetric(totalDevices)}</strong>
            <span>{t('dash.deviceTotal')}</span>
          </div>
          <div className="dashboard-status-bar" aria-hidden="true">
            {totalDevices != null && totalDevices > 0 && statuses.map(({ key, count }) => (
              <span key={key} className={`dashboard-status--${key}`} style={{ width: `${(count ?? 0) / totalDevices * 100}%` }} />
            ))}
          </div>
          <ul className="dashboard-statuses">
            {statuses.map(({ key, label, count }) => (
              <li key={key}>
                <span className={`dashboard-status-dot dashboard-status--${key}`} aria-hidden="true" />
                <span>{label}</span>
                <strong>{formatMetric(count)}</strong>
              </li>
            ))}
          </ul>
        </section>

        <section aria-labelledby="dashboard-recent-alerts" className="dashboard-panel">
          <div className="dashboard-panel-heading">
            <h2 id="dashboard-recent-alerts"><BellOutlined aria-hidden="true" />{t('dash.recentAlerts')}</h2>
            {canViewAlerts && <Link to="/alerts" className="dashboard-panel-link">{t('dash.viewAlerts')} <ArrowRightOutlined aria-hidden="true" /></Link>}
          </div>
          {statsLoading ? (
            <div className="dashboard-panel-state"><Spin aria-label={t('common.loading')} /></div>
          ) : recentAlerts?.length ? (
            <ul className="dashboard-alerts">
              {recentAlerts.slice(0, 5).map((alarm) => {
                const level = getAlarmLevelDisplay(alarm.fault_code, alarm.alarm_level)
                const messageKey = getAlarmMessageI18nKey(alarm.fault_code)
                return (
                  <li key={alarm.id}>
                    <Tag bordered={false} style={{ backgroundColor: `${level.color}1c` }}>{level.i18nKey ? t(level.i18nKey) : level.label}</Tag>
                    <div className="dashboard-alert-details">
                      <strong>{messageKey ? t(messageKey) : alarm.fault_message || alarm.fault_code || '—'}</strong>
                      <span>{alarm.device_sn}</span>
                    </div>
                    {alarm.occurred_at && (
                      <time dateTime={alarm.occurred_at}>{formatInTimezone(alarm.occurred_at, timezone, 'MM-DD HH:mm')}</time>
                    )}
                  </li>
                )
              })}
            </ul>
          ) : (
            <div className="dashboard-panel-state">
              <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t(recentAlerts ? 'dash.noAlerts' : 'dash.alertsUnavailable')} />
            </div>
          )}
        </section>
      </div>

      <ProCard
        className="dashboard-chart"
        title={<h2><LineChartOutlined aria-hidden="true" />{t('station.genTrend30Days')}</h2>}
        loading={trend30DaysLoading}
      >
        {trend30DaysData.length > 0 ? (
          <ReactECharts option={trend30DaysOption} style={{ height: 272 }} />
        ) : (
          <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t(trend30DaysError ? 'dash.chartUnavailable' : 'dash.noEnergyData')} />
        )}
      </ProCard>

      <ProCard
        className="dashboard-chart"
        title={<h2><LineChartOutlined aria-hidden="true" />{t('dash.powerTrend')}</h2>}
        extra={
          <Space wrap>
            <DatePicker
              aria-label={t('dash.date')}
              value={dayjs(flowDate)}
              onChange={(date) => {
                const next = date?.format('YYYY-MM-DD')
                if (next) setFlowDate(next === dayjs().tz(timezone).format('YYYY-MM-DD') ? null : next)
              }}
              allowClear={false}
            />
            <Button size="small" onClick={() => setFlowDate(dayjs().tz(timezone).subtract(1, 'day').format('YYYY-MM-DD'))}>{t('dash.yesterday')}</Button>
            <Button size="small" onClick={() => setFlowDate(null)}>{t('dash.today')}</Button>
          </Space>
        }
      >
        {flowLoading ? (
          <div className="dashboard-chart-loading"><Spin aria-label={t('common.loading')} /></div>
        ) : flowData.length > 0 ? (
          <ReactECharts option={energyFlowOption} style={{ height: 340 }} />
        ) : (
          <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t(flowError ? 'dash.chartUnavailable' : 'dash.noEnergyData')} />
        )}
      </ProCard>

      <ProCard
        className="dashboard-chart"
        title={<h2><BarChartOutlined aria-hidden="true" />{t('dash.energyOverview')}</h2>}
        extra={
          <Segmented size="small" value={energyOverviewPeriod} onChange={setEnergyOverviewPeriod}
            options={[
              { label: t('dash.last7Days'), value: 'day' },
              { label: t('dash.last30Days'), value: '30days' },
              { label: t('dash.last4Weeks'), value: 'week' },
              { label: t('dash.last12Months'), value: 'month' },
            ]}
          />
        }
      >
        {energyStatsLoading || energyTrendLoading ? (
          <div className="dashboard-chart-loading"><Spin aria-label={t('common.loading')} /></div>
        ) : Array.isArray(energyStatsRaw?.dates) && energyStatsRaw.dates.length > 0 ? (
          <ReactECharts option={energyOverviewOption} style={{ height: 300 }} />
        ) : (
          <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t(energyStatsError ? 'dash.chartUnavailable' : 'dash.noEnergyData')} />
        )}
      </ProCard>

      <ProCard
        className="dashboard-chart"
        title={<h2><BarChartOutlined aria-hidden="true" />{t('dash.stationRank')}</h2>}
        loading={rankingLoading}
        extra={
          <Segmented size="small" value={rankingPeriod} onChange={setRankingPeriod}
            options={[
              { label: t('dash.today'), value: 'today' },
              { label: t('dash.thisWeek'), value: 'week' },
              { label: t('dash.thisMonth'), value: 'month' },
            ]}
          />
        }
      >
        {rankingData.length > 0 ? (
          <ReactECharts option={rankingOption} style={{ height: 300 }} />
        ) : (
          <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t(rankingError ? 'dash.chartUnavailable' : 'dash.noStationData')} />
        )}
      </ProCard>
    </div>
  )
}

export default DashboardPage
