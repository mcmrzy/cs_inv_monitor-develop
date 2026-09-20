/**
 * 设备调试 Tab（DebugTab）
 *
 * 数据源：
 *  - GET  /devices/by-sn/:sn/debug-session   会话查询（10s 轮询兜底，仅页面可见时）：
 *            用于发现「是否存在进行中的会话」；会话期间的实时状态由 SSE 推送
 *  - SSE  /devices/by-sn/:sn/debug-stream    实时推送（useDebugStream）：连接即收到
 *            时间窗快照，之后每个新采样点 ≤2s 推达，会话状态变化也由流内事件更新
 *  - POST /devices/by-sn/:sn/debug-session        开启会话（duration_seconds + request_id 幂等键）
 *  - DELETE /devices/by-sn/:sn/debug-session/:id  停止会话（幂等）
 *
 * 语义约定：
 *  - 关闭页面不调用停止 API：会话由服务端 TTL（expires_at）自动过期；
 *  - 曲线四组：MPPT/PV（PV1/PV2 电压 + Buck1/Buck2 电流）、电池、逆变（母线电压+逆变电流）、
 *    负载（交流输出测点）；电压画左轴(V)、电流画右轴(A)，null 断线不连；
 *  - 本地累积采样点上限 400（超出裁掉最旧）；切换时间窗会重连并由服务端重发快照。
 */
import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Alert, App, Button, Card, Checkbox, Collapse, Select, Space, Spin, Tag, Tooltip, Typography,
} from 'antd'
import {
  ClearOutlined, PauseCircleOutlined, PlayCircleOutlined, ReloadOutlined, ThunderboltOutlined,
} from '@ant-design/icons'

import { deviceApi } from '@/services/deviceApi'
import type {
  DebugSession,
  DebugSessionStatus,
  StartDebugSessionBody,
} from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import { useDebugStream } from '@/hooks/useDebugStream'
import ReactECharts from '@/lib/echarts'

const { Text } = Typography

interface DebugTabProps {
  sn: string
}

const CARD_SHADOW = '0 2px 8px rgba(17,24,39,0.06)'
/** 本地累积采样点上限，超出裁掉最旧的 */
const MAX_POINTS = 400

/** 会话仍「活着」的状态（显示倒计时/停止按钮；interrupted 为终态不提供停止） */
const LIVE_STATUSES = new Set<DebugSessionStatus>(['starting', 'active', 'stopping'])

/* ═══════════ 曲线分组与选线定义 ═══════════ */

type MetricKey = keyof import('@/services/deviceApi').DebugSampleMetrics
type GroupKey = 'mppt' | 'battery' | 'inverter' | 'load'

interface MetricDef {
  key: MetricKey
  /** 0 = 左轴电压(V)，1 = 右轴电流(A) */
  axis: 0 | 1
  color: string
  /** 读数徽标上的单位 */
  unit: 'V' | 'A'
}

/** 界面按测点原名标注：MPPT 组电流注明为 Buck1/Buck2 电流 */
const METRIC_DEFS: Record<MetricKey, MetricDef> = {
  pv1_voltage: { key: 'pv1_voltage', axis: 0, color: '#fbbf24', unit: 'V' },
  buck1_current: { key: 'buck1_current', axis: 1, color: '#fb923c', unit: 'A' },
  pv2_voltage: { key: 'pv2_voltage', axis: 0, color: '#38bdf8', unit: 'V' },
  buck2_current: { key: 'buck2_current', axis: 1, color: '#60a5fa', unit: 'A' },
  battery_voltage: { key: 'battery_voltage', axis: 0, color: '#34d399', unit: 'V' },
  battery_current: { key: 'battery_current', axis: 1, color: '#10b981', unit: 'A' },
  dc_bus_voltage: { key: 'dc_bus_voltage', axis: 0, color: '#a78bfa', unit: 'V' },
  inv_current: { key: 'inv_current', axis: 1, color: '#c084fc', unit: 'A' },
  ac_voltage: { key: 'ac_voltage', axis: 0, color: '#f87171', unit: 'V' },
  ac_current: { key: 'ac_current', axis: 1, color: '#f97316', unit: 'A' },
}

