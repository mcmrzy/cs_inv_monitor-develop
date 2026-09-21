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
 *  - 曲线分四组（MPPT/PV、电池、逆变、负载），每组含实测测点与派生功率
 *    （P = U × I，见 debugMetrics.ts）；电压走左轴、电流走右轴、计算功率走第三条右轴，
 *    「正负轴」开关控制三条纵轴是否以 0 为中心对称展开；
 *  - 超出物理量程的采样点判为固件脏值：曲线剔除（单点会把纵轴撑爆），
 *    表格原样保留并标红，卡片头部明示剔除数量；
 *  - 明细表与曲线同源同窗口，另带窗口内最小/最大汇总行与 CSV 导出；
 *  - 本地累积采样点上限 400（超出裁掉最旧）；切换时间窗会重连并由服务端重发快照。
 */
import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Alert, App, Button, Card, Select, Space, Switch, Tag, Tooltip, Typography,
} from 'antd'
import {
  DownloadOutlined, PauseCircleOutlined, PlayCircleOutlined,
  ReloadOutlined, SlidersOutlined, TableOutlined, ThunderboltOutlined, WarningOutlined,
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
import {
  ALL_SERIES,
  GROUPS,
  SERIES_DEFS,
  formatSeriesValue,
  groupSeries,
  isDerived,
  DEFAULT_SELECTED,
  type SeriesKey,
} from './debug/debugMetrics'
import { buildCsv, computeSeriesStat, qualityFlagsOf } from './debug/debugAnalysis'
import { buildDebugChartOption } from './debug/debugChartOption'
import { DEBUG_ACCENT, DEBUG_CHIP_BG, DEBUG_PANEL_STYLE, DEBUG_TEXT, DEBUG_TITLE } from './debug/debugTheme'
import DebugChart from './debug/DebugChart'
import SeriesChip from './debug/SeriesChip'
import DebugTable from './debug/DebugTable'
import { useDebugLabels } from './debug/useDebugLabels'

const { Text } = Typography

interface DebugTabProps {
  sn: string
}

const CARD_SHADOW = '0 2px 8px rgba(17,24,39,0.06)'
/** 本地累积采样点上限，超出裁掉最旧的 */
const MAX_POINTS = 400

/** 会话仍「活着」的状态（显示倒计时/停止按钮；interrupted 为终态不提供停止） */
const LIVE_STATUSES = new Set<DebugSessionStatus>(['starting', 'active', 'stopping'])

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

/** CSV 下载（文件名带 SN 与本地时区时间戳，便于留档） */
function downloadCsv(filename: string, content: string) {
  const blob = new Blob([content], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}

/* ═══════════ 主组件 ═══════════ */

const DebugTab: React.FC<DebugTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const { message } = App.useApp()
  const queryClient = useQueryClient()
  const { labels, shortLabels } = useDebugLabels()

  const [durationSeconds, setDurationSeconds] = useState(3600)
  const [windowMinutes, setWindowMinutes] = useState<15 | 30 | 60>(60)
  const [selected, setSelected] = useState<SeriesKey[]>([...DEFAULT_SELECTED])
  /** 正负轴：三条纵轴以 0 为中心对称展开 */
  const [symmetricAxis, setSymmetricAxis] = useState(true)
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

  const toggleSeries = (key: SeriesKey, checked: boolean) => {
    setSelected((prev) =>
      checked ? (prev.includes(key) ? prev : [...prev, key]) : prev.filter((k) => k !== key),
    )
  }

  /** 整组选中/清空（分组里既有实测也有派生功率） */
  const toggleGroup = (keys: SeriesKey[], checked: boolean) => {
    setSelected((prev) => {
      if (!checked) return prev.filter((k) => !keys.includes(k))
      const merged = [...prev]
      for (const key of keys) if (!merged.includes(key)) merged.push(key)
      return merged
    })
  }

  /* ── 倒计时 / 最新样本 ── */
  const remainingMs = useMemo(() => {
    if (!session?.expires_at) return 0
    const exp = new Date(session.expires_at).getTime()
    return Number.isNaN(exp) ? 0 : exp - now
  }, [session?.expires_at, now])

  const lastSampleTime = samples.length > 0 ? samples[samples.length - 1].time : (session?.last_sample_at ?? null)

  /** 每条选中曲线的窗口统计（读数徽标 tooltip + 汇总参照） */
  const stats = useMemo(
    () => new Map(selected.map((key) => [key, computeSeriesStat(samples, key)])),
    [samples, selected],
  )

  /** 曲线 option（越界点在这里被剔除，dropped 计数用于卡片头部明示） */
  const chart = useMemo(
    () => buildDebugChartOption({
      samples,
      selected,
      labels,
      timezone,
      symmetric: symmetricAxis,
      axisNames: { voltage: 'V', current: 'A', power: 'W' },
    }),
    [samples, selected, labels, timezone, symmetricAxis],
  )

  const handleExport = () => {
    try {
      const csv = buildCsv(samples, selected, {
        timezone,
        headers: {
          time: t('deviceDetail.debug.table.time'),
          quality: t('deviceDetail.debug.table.quality'),
          series: labels,
        },
        qualityText: (flags) =>
          qualityFlagsOf(flags).map((f) => t(f.labelKey)).join('|') || t('deviceDetail.debug.table.qualityOk'),
      })
      downloadCsv(
        `debug-${sn}-${formatInTimezone(new Date().toISOString(), timezone, 'YYYYMMDD-HHmmss')}.csv`,
        csv,
      )
    } catch (e) {
      message.error(`${t('deviceDetail.debug.table.exportFailed')}${getErrMsg(e)}`)
    }
  }

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

  /** 越界剔除提示：明确告诉用户「曲线少画的点去哪里了」 */
  const droppedBadge = chart.dropped > 0 && (
    <Tooltip title={t('deviceDetail.debug.excludedHint')}>
      <Tag icon={<WarningOutlined />} color="warning" style={{ marginInlineEnd: 0, borderRadius: 999 }}>
        {t('deviceDetail.debug.excluded', { n: chart.dropped })}
      </Tag>
    </Tooltip>
  )

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* ── 控制区 ── */}
      <Card size="small" style={{ borderRadius: 12, boxShadow: CARD_SHADOW }} loading={sessionLoading && !session}>
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

      {/* ── 选线区：一行一组 + 彩色药丸开关 ── */}
      <Card
        size="small"
        style={{ borderRadius: 12, boxShadow: CARD_SHADOW }}
        styles={{ body: { padding: '12px 16px' } }}
        title={
          <Space size={10} wrap>
            <SlidersOutlined style={{ color: DEBUG_ACCENT }} />
            <span style={{ fontWeight: 600, color: DEBUG_TITLE }}>{t('deviceDetail.debug.selectTitle')}</span>
            <Text type="secondary" style={{ fontSize: 12, fontWeight: 400 }}>
              {t('deviceDetail.debug.selectHint')}
            </Text>
          </Space>
        }
        extra={
          <Space size={12} wrap>
            <Text type="secondary" style={{ fontSize: 12 }}>
              {t('deviceDetail.debug.selectedCount', { n: selected.length, total: ALL_SERIES.length })}
            </Text>
            <Space size={2}>
              <Button
                type="link"
                size="small"
                disabled={selected.length === ALL_SERIES.length}
                onClick={() => setSelected([...ALL_SERIES])}
              >
                {t('deviceDetail.debug.groupSelectAll')}
              </Button>
              <Button
                type="link"
                size="small"
                disabled={selected.length === 0}
                onClick={() => setSelected([])}
              >
                {t('deviceDetail.debug.clearAll')}
              </Button>
            </Space>
          </Space>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column' }}>
          {GROUPS.map((g, idx) => {
            const all = groupSeries(g)
            const allChecked = all.every((k) => selected.includes(k))
            const noneChecked = !all.some((k) => selected.includes(k))
            return (
              <div
                key={g.key}
                style={{
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 8,
                  padding: '10px 0',
                  borderTop: idx === 0 ? undefined : '1px solid #f0f0f0',
                }}
              >
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, flexWrap: 'wrap' }}>
                  <span style={{ fontWeight: 600, color: DEBUG_TITLE, fontSize: 13 }}>
                    {t(`deviceDetail.debug.group.${g.key}`)}
                  </span>
                  <span style={{ color: DEBUG_TEXT, fontSize: 12 }}>
                    {t(`deviceDetail.debug.note.${g.key}`)}
                  </span>
                  <span style={{ marginInlineStart: 'auto' }}>
                    <Button type="link" size="small" disabled={allChecked} onClick={() => toggleGroup(all, true)}>
                      {t('deviceDetail.debug.groupSelectAll')}
                    </Button>
                    <Button type="link" size="small" disabled={noneChecked} onClick={() => toggleGroup(all, false)}>
                      {t('deviceDetail.debug.groupClear')}
                    </Button>
                  </span>
                </div>
                <Space size={[8, 8]} wrap>
                  {all.map((key) => (
                    <SeriesChip
                      key={key}
                      label={shortLabels[key]}
                      color={SERIES_DEFS[key].color}
                      active={selected.includes(key)}
                      derived={isDerived(key)}
                      onToggle={() => toggleSeries(key, !selected.includes(key))}
                    />
                  ))}
                </Space>
              </div>
            )
          })}
        </div>
      </Card>

      {/* ── 曲线区：白底彩色示波器 ── */}
      <Card
        size="small"
        style={{ ...DEBUG_PANEL_STYLE }}
        styles={{ body: { padding: '12px 16px 8px' } }}
        title={
          <Space size={10} wrap>
            <ThunderboltOutlined style={{ color: DEBUG_ACCENT }} />
            <span style={{ fontWeight: 600, color: DEBUG_TITLE }}>{t('deviceDetail.debug.chartTitle')}</span>
            {liveBadge}
            {droppedBadge}
          </Space>
        }
        extra={
          <Space size={12} wrap>
            <Tooltip title={t('deviceDetail.debug.axisToggleHint')}>
              <Space size={6}>
                <Text style={{ fontSize: 13, color: DEBUG_TEXT }}>{t('deviceDetail.debug.axisToggle')}</Text>
                <Switch size="small" checked={symmetricAxis} onChange={setSymmetricAxis} />
              </Space>
            </Tooltip>
            <Space size={8}>
              <Text style={{ fontSize: 13, color: DEBUG_TEXT }}>{t('deviceDetail.debug.window')}</Text>
              <Select
                value={windowMinutes}
                size="small"
                onChange={(value) => setWindowMinutes(value as 15 | 30 | 60)}
                style={{ width: 92 }}
                options={WINDOW_OPTIONS.map((v) => ({
                  value: v,
                  label: t(`deviceDetail.debug.window.${v}`),
                }))}
              />
            </Space>
          </Space>
        }
      >
        {/* 最新读数徽标：数字随推送实时跳动；悬浮看窗口统计 */}
        {selected.length > 0 && (
          <Space size={8} wrap style={{ marginBottom: 10 }}>
            {selected.map((key) => {
              const def = SERIES_DEFS[key]
              const stat = stats.get(key)
              const value = stat?.last ?? null
              const derived = isDerived(key)
              return (
                <Tooltip
                  key={key}
                  title={t('deviceDetail.debug.statsHint', {
                    min: stat?.min == null ? '--' : formatSeriesValue(key, stat.min),
                    max: stat?.max == null ? '--' : formatSeriesValue(key, stat.max),
                    avg: stat?.avg == null ? '--' : formatSeriesValue(key, stat.avg),
                    count: stat?.valid ?? 0,
                  })}
                >
                  <div
                    style={{
                      display: 'flex', alignItems: 'baseline', gap: 5, padding: '3px 8px', borderRadius: 8,
                      background: DEBUG_CHIP_BG,
                      border: `1px ${derived ? 'dashed' : 'solid'} ${def.color}55`,
                    }}
                  >
                    <span
                      style={{
                        width: 8, height: 8, borderRadius: derived ? 2 : 999,
                        background: def.color, alignSelf: 'center',
                      }}
                    />
                    <span style={{ fontSize: 12, color: DEBUG_TEXT }}>{labels[key]}</span>
                    <span style={{ fontFamily: 'monospace', fontSize: 13, fontWeight: 600, color: def.color }}>
                      {formatSeriesValue(key, value)}
                    </span>
                    <span style={{ fontSize: 11, color: DEBUG_TEXT }}>{def.unit}</span>
                  </div>
                </Tooltip>
              )
            })}
          </Space>
        )}
        <DebugChart option={chart.option} emptyText={t('deviceDetail.debug.noPoints')} />
        <div style={{ marginTop: 6, fontSize: 11, color: DEBUG_TEXT, lineHeight: 1.6 }}>
          {t('deviceDetail.debug.footNote')}
        </div>
      </Card>

      {/* ── 明细表：曲线之外可读、可导出的原始数据 ── */}
      <Card
        size="small"
        style={{ ...DEBUG_PANEL_STYLE }}
        styles={{ body: { padding: '8px 12px 4px' } }}
        title={
          <Space size={10} wrap>
            <TableOutlined style={{ color: DEBUG_ACCENT }} />
            <span style={{ fontWeight: 600, color: DEBUG_TITLE }}>{t('deviceDetail.debug.table.title')}</span>
            <Text style={{ fontSize: 12, color: DEBUG_TEXT }}>
              {t('deviceDetail.debug.table.subtitle')}
            </Text>
          </Space>
        }
        extra={
          <Button
            size="small"
            icon={<DownloadOutlined />}
            disabled={samples.length === 0 || selected.length === 0}
            onClick={handleExport}
          >
            {t('deviceDetail.debug.table.export')}
          </Button>
        }
      >
        <DebugTable samples={samples} keys={selected} labels={labels} shortLabels={shortLabels} timezone={timezone} />
      </Card>
    </div>
  )
}

export default DebugTab
