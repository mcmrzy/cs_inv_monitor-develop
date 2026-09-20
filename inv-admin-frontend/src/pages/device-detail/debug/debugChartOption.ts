/**
 * 调试示波器的 ECharts option 构造（纯函数，便于单测断言）。
 *
 * 关键取舍：
 *  - 纵轴按「电压 / 电流 / 功率」三分组，各占一条轴；正负轴开启时三条轴都以 0
 *    为中心对称展开，零线在网格中线重合（读充电/放电、正/负功率一眼分明）。
 *  - 越界（脏值）点已由 buildSeriesValues 剔除，不会撑爆纵轴；剔除数量在卡片
 *    头部明示，原值在表格里标红保留。
 *  - 派生功率用虚线，与实测曲线在视觉上分开；白底上用高饱和实色，保证可读。
 */
import { formatInTimezone } from '@/utils/timezone'
import type { DebugSample } from '@/services/deviceApi'
import { SERIES_DEFS, type AxisKey, type SeriesKey } from './debugMetrics'
import { buildAxisRange, buildSeriesValues, niceCeil } from './debugAnalysis'
import { DEBUG_AXIS, DEBUG_SPLIT, DEBUG_TEXT } from './debugTheme'

export interface ChartBuildResult {
  /** 无可绘制曲线时为 null（UI 退化为空态） */
  option: Record<string, unknown> | null
  /** 被剔除的越界点数（脏值证据，UI 明示） */
  dropped: number
}

export interface BuildChartParams {
  samples: readonly DebugSample[]
  selected: readonly SeriesKey[]
  /** 已翻译的曲线名（含「（计算）」后缀），按 key 索引 */
  labels: Record<string, string>
  timezone: string
  /** 正负轴：以 0 为中心对称 */
  symmetric: boolean
  /** 纵轴名（已翻译），如 { voltage: 'V', current: 'A', power: 'W' } */
  axisNames: Record<AxisKey, string>
}

/** 零线：三条纵轴的 0 落在同一水平线上，比普通分隔线亮一档 */
const ZERO_LINE = 'rgba(17,24,39,0.38)'

const AXIS_ORDER: readonly AxisKey[] = ['voltage', 'current', 'power']

/** 同一纵轴上曲线过多时关掉渐变面积/实时光斑，避免糊成一片 */
const AREA_MAX_SERIES_PER_AXIS = 2
const LIVE_DOT_MAX_SERIES = 6

