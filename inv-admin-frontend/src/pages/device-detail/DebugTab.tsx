/**
 * 设备调试 Tab（DebugTab）
 *
 * 数据源：
 *  - GET  /devices/by-sn/:sn/debug-session          查询当前调试会话（10s 轮询，仅页面可见时）
 *  - POST /devices/by-sn/:sn/debug-session          开启会话（duration_seconds + request_id 幂等键）
 *  - DELETE /devices/by-sn/:sn/debug-session/:id    停止会话（幂等）
 *  - GET  /devices/by-sn/:sn/debug-samples          采样拉取（10s 轮询，after=游标增量）
 *
 * 语义约定：
 *  - 关闭页面不调用停止 API：会话由服务端 TTL（expires_at）自动过期；
 *  - 曲线四组：MPPT/PV（PV1/PV2 电压 + Buck1/Buck2 电流）、电池、逆变（母线电压+逆变电流）、
 *    负载（交流输出测点）；电压画左轴(V)、电流画右轴(A)，null 断线不连；
 *  - 本地累积采样点上限 400（超出裁掉最旧）；切换时间窗 / 重新进入页面全量拉取。
 */
import { useEffect, useMemo, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Alert, App, Button, Card, Checkbox, Collapse, Empty, Select, Space, Spin, Tag, Typography,
} from 'antd'
import { ClearOutlined, PauseCircleOutlined, PlayCircleOutlined } from '@ant-design/icons'

import { deviceApi } from '@/services/deviceApi'
import type {
  DebugSample,
  DebugSampleMetrics,
  DebugSession,
  DebugSessionStatus,
  StartDebugSessionBody,
} from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import ReactECharts from '@/lib/echarts'

const { Text } = Typography

interface DebugTabProps {
  sn: string
}

const CARD_SHADOW = '0 2px 8px rgba(17,24,39,0.06)'
/** 本地累积采样点上限，超出裁掉最旧的 */
const MAX_POINTS = 400
const SAMPLE_LIMIT = 200

/** 会话仍「活着」的状态（显示倒计时/停止按钮；interrupted 为终态不提供停止） */
const LIVE_STATUSES = new Set<DebugSessionStatus>(['starting', 'active', 'stopping'])
/** 仍在产生采样、需要继续拉取的状态 */
const SAMPLING_STATUSES = new Set<DebugSessionStatus>(['starting', 'active'])

/* ═══════════ 曲线分组与选线定义 ═══════════ */

type MetricKey = keyof DebugSampleMetrics
type GroupKey = 'mppt' | 'battery' | 'inverter' | 'load'

interface MetricDef {
  key: MetricKey
  /** 0 = 左轴电压(V)，1 = 右轴电流(A) */
  axis: 0 | 1
  color: string
}