const METRIC_TKEY: Record<MetricKey, string> = {
  pv1_voltage: 'deviceDetail.debug.metric.pv1Voltage',
  buck1_current: 'deviceDetail.debug.metric.buck1Current',
  pv2_voltage: 'deviceDetail.debug.metric.pv2Voltage',
  buck2_current: 'deviceDetail.debug.metric.buck2Current',
  battery_voltage: 'deviceDetail.debug.metric.batteryVoltage',
  battery_current: 'deviceDetail.debug.metric.batteryCurrent',
  dc_bus_voltage: 'deviceDetail.debug.metric.dcBusVoltage',
  inv_current: 'deviceDetail.debug.metric.invCurrent',
  ac_voltage: 'deviceDetail.debug.metric.acVoltage',
  ac_current: 'deviceDetail.debug.metric.acCurrent',
}

const GROUPS: { key: GroupKey; metrics: MetricKey[] }[] = [
  { key: 'mppt', metrics: ['pv1_voltage', 'buck1_current', 'pv2_voltage', 'buck2_current'] },
  { key: 'battery', metrics: ['battery_voltage', 'battery_current'] },
  { key: 'inverter', metrics: ['dc_bus_voltage', 'inv_current'] },
  { key: 'load', metrics: ['ac_voltage', 'ac_current'] },
]

const GROUP_NOTE_TKEY: Record<GroupKey, string> = {
  mppt: 'deviceDetail.debug.note.mppt',
  battery: 'deviceDetail.debug.note.battery',
  inverter: 'deviceDetail.debug.note.inverter',
  load: 'deviceDetail.debug.note.load',
}

/** 默认勾选：电池电压/电流 + 交流电压/电流 */
const DEFAULT_SELECTED: MetricKey[] = ['battery_voltage', 'battery_current', 'ac_voltage', 'ac_current']

const DURATION_OPTIONS = [1800, 3600, 7200, 14400]
const WINDOW_OPTIONS = [15, 30, 60] as const

/** 会话状态 → 徽标颜色 */
const STATUS_TAG_COLOR: Record<DebugSessionStatus | 'none', string> = {
  none: 'default',
  starting: 'processing',
  active: 'success',
  interrupted: 'warning',
  stopping: 'processing',
  stopped: 'default',
  expired: 'default',
  failed: 'error',
}

/* ═══════════ 深色仪表盘样式常量 ═══════════ */

/** 深色示波器面板：微透明描边 + 深蓝底，曲线在此之上更醒目 */
const SCOPE_PANEL_STYLE: React.CSSProperties = {
  borderRadius: 12,
  border: '1px solid rgba(56,189,248,0.28)',
  background: 'linear-gradient(165deg, #101a2e 0%, #0b1220 55%, #101f38 100%)',
  boxShadow: '0 4px 18px rgba(8,15,30,0.45)',
}

const SCOPE_TEXT = '#94a3b8'
const SCOPE_SPLIT = 'rgba(148,163,184,0.16)'
const SCOPE_AXIS = 'rgba(148,163,184,0.35)'

/* ═══════════ 工具函数 ═══════════ */

/** 开启会话幂等键（jsdom/旧浏览器无 crypto.randomUUID 时降级） */
function newRequestId(): string {
  return typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `web-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
}

/** 剩余时间 → mm:ss / h:mm:ss */
function formatRemaining(ms: number): string {
  if (ms <= 0) return '00:00'
  const totalSec = Math.floor(ms / 1000)
  const h = Math.floor(totalSec / 3600)
  const m = Math.floor((totalSec % 3600) / 60)
  const s = totalSec % 60
  const pad = (n: number) => String(n).padStart(2, '0')
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`
}

const getErrMsg = (e: unknown): string => (e instanceof Error && e.message ? `: ${e.message}` : '')

/* ═══════════ 主组件 ═══════════ */