export function buildDebugChartOption(params: BuildChartParams): ChartBuildResult {
  const { samples, selected, labels, timezone, symmetric, axisNames } = params
  if (samples.length === 0) return { option: null, dropped: 0 }

  const times = samples.map((s) => formatInTimezone(s.time, timezone, 'HH:mm:ss'))
  const nameToKey = new Map<string, SeriesKey>()
  const rendered: { key: SeriesKey; values: (number | null)[]; color: string; axis: AxisKey }[] = []
  let dropped = 0

  for (const key of selected) {
    const def = SERIES_DEFS[key]
    if (!def) continue
    const series = buildSeriesValues(samples, key)
    dropped += series.dropped
    if (series.valid === 0) continue
    nameToKey.set(labels[key] ?? key, key)
    rendered.push({ key, values: series.values, color: def.color, axis: def.axis })
  }
  if (rendered.length === 0) return { option: null, dropped }

  // 只保留有曲线的纵轴，并记录索引（series.yAxisIndex 用）
  const usedAxes = AXIS_ORDER.filter((axis) => rendered.some((r) => r.axis === axis))
  const axisIndex = new Map<AxisKey, number>(usedAxes.map((axis, i) => [axis, i]))

  const yAxis = usedAxes.map((axis) => {
    const values = rendered.filter((r) => r.axis === axis).flatMap((r) => r.values.filter((v): v is number => v != null))
    const range = buildAxisRange(values, symmetric)
    const [min, max] = range ?? [-1, 1]
    const right = axis !== 'voltage'
    const offset = axis === 'power' ? 54 : 0
    return {
      type: 'value' as const,
      name: axisNames[axis],
      nameTextStyle: { color: DEBUG_TEXT, fontSize: 11 },
      position: right ? ('right' as const) : ('left' as const),
      offset,
      min,
      max,
      // 数值全为 0 时对称轴会退化成一条线：留最小可视带
      axisLabel: {
        fontSize: 11,
        color: DEBUG_TEXT,
        formatter: (v: number) => {
          const abs = Math.abs(v)
          if (abs >= 1000) {
            const scaled = niceCeil(abs) / 1000
            return `${v < 0 ? '-' : ''}${Number.isInteger(scaled) ? scaled : scaled.toFixed(1)}k`
          }
          return Number.isInteger(v) ? `${v}` : `${Number(v.toFixed(2))}`
        },
      },
      axisLine: { show: true, lineStyle: { color: DEBUG_AXIS } },
      splitLine: { show: !right, lineStyle: { color: DEBUG_SPLIT } },
    }
  })

  // 每条纵轴上曲线过多时，只给前两条上渐变面积
  const areaCount = new Map<AxisKey, number>()
  const zeroLineAxes = new Set<AxisKey>()
  const series: Record<string, unknown>[] = []

  for (const item of rendered) {
    const def = SERIES_DEFS[item.key]
    const name = labels[item.key] ?? item.key
    const yIdx = axisIndex.get(item.axis) ?? 0
    const showArea = (areaCount.get(item.axis) ?? 0) < AREA_MAX_SERIES_PER_AXIS
    areaCount.set(item.axis, (areaCount.get(item.axis) ?? 0) + 1)
    // 零线：正负轴下三条纵轴的 0 都落在同一水平线上，每条轴标一次
    const withZeroLine = !zeroLineAxes.has(item.axis)
    zeroLineAxes.add(item.axis)

    series.push({
      name,
      type: 'line',
      yAxisIndex: yIdx,
      data: item.values,
      showSymbol: false,
      // null 断线不连（缺采样 / 越界剔除都不连线）
      connectNulls: false,
      smooth: 0.25,
      lineStyle: {
        width: def.derivedFrom ? 1.5 : 2,
        color: def.color,
        type: def.derivedFrom ? 'dashed' : 'solid',
      },
      itemStyle: { color: def.color },
      emphasis: { focus: 'series' },
      areaStyle: showArea
        ? {
            color: {
              type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: `${def.color}2e` },
                { offset: 1, color: `${def.color}00` },
              ],
            },
          }
        : undefined,
      // 零线：正负轴下三条纵轴的 0 都落在同一水平线上，标出来便于读数
      ...(withZeroLine
        ? {
            markLine: {
              silent: true,
              symbol: 'none',
              animation: false,
              lineStyle: { color: ZERO_LINE, width: 1, type: 'solid' },
              label: { show: false },
              data: [{ yAxis: 0 }],
            },
          }
        : {}),
    })
  }

  // 最新点脉冲光斑：一眼看出「数据正在进来」
  if (rendered.length <= LIVE_DOT_MAX_SERIES) {
    for (const item of rendered) {
      let lastIdx = item.values.length - 1
      while (lastIdx >= 0 && item.values[lastIdx] == null) lastIdx -= 1
      if (lastIdx < 0) continue
      series.push({
        name: `${labels[item.key] ?? item.key}·live`,
        type: 'effectScatter',
        yAxisIndex: axisIndex.get(item.axis) ?? 0,
        data: [[lastIdx, item.values[lastIdx]]],
        symbolSize: 6,
        rippleEffect: { scale: 3.2, brushType: 'stroke' },
        itemStyle: { color: item.color, shadowColor: `${item.color}66`, shadowBlur: 6 },
        tooltip: { show: false },
        silent: true,
        z: 6,
      })
    }
  }

  const option: Record<string, unknown> = {
    backgroundColor: 'transparent',
    // 实时追加：首帧有入场动画，后续更新不重播动画（示波器要跟手）
    animation: true,
    animationDuration: 260,
    animationDurationUpdate: 0,
    animationEasingUpdate: 'linear',
    tooltip: {
      trigger: 'axis' as const,
      backgroundColor: 'rgba(255,255,255,0.98)',
      borderColor: 'rgba(17,24,39,0.08)',
      extraCssText: 'box-shadow: 0 6px 20px rgba(17,24,39,0.12); border-radius: 8px;',
      padding: [8, 12],
      textStyle: { color: '#1f2937', fontSize: 12 },
      axisPointer: {
        type: 'cross' as const,
        lineStyle: { color: 'rgba(17,24,39,0.35)' },
        crossStyle: { color: 'rgba(17,24,39,0.35)' },
        label: { backgroundColor: '#1f2937', color: '#ffffff' },
      },
      formatter: (raw: unknown) => {
        const list = (Array.isArray(raw) ? raw : [raw]) as {
          axisValueLabel?: string
          seriesName?: string
          color?: string
          value?: unknown
        }[]
        const rows = list.filter((p) => typeof p.value === 'number')
        if (rows.length === 0) return ''
        const head = `<div style="color:${DEBUG_TEXT};font-size:11px;margin-bottom:4px">${rows[0].axisValueLabel ?? ''}</div>`
        const body = rows
          .map((p) => {
            const key = nameToKey.get(String(p.seriesName))
            const def = key ? SERIES_DEFS[key] : null
            const value = p.value as number
            const text = def ? `${value.toFixed(def.precision)} ${def.unit}` : `${value}`
            return `<div style="display:flex;align-items:center;gap:6px;line-height:18px;white-space:nowrap">`
              + `<span style="width:8px;height:8px;border-radius:50%;background:${p.color};flex:0 0 auto"></span>`
              + `<span style="color:${DEBUG_TEXT}">${p.seriesName}</span>`
              + `<span style="margin-left:auto;padding-left:16px;font-family:monospace;font-weight:600;color:${p.color}">${text}</span>`
              + `</div>`
          })
          .join('')
        return `<div style="min-width:210px">${head}${body}</div>`
      },
    },
    legend: {
      data: rendered.map((r) => labels[r.key] ?? r.key),
      type: 'scroll' as const,
      top: 0,
      itemGap: 12,
      itemWidth: 14,
      textStyle: { color: DEBUG_TEXT, fontSize: 11 },
      inactiveColor: 'rgba(17,24,39,0.25)',
      pageTextStyle: { color: DEBUG_TEXT },
      pageIconColor: DEBUG_TEXT,
      pageIconInactiveColor: 'rgba(17,24,39,0.25)',
    },
    grid: { left: '3%', right: usedAxes.length >= 3 ? '9%' : '4%', bottom: '15%', top: 46, containLabel: true },
    xAxis: {
      type: 'category' as const,
      data: times,
      boundaryGap: false,
      axisLabel: { fontSize: 11, color: DEBUG_TEXT },
      axisLine: { lineStyle: { color: DEBUG_AXIS } },
      axisTick: { show: false },
    },
    yAxis,
    dataZoom: [
      { type: 'inside', start: 0, end: 100 },
      {
        type: 'slider', start: 0, end: 100, height: 14, bottom: 4,
        borderColor: DEBUG_AXIS, fillerColor: 'rgba(22,119,255,0.10)',
        textStyle: { color: DEBUG_TEXT, fontSize: 10 },
        handleStyle: { color: '#1677ff' },
      },
    ],
    series,
  }

  return { option, dropped }
}
