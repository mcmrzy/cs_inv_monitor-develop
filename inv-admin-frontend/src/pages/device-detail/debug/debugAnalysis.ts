/**
 * 调试曲线的分析工具：序列取值、窗口统计、纵轴范围、质量位判读、CSV 导出。
 * 纯函数，无 React 依赖，便于单测覆盖边界（脏值、全零、断线、空窗口）。
 */
import { formatInTimezone } from '@/utils/timezone'
import type { DebugSample } from '@/services/deviceApi'
import {
  SERIES_DEFS,
  formatSeriesValue,
  isOutOfRange,
  isPlottable,
  readSeries,
  type SeriesKey,
} from './debugMetrics'

/* ═══════════ 序列取值 ═══════════ */

export interface SeriesValues {
  /** 与 samples 等长；null = 无数据或越界（曲线断线，不连） */
  values: (number | null)[]
  /** 被剔除的越界点数（脏值证据，UI 里明示） */
  dropped: number
  /** 有效点数 */
  valid: number
}

/**
 * 取绘图序列：越界点不参与绘图（单个脏值会把纵轴撑爆、正常值全被压平），
 * 但会计数并在界面明示；表格仍逐行展示原值并标红。
 */
export function buildSeriesValues(samples: readonly DebugSample[], key: SeriesKey): SeriesValues {
  const values: (number | null)[] = new Array(samples.length)
  let dropped = 0
  let valid = 0
  for (let i = 0; i < samples.length; i += 1) {
    const raw = readSeries(samples[i], key)
    if (isPlottable(key, raw)) {
      values[i] = raw
      valid += 1
    } else {
      values[i] = null
      if (isOutOfRange(key, raw)) dropped += 1
    }
  }
  return { values, dropped, valid }
}

/* ═══════════ 窗口统计 ═══════════ */

export interface SeriesStat {
  key: SeriesKey
  /** 参与统计的有效点（越界点不计入，避免脏值污染 min/max） */
  valid: number
  dropped: number
  min: number | null
  max: number | null
  avg: number | null
  /** 最后一个有效值 */
  last: number | null
}

export function computeSeriesStat(samples: readonly DebugSample[], key: SeriesKey): SeriesStat {
  let min: number | null = null
  let max: number | null = null
  let sum = 0
  let valid = 0
  let dropped = 0
  let last: number | null = null
  for (const sample of samples) {
    const raw = readSeries(sample, key)
    if (isOutOfRange(key, raw)) {
      dropped += 1
      continue
    }
    if (raw == null) continue
    valid += 1
    sum += raw
    min = min == null ? raw : Math.min(min, raw)
    max = max == null ? raw : Math.max(max, raw)
    last = raw
  }
  return {
    key,
    valid,
    dropped,
    min,
    max,
    avg: valid > 0 ? sum / valid : null,
    last,
  }
}

/** 单测/表格：一条曲线的统计文案（如 "50.20 ~ 52.10 V"） */
export function formatStatRange(key: SeriesKey, stat: SeriesStat): string {
  const unit = SERIES_DEFS[key]?.unit ?? ''
  if (stat.min == null || stat.max == null) return ''
  return `${formatSeriesValue(key, stat.min)} ~ ${formatSeriesValue(key, stat.max)} ${unit}`.trim()
}

/* ═══════════ 纵轴范围 ═══════════ */

/** 1-1.2-1.5-2-2.5-3-4-5-6-7.5-8-10 档：比只取 1/2/5 更贴数据，轴标签仍是整数 */
const NICE_STEPS = [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5, 8, 10] as const

/** 纵轴上下各留 5% 余量，曲线不贴网格边 */
const AXIS_HEADROOM = 1.05

/** 向上取到「好看」的刻度（1.2×10^n 这种） */
export function niceCeil(v: number): number {
  const abs = Math.abs(v)
  if (!Number.isFinite(abs) || abs === 0) return 0
  const exp = Math.floor(Math.log10(abs))
  const base = 10 ** exp
  const f = abs / base
  const step = NICE_STEPS.find((s) => f <= s + 1e-9) ?? 10
  return step * base
}