/** 界面按测点原名标注：MPPT 组电流注明为 Buck1/Buck2 电流 */
const METRIC_DEFS: Record<MetricKey, MetricDef> = {
  pv1_voltage: { key: 'pv1_voltage', axis: 0, color: '#f59e0b' },
  buck1_current: { key: 'buck1_current', axis: 1, color: '#fb923c' },
  pv2_voltage: { key: 'pv2_voltage', axis: 0, color: '#3b82f6' },
  buck2_current: { key: 'buck2_current', axis: 1, color: '#60a5fa' },
  battery_voltage: { key: 'battery_voltage', axis: 0, color: '#22c55e' },
  battery_current: { key: 'battery_current', axis: 1, color: '#16a34a' },
  dc_bus_voltage: { key: 'dc_bus_voltage', axis: 0, color: '#8b5cf6' },
  inv_current: { key: 'inv_current', axis: 1, color: '#a78bfa' },
  ac_voltage: { key: 'ac_voltage', axis: 0, color: '#ef4444' },
  ac_current: { key: 'ac_current', axis: 1, color: '#f97316' },
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

/* ═══════════ 工具函数 ═══════════ */

/** 开启会话幂等键（jsdom/旧浏览器无 crypto.randomUUID 时降级） */
function newRequestId(): string {
  return typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `web-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
}

/** 合并增量采样：按 time 去重、升序，超出上限裁掉最旧的 */
function mergeSamples(prev: DebugSample[], incoming: DebugSample[]): DebugSample[] {
  if (incoming.length === 0) return prev
  const byTime = new Map<string, DebugSample>()
  for (const s of prev) byTime.set(s.time, s)
  for (const s of incoming) byTime.set(s.time, s)
  const merged = [...byTime.values()].sort((a, b) => a.time.localeCompare(b.time))
  return merged.length > MAX_POINTS ? merged.slice(merged.length - MAX_POINTS) : merged
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
  const [samples, setSamples] = useState<DebugSample[]>([])
  /** 每秒跳动的「当前时间」，驱动倒计时刷新 */
  const [now, setNow] = useState(() => Date.now())
  /** 增量游标（不透明字符串），放 ref 避免进 queryKey 触发多余 refetch */
  const cursorRef = useRef('')

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [])

  /* ── 会话查询：10s 轮询，仅页面可见时 ── */
  const { data: sessionEnvelope, isLoading: sessionLoading } = useQuery({
    queryKey: queryKeys.devices.debugSession(sn),
    queryFn: () => deviceApi.getDebugSession(sn).then((r) => r.data?.data ?? null),
    refetchInterval: () => (document.visibilityState === 'visible' ? 10_000 : false),
  })

  const session: DebugSession | null = sessionEnvelope?.session ?? null
  const deviceOnline = sessionEnvelope?.device_online ?? false
  const supported = sessionEnvelope?.supported ?? true
  const status: DebugSessionStatus | 'none' = session?.status ?? 'none'
  const sessionLive = session != null && LIVE_STATUSES.has(session.status)
  const sessionId = session?.id ?? null
  const sampling = session != null && SAMPLING_STATUSES.has(session.status)

  /* ── 采样查询：10s 增量拉取（after=游标），仅会话活跃且页面可见时 ── */
  const { data: samplesPage } = useQuery({
    queryKey: [...queryKeys.devices.debugSamples(sn, sessionId ?? undefined), windowMinutes],
    queryFn: () =>
      deviceApi
        .getDebugSamples(sn, {
          session_id: sessionId ?? undefined,
          window_minutes: windowMinutes,
          after: cursorRef.current,
          limit: SAMPLE_LIMIT,
        })
        .then((r) => r.data?.data ?? null),
    enabled: Boolean(sessionId) && sampling,
    refetchInterval: () => (document.visibilityState === 'visible' && sampling ? 10_000 : false),
  })

  // 增量合并：更新游标 + 追加去重后的采样点（上限 400）
  useEffect(() => {
    if (!samplesPage) return
    cursorRef.current = samplesPage.next_cursor ?? ''
    if (samplesPage.items.length > 0) setSamples((prev) => mergeSamples(prev, samplesPage.items))
  }, [samplesPage])

  /** 全量重置（切时间窗/开启新会话）：清空游标与本地累积点 */
  const resetSamples = () => {
    cursorRef.current = ''
    setSamples([])
  }

  /* ── 开启 / 停止会话 ── */
  const startMutation = useMutation({
    mutationFn: (body: StartDebugSessionBody) => deviceApi.startDebugSession(sn, body),
    onSuccess: (res) => {
      resetSamples()
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

  const handleWindowChange = (value: number) => {
    // 游标是 ref，必须在新 query（新 queryKey）发出前置空，保证切窗后全量拉取
    resetSamples()
    setWindowMinutes(value as 15 | 30 | 60)
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

  /* ── ECharts 双纵轴折线图（左 V 右 A）── */
  const chartOption = useMemo(() => {
    if (samples.length === 0) return null
    const times = samples.map((s) => formatInTimezone(s.time, timezone, 'HH:mm:ss'))
    const series: Record<string, unknown>[] = []
    for (const key of selected) {
      const def = METRIC_DEFS[key]
      const data = samples.map((s) => s.metrics?.[key] ?? null)
      // 无数据的线不渲染 series
      if (!data.some((v) => v != null && Number.isFinite(v))) continue
      series.push({
        name: t(METRIC_TKEY[key]),
        type: 'line',
        yAxisIndex: def.axis,
        data,
        showSymbol: false,
        // null 断线不连
        connectNulls: false,
        lineStyle: { width: 2, color: def.color },
        itemStyle: { color: def.color },
      })
    }
    if (series.length === 0) return null
    return {
      tooltip: { trigger: 'axis' as const },
      legend: { data: series.map((s) => s.name), top: 0, itemGap: 12 },
      grid: { left: '3%', right: '4%', bottom: '8%', top: 36, containLabel: true },
      xAxis: { type: 'category' as const, data: times, axisLabel: { fontSize: 11 } },
      yAxis: [
        { type: 'value' as const, name: 'V', scale: true, axisLabel: { fontSize: 11 } },
        { type: 'value' as const, name: 'A', scale: true, splitLine: { show: false }, axisLabel: { fontSize: 11 } },
      ],
      series,
    }
  }, [samples, selected, timezone, t])

  // 占用中（含 stopping）不允许再点开始：避免与后端 409 conflict 空转
  const hasLiveSession = session != null && LIVE_STATUSES.has(session.status)

  return (
    <Spin spinning={sessionLoading}>
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
          <Alert type="info" showIcon style={{ marginTop: 12, borderRadius: 10 }}
            message={t('deviceDetail.debug.note.session')} />
        </Card>

        {/* ── 曲线区：选线 + 双纵轴折线图 ── */}
        <Card
          size="small"
          style={{ borderRadius: 12, boxShadow: CARD_SHADOW }}
          title={<span style={{ fontWeight: 600 }}>📈 {t('deviceDetail.debug.chartTitle')}</span>}
          extra={
            <Space size={12} wrap>
            <Space size={8}>
              <Text type="secondary" style={{ fontSize: 13 }}>{t('deviceDetail.debug.window')}</Text>
              <Select
                value={windowMinutes}
                onChange={handleWindowChange}
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
          <Collapse
            size="small"
            style={{ marginBottom: 12 }}
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
          {chartOption ? (
            <ReactECharts option={chartOption} notMerge style={{ height: 360 }} />
          ) : (
            <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t('deviceDetail.debug.noPoints')} />
          )}
        </Card>
      </div>
    </Spin>
  )
}

export default DebugTab