const DebugTab: React.FC<DebugTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const { message } = App.useApp()
  const queryClient = useQueryClient()

  const [durationSeconds, setDurationSeconds] = useState(3600)
  const [windowMinutes, setWindowMinutes] = useState<15 | 30 | 60>(60)
  const [selected, setSelected] = useState<MetricKey[]>(DEFAULT_SELECTED)
  /** 每秒跳动的「当前时间」，驱动倒计时刷新 */
  const [now, setNow] = useState(() => Date.now())

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [])

  /* ── 会话查询（兜底）：发现「是否有进行中的会话」；实时状态由 SSE 推送 ── */
  const { data: sessionEnvelope, isLoading: sessionLoading } = useQuery({
    queryKey: queryKeys.devices.debugSession(sn),
    queryFn: () => deviceApi.getDebugSession(sn).then((r) => r.data?.data ?? null),
    refetchInterval: () => (document.visibilityState === 'visible' ? 10_000 : false),
  })

  const polledSession = sessionEnvelope?.session ?? null
  const status: DebugSessionStatus | 'none' = polledSession?.status ?? 'none'

  /* ── 实时流：仅在会话存活期间订阅 ── */
  const sessionLive = polledSession != null && LIVE_STATUSES.has(polledSession.status)
  const stream = useDebugStream(sn, { windowMinutes, enabled: sessionLive, maxPoints: MAX_POINTS })

  // 流已连接时以流内会话为准（≤10s 新鲜度），未连接时回退到轮询结果
  const session: DebugSession | null = stream.session ?? polledSession
  const deviceOnline = stream.connected ? stream.deviceOnline : (sessionEnvelope?.device_online ?? false)
  const supported = sessionEnvelope?.supported ?? true
  const samples = stream.samples

  /* ── 开启 / 停止会话 ── */
  const startMutation = useMutation({
    mutationFn: (body: StartDebugSessionBody) => deviceApi.startDebugSession(sn, body),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.devices.debugSession(sn) })
      if (res.data?.data?.conflict) {
        message.warning(t('deviceDetail.debug.startConflict'))
      } else {
        message.success(t('deviceDetail.debug.startSuccess'))
      }
    },
    onError: (e) => message.error(`${t('deviceDetail.debug.startFailed')}${getErrMsg(e)}`),
  })

  const stopMutation = useMutation({
    mutationFn: (id: number) => deviceApi.stopDebugSession(sn, id),
    onSuccess: () => {
      message.success(t('deviceDetail.debug.stopSuccess'))
      queryClient.invalidateQueries({ queryKey: queryKeys.devices.debugSession(sn) })
    },
    onError: (e) => message.error(`${t('deviceDetail.debug.stopFailed')}${getErrMsg(e)}`),
  })

  const handleStart = () => {
    startMutation.mutate({
      duration_seconds: durationSeconds,
      request_id: newRequestId(),
      source: 'web',
    })
  }

  const toggleMetric = (key: MetricKey, checked: boolean) => {
    setSelected((prev) =>
      checked ? (prev.includes(key) ? prev : [...prev, key]) : prev.filter((k) => k !== key),
    )
  }

  /* ── 倒计时 / 最新样本 ── */
  const remainingMs = useMemo(() => {
    if (!session?.expires_at) return 0
    const exp = new Date(session.expires_at).getTime()
    return Number.isNaN(exp) ? 0 : exp - now
  }, [session?.expires_at, now])

  const lastSampleTime = samples.length > 0 ? samples[samples.length - 1].time : (session?.last_sample_at ?? null)

  /** 每条选中曲线的最新读数（读数徽标用） */
  const latestReadings = useMemo(() => {
    const last = samples.length > 0 ? samples[samples.length - 1] : null
    return selected.map((key) => {
      const def = METRIC_DEFS[key]
      const raw = last?.metrics?.[key] ?? null
      const value = raw != null && Number.isFinite(raw) ? raw : null
      return { key, def, label: t(METRIC_TKEY[key]), value }
    })
  }, [samples, selected, t])

  /* ── 深色示波器：双纵轴 + 辉光线 + 渐变面积 + 最新点脉冲光斑 ── */
  const chartOption = useMemo(() => {
    if (samples.length === 0) return null
    const times = samples.map((s) => formatInTimezone(s.time, timezone, 'HH:mm:ss'))
    const series: Record<string, unknown>[] = []
    const legendNames: string[] = []

    for (const key of selected) {
      const def = METRIC_DEFS[key]
      const data = samples.map((s) => s.metrics?.[key] ?? null)
      // 无数据的线不渲染 series
      if (!data.some((v) => v != null && Number.isFinite(v))) continue

      legendNames.push(t(METRIC_TKEY[key]))
      series.push({
        name: t(METRIC_TKEY[key]),
        type: 'line',
        yAxisIndex: def.axis,
        data,
        showSymbol: false,
        // null 断线不连
        connectNulls: false,
        smooth: 0.25,
        lineStyle: { width: 2, color: def.color, shadowColor: def.color, shadowBlur: 7 },
        itemStyle: { color: def.color },
        emphasis: { focus: 'series' },
        areaStyle: {
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: `${def.color}30` },
              { offset: 1, color: `${def.color}02` },
            ],
          },
        },
      })

      // 最新点的脉冲光斑：一眼看出「数据正在进来」
      let lastIdx = data.length - 1
      while (lastIdx >= 0 && data[lastIdx] == null) lastIdx -= 1
      if (lastIdx >= 0) {
        series.push({
          name: `${t(METRIC_TKEY[key])}·live`,
          type: 'effectScatter',
          yAxisIndex: def.axis,
          data: [[lastIdx, data[lastIdx]]],
          symbolSize: 6,
          rippleEffect: { scale: 3.2, brushType: 'stroke' },
          itemStyle: { color: def.color, shadowColor: def.color, shadowBlur: 10 },
          tooltip: { show: false },
          silent: true,
          z: 6,
        })
      }
    }
    if (series.length === 0) return null
    return {
      backgroundColor: 'transparent',
      tooltip: {
        trigger: 'axis' as const,
        backgroundColor: 'rgba(13,20,36,0.92)',
        borderColor: 'rgba(56,189,248,0.35)',
        textStyle: { color: '#e2e8f0', fontSize: 12 },
        axisPointer: { type: 'cross' as const, lineStyle: { color: 'rgba(148,163,184,0.45)' } },
      },
      legend: { data: legendNames, top: 0, textStyle: { color: SCOPE_TEXT, fontSize: 11 }, itemGap: 12 },
      grid: { left: '3%', right: '4%', bottom: '14%', top: 36, containLabel: true },
      xAxis: {
        type: 'category' as const,
        data: times,
        axisLabel: { fontSize: 11, color: SCOPE_TEXT },
        axisLine: { lineStyle: { color: SCOPE_AXIS } },
      },
      yAxis: [
        {
          type: 'value' as const, name: 'V', scale: true,
          nameTextStyle: { color: SCOPE_TEXT },
          axisLabel: { fontSize: 11, color: SCOPE_TEXT },
          splitLine: { lineStyle: { color: SCOPE_SPLIT } },
        },
        {
          type: 'value' as const, name: 'A', scale: true,
          nameTextStyle: { color: SCOPE_TEXT },
          axisLabel: { fontSize: 11, color: SCOPE_TEXT },
          splitLine: { show: false },
        },
      ],
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        { type: 'slider', start: 0, end: 100, height: 16, bottom: 6, borderColor: SCOPE_AXIS },
      ],
      series,
    }
  }, [samples, selected, timezone, t])

  // 占用中（含 stopping）不允许再点开始：避免与后端 409 conflict 空转
  const hasLiveSession = session != null && LIVE_STATUSES.has(session.status)

  /* ── 实时连接状态徽标 ── */
  const liveBadge = sessionLive && (
    <Tooltip title={t('deviceDetail.debug.pushHint')}>
      <Tag
        icon={<ThunderboltOutlined />}
        color={stream.connected ? 'success' : 'processing'}
        style={{ marginInlineEnd: 0, borderRadius: 999 }}
      >
        {stream.connected ? t('deviceDetail.debug.live') : t('deviceDetail.debug.reconnecting')}
      </Tag>
    </Tooltip>
  )

  return (
    <Spin spinning={sessionLoading && !session}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        {/* ── 控制区 ── */}
        <Card size="small" style={{ borderRadius: 12, boxShadow: CARD_SHADOW }}>
          <Space size={16} wrap align="center">
            <Text code copyable={false}>{sn}</Text>
            <Tag color={deviceOnline ? 'green' : 'default'} style={{ marginInlineEnd: 0 }}>
              {deviceOnline ? t('deviceDetail.debug.deviceOnline') : t('deviceDetail.debug.deviceOffline')}
            </Tag>
            <Tag color={STATUS_TAG_COLOR[status]} style={{ marginInlineEnd: 0 }}>
              {t(`deviceDetail.debug.status.${status}`)}
            </Tag>
            {liveBadge}
            {sessionLive && (
              <Text type="secondary" style={{ fontSize: 13 }}>
                {t('deviceDetail.debug.remaining')}:{' '}
                <Text strong style={{ fontFamily: 'monospace', fontSize: 15 }}>
                  {formatRemaining(remainingMs)}
                </Text>
                {session?.expires_at && (
                  <>（{formatInTimezone(session.expires_at, timezone, 'HH:mm')}）</>
                )}
              </Text>
            )}
            <Text type="secondary" style={{ fontSize: 13 }}>
              {t('deviceDetail.debug.lastSample')}:{' '}
              {lastSampleTime ? formatInTimezone(lastSampleTime, timezone, 'HH:mm:ss') : t('deviceDetail.debug.noSample')}
            </Text>
          </Space>

          <Space size={12} wrap style={{ marginTop: 12 }}>
            <Space size={8}>
              <Text type="secondary" style={{ fontSize: 13 }}>{t('deviceDetail.debug.duration')}</Text>
              <Select
                value={durationSeconds}
                onChange={setDurationSeconds}
                disabled={startMutation.isPending}
                style={{ width: 120 }}
                options={DURATION_OPTIONS.map((v) => ({
                  value: v,
                  label: t(`deviceDetail.debug.duration.${v}`),
                }))}
              />
            </Space>
            <Button
              type="primary"
              icon={<PlayCircleOutlined />}
              loading={startMutation.isPending}
              disabled={hasLiveSession || !deviceOnline}
              onClick={handleStart}
            >
              {t('deviceDetail.debug.start')}
            </Button>
            {session && sessionLive && (
              <Button
                danger
                icon={<PauseCircleOutlined />}
                loading={stopMutation.isPending}
                disabled={session.status === 'stopping'}
                onClick={() => session && stopMutation.mutate(session.id)}
              >
                {t('deviceDetail.debug.stop')}
              </Button>
            )}
            {session?.status === 'failed' && session.failure_reason && (
              <Text type="danger" style={{ fontSize: 12 }}>{session.failure_reason}</Text>
            )}
          </Space>

          {!supported && (
            <Alert type="warning" showIcon style={{ marginTop: 12, borderRadius: 10 }}
              message={t('deviceDetail.debug.unsupported')} />
          )}
          {sessionLive && stream.error && (
            <Alert
              type="error"
              showIcon
              style={{ marginTop: 12, borderRadius: 10 }}
              message={t('deviceDetail.debug.streamError')}
              description={
                <Space direction="vertical" size={4}>
                  <Text type="secondary" style={{ fontSize: 12 }}>{stream.error}</Text>
                  <Button size="small" icon={<ReloadOutlined />} onClick={stream.reconnect}>
                    {t('deviceDetail.debug.retry')}
                  </Button>
                </Space>
              }
            />
          )}
          <Alert type="info" showIcon style={{ marginTop: 12, borderRadius: 10 }}
            message={t('deviceDetail.debug.note.session')} />
        </Card>

        {/* ── 选线区 ── */}
        <Card size="small" style={{ borderRadius: 12, boxShadow: CARD_SHADOW }}>
          <Collapse
            size="small"
            // 调试页默认展开全部分组，方便直接看到所有可勾选曲线
            defaultActiveKey={GROUPS.map((g) => g.key)}
            items={GROUPS.map((g) => ({
              key: g.key,
              label: (
                <Space size={10} wrap>
                  <span style={{ fontWeight: 600 }}>{t(`deviceDetail.debug.group.${g.key}`)}</span>
                  <Text type="secondary" style={{ fontSize: 12, fontWeight: 400 }}>
                    {t(GROUP_NOTE_TKEY[g.key])}
                  </Text>
                </Space>
              ),
              children: (
                <Space size={[4, 8]} wrap>
                  {g.metrics.map((mk) => {
                    const def = METRIC_DEFS[mk]
                    return (
                      <Checkbox
                        key={mk}
                        checked={selected.includes(mk)}
                        onChange={(e) => toggleMetric(mk, e.target.checked)}
                      >
                        <span style={{ color: def.color, fontWeight: 600, marginInlineEnd: 4 }}>■</span>
                        {t(METRIC_TKEY[mk])}
                      </Checkbox>
                    )
                  })}
                </Space>
              ),
            }))}
          />
        </Card>

        {/* ── 曲线区：深色示波器面板 ── */}
        <Card
          size="small"
          style={{ ...SCOPE_PANEL_STYLE }}
          styles={{ body: { padding: '12px 16px 8px' } }}
          title={
            <Space size={10} wrap>
              <ThunderboltOutlined style={{ color: '#38bdf8' }} />
              <span style={{ fontWeight: 600, color: '#e2e8f0' }}>{t('deviceDetail.debug.chartTitle')}</span>
              {liveBadge}
            </Space>
          }
          extra={
            <Space size={12} wrap>
              <Space size={8}>
                <Text type="secondary" style={{ fontSize: 13, color: SCOPE_TEXT }}>{t('deviceDetail.debug.window')}</Text>
                <Select
                  value={windowMinutes}
                  onChange={(value) => setWindowMinutes(value as 15 | 30 | 60)}
                  style={{ width: 100 }}
                  options={WINDOW_OPTIONS.map((v) => ({
                    value: v,
                    label: t(`deviceDetail.debug.window.${v}`),
                  }))}
                />
              </Space>
              <Button
                size="small"
                icon={<ClearOutlined />}
                disabled={selected.length === 0}
                onClick={() => setSelected([])}
              >
                {t('deviceDetail.debug.clearAll')}
              </Button>
            </Space>
          }
        >
          {/* 最新读数徽标：数字随推送实时跳动 */}
          {latestReadings.length > 0 && (
            <Space size={8} wrap style={{ marginBottom: 10 }}>
              {latestReadings.map(({ key, def, label, value }) => (
                <div
                  key={key}
                  style={{
                    display: 'flex', alignItems: 'baseline', gap: 6, padding: '4px 10px', borderRadius: 8,
                    background: 'rgba(148,163,184,0.08)', border: `1px solid ${def.color}44`,
                  }}
                >
                  <span style={{ width: 8, height: 8, borderRadius: 999, background: def.color, alignSelf: 'center' }} />
                  <span style={{ fontSize: 12, color: SCOPE_TEXT }}>{label}</span>
                  <span style={{ fontFamily: 'monospace', fontSize: 14, fontWeight: 600, color: def.color }}>
                    {value != null ? value.toFixed(2) : '--'}
                  </span>
                  <span style={{ fontSize: 11, color: SCOPE_TEXT }}>{def.unit}</span>
                </div>
              ))}
            </Space>
          )}
          {chartOption ? (
            <ReactECharts option={chartOption} notMerge lazyUpdate style={{ height: 380, width: '100%' }} />
          ) : (
            <div style={{ padding: '56px 0', textAlign: 'center', color: SCOPE_TEXT, fontSize: 13 }}>
              {t('deviceDetail.debug.noPoints')}
            </div>
          )}
        </Card>
      </div>
    </Spin>
  )
}

export default DebugTab