/**
 * 纵轴范围。symmetric=true 时以 0 为中心对称展开（正负轴：充电/放电、感性/容性
 * 都能上下分开读，三条纵轴的零线重合在网格中线）；false 时贴数据压缩。
 * 两端各留 5% 余量再取整，避免曲线正好贴着网格上下沿。
 */
export function buildAxisRange(values: readonly number[], symmetric: boolean): [number, number] | null {
  const finite = values.filter((v) => Number.isFinite(v))
  if (finite.length === 0) return null
  let min = finite[0]
  let max = finite[0]
  for (const v of finite) {
    if (v < min) min = v
    if (v > max) max = v
  }
  if (symmetric) {
    const m = niceCeil(Math.max(Math.abs(min), Math.abs(max)) * AXIS_HEADROOM)
    // 全 0 也留一条可读的带子，避免退化成一条线
    return m === 0 ? [-1, 1] : [-m, m]
  }
  const hi = niceCeil(Math.max(max, 0) * AXIS_HEADROOM)
  const lo = min < 0 ? -niceCeil(-min * AXIS_HEADROOM) : 0
  return hi === lo ? [lo, lo + 1] : [lo, hi]
}

/* ═══════════ 质量位判读（与 device-communication telemetry 位定义一致）═══════════ */

export interface QualityFlagDef {
  bit: number
  labelKey: string
  severity: 'error' | 'warning'
}

export const QUALITY_FLAGS: readonly QualityFlagDef[] = [
  { bit: 1, labelKey: 'deviceDetail.debug.quality.partial', severity: 'warning' },
  { bit: 2, labelKey: 'deviceDetail.debug.quality.outOfRange', severity: 'error' },
  { bit: 4, labelKey: 'deviceDetail.debug.quality.clock', severity: 'warning' },
  { bit: 8, labelKey: 'deviceDetail.debug.quality.outOfOrder', severity: 'warning' },
  { bit: 16, labelKey: 'deviceDetail.debug.quality.counterReset', severity: 'warning' },
  { bit: 32, labelKey: 'deviceDetail.debug.quality.commFault', severity: 'error' },
]

/** 该质量位组合命中的标记（按位从小到大） */
export function qualityFlagsOf(flags: number | null | undefined): QualityFlagDef[] {
  if (!flags) return []
  return QUALITY_FLAGS.filter((f) => (flags & f.bit) !== 0)
}

/** 质量列的整体严重度：有 error 位取 error，否则有 warning 位取 warning，无位返回 null */
export function qualitySeverity(flags: number | null | undefined): 'error' | 'warning' | null {
  const hit = qualityFlagsOf(flags)
  if (hit.length === 0) return null
  return hit.some((f) => f.severity === 'error') ? 'error' : 'warning'
}

/* ═══════════ CSV 导出 ═══════════ */

function csvCell(value: string | number): string {
  const text = String(value)
  return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
}

export interface CsvOptions {
  timezone: string
  /** 表头文案：时间列 + 质量列 + 各曲线列（由调用方翻译） */
  headers: { time: string; quality: string; series: Record<string, string> }
  /** 质量位的可读文案 */
  qualityText: (flags: number) => string
}

/** 导出采样明细（时间升序，Excel 友好：带 BOM、字段转义） */
export function buildCsv(
  samples: readonly DebugSample[],
  keys: readonly SeriesKey[],
  options: CsvOptions,
): string {
  const cols = keys.filter((k) => SERIES_DEFS[k])
  const header = [options.headers.time, options.headers.quality, ...cols.map((k) => options.headers.series[k] ?? k)]
  const lines = [header.map(csvCell).join(',')]
  for (const sample of samples) {
    const row: (string | number)[] = [
      formatInTimezone(sample.time, options.timezone, 'YYYY-MM-DD HH:mm:ss'),
      options.qualityText(sample.quality_flags ?? 0),
    ]
    for (const key of cols) {
      const value = readSeries(sample, key)
      const def = SERIES_DEFS[key]
      const text = value == null ? '' : `${value.toFixed(def.precision)}`
      const flagged = isOutOfRange(key, value) ? ` ${def.unit}!` : ''
      row.push(text === '' ? '' : `${text}${flagged}`)
    }
    lines.push(row.map(csvCell).join(','))
  }
  // BOM：Excel 打开中文表头不乱码
  return `\uFEFF${lines.join('\r\n')}\r\n`
}
