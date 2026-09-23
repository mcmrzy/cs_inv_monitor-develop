/**
 * 设备调试页的测点模型（图示端共用的唯一事实源）。
 *
 * 三件事在这里定死：
 *  1. 每个测点的物理量程（与 device-communication/internal/telemetry 的 bounded()
 *     一致）——ARM 固件会输出垃圾值（如视在功率 2883584VA、逆变电流 1334A），
 *     超出量程的一律判为脏值：曲线剔除（否则单点把纵轴撑爆、正常值全被压平），
 *     表格标红保留证据。
 *  2. 派生功率 P = U × I —— 只有同一电路节点的电压电流才配对相乘，
 *     逆变组用交流电压配逆变电流（逆变电流是逆变器输出侧的交流电流，
 *     乘直流母线电压没有物理意义）。
 *  3. 显示精度 —— 后端已把 float32 表示噪声规整到 3 位小数，
 *     展示层再按测点定小数位，避免 51.20000076293945 这类长浮点上屏。
 */
import type { DebugSample, DebugSampleMetrics } from '@/services/deviceApi'

export type MetricKey = keyof DebugSampleMetrics
export type PowerKey = 'pv1_power' | 'pv2_power' | 'battery_power' | 'inv_power' | 'load_power'
export type SeriesKey = MetricKey | PowerKey
/** 纵轴分组：电压(V) / 电流(A) / 计算功率(W)，各自一个纵轴 */
export type AxisKey = 'voltage' | 'current' | 'power'
export type GroupKey = 'mppt' | 'battery' | 'inverter' | 'load'
export type Unit = 'V' | 'A' | 'W'

export interface SeriesDef {
  key: SeriesKey
  axis: AxisKey
  color: string
  unit: Unit
  /** 物理量程 [min, max]；null = 派生量（由已校验测点相乘，不重复判定越界） */
  range: [number, number] | null
  /** 显示小数位 */
  precision: number
  /** 派生功率：由哪两个测点相乘（[电压, 电流]） */
  derivedFrom?: readonly [MetricKey, MetricKey]
  labelKey: string
}

const METRIC_LABEL_KEYS: Record<MetricKey, string> = {
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

/** 实测测点定义（顺序即选线区的展示顺序） */
export const METRIC_KEYS: readonly MetricKey[] = [
  'pv1_voltage', 'buck1_current', 'pv2_voltage', 'buck2_current',
  'battery_voltage', 'battery_current',
  'dc_bus_voltage', 'inv_current',
  'ac_voltage', 'ac_current',
]

/**
 * 配色（白底彩线，2026-09-20 由深色示波器改为浅色）：
 *  - 同一分组的电压/电流同色系，靠明度分开（电压亮、电流深）；
 *  - 派生功率换一个饱和色系 + 虚线，避免与同组实测曲线混色；
 *  - 所有色值都取 500~800 档，保证白底上的对比度。
 */
const METRIC_SPECS: Record<MetricKey, Omit<SeriesDef, 'key' | 'labelKey'>> = {
  // PV 正常工作电压 60~500V；<60V 是残压/无输入（有效读数，不上限），>500V 才判脏值
  // （对齐 heartbeat_v3.go：pvVoltageFloor=60 归 0、bounded 0~500）
  pv1_voltage: { axis: 'voltage', color: '#f59e0b', unit: 'V', range: [0, 500], precision: 2 },
  buck1_current: { axis: 'current', color: '#b45309', unit: 'A', range: [0, 30], precision: 2 },
  pv2_voltage: { axis: 'voltage', color: '#06b6d4', unit: 'V', range: [0, 500], precision: 2 },
  buck2_current: { axis: 'current', color: '#0e7490', unit: 'A', range: [0, 30], precision: 2 },
  battery_voltage: { axis: 'voltage', color: '#10b981', unit: 'V', range: [0, 70], precision: 2 },
  battery_current: { axis: 'current', color: '#047857', unit: 'A', range: [-150, 150], precision: 2 },
  dc_bus_voltage: { axis: 'voltage', color: '#8b5cf6', unit: 'V', range: [0, 500], precision: 2 },
  inv_current: { axis: 'current', color: '#5b21b6', unit: 'A', range: [0, 100], precision: 2 },
  ac_voltage: { axis: 'voltage', color: '#ef4444', unit: 'V', range: [0, 250], precision: 2 },
  ac_current: { axis: 'current', color: '#9f1239', unit: 'A', range: [0, 100], precision: 2 },
}

export const METRIC_DEFS: Record<MetricKey, SeriesDef> = METRIC_KEYS.reduce(
  (acc, key) => {
    acc[key] = { key, labelKey: METRIC_LABEL_KEYS[key], ...METRIC_SPECS[key] }
    return acc
  },
  {} as Record<MetricKey, SeriesDef>,
)

/** 派生功率定义（每个换一个饱和色系 + 虚线：白底上既醒目又不会被当成实测值） */
const POWER_SPECS: Record<PowerKey, { color: string; labelKey: string; derivedFrom: readonly [MetricKey, MetricKey] }> = {
  pv1_power: {
    color: '#0d9488', labelKey: 'deviceDetail.debug.metric.pv1Power',
    derivedFrom: ['pv1_voltage', 'buck1_current'],
  },
  pv2_power: {
    color: '#4f46e5', labelKey: 'deviceDetail.debug.metric.pv2Power',
    derivedFrom: ['pv2_voltage', 'buck2_current'],
  },
  battery_power: {
    color: '#ea580c', labelKey: 'deviceDetail.debug.metric.batteryPower',
    derivedFrom: ['battery_voltage', 'battery_current'],
  },
  inv_power: {
    color: '#9333ea', labelKey: 'deviceDetail.debug.metric.invPower',
    derivedFrom: ['ac_voltage', 'inv_current'],
  },
  load_power: {
    color: '#2563eb', labelKey: 'deviceDetail.debug.metric.loadPower',
    derivedFrom: ['ac_voltage', 'ac_current'],
  },
}

export const POWER_KEYS: readonly PowerKey[] = [
  'pv1_power', 'pv2_power', 'battery_power', 'inv_power', 'load_power',
]

export const POWER_DEFS: Record<PowerKey, SeriesDef> = POWER_KEYS.reduce(
  (acc, key) => {
    const spec = POWER_SPECS[key]
    acc[key] = {
      key,
      labelKey: spec.labelKey,
      axis: 'power',
      color: spec.color,
      unit: 'W',
      range: null,
      precision: 1,
      derivedFrom: spec.derivedFrom,
    }
    return acc
  },
  {} as Record<PowerKey, SeriesDef>,
)

export const SERIES_DEFS: Record<SeriesKey, SeriesDef> = {
  ...METRIC_DEFS,
  ...POWER_DEFS,
}

/** 全部可选曲线（实测 + 计算功率），顺序即选线区展示顺序 */
export const ALL_SERIES: readonly SeriesKey[] = [...METRIC_KEYS, ...POWER_KEYS]

export interface DebugGroup {
  key: GroupKey
  metrics: readonly MetricKey[]
  powers: readonly PowerKey[]
}

export const GROUPS: readonly DebugGroup[] = [
  { key: 'mppt', metrics: ['pv1_voltage', 'buck1_current', 'pv2_voltage', 'buck2_current'], powers: ['pv1_power', 'pv2_power'] },
  { key: 'battery', metrics: ['battery_voltage', 'battery_current'], powers: ['battery_power'] },
  { key: 'inverter', metrics: ['dc_bus_voltage', 'inv_current'], powers: ['inv_power'] },
  { key: 'load', metrics: ['ac_voltage', 'ac_current'], powers: ['load_power'] },
]

export function groupSeries(group: DebugGroup): SeriesKey[] {
  return [...group.metrics, ...group.powers]
}

/** 默认勾选：电池与交流输出两组的电压/电流 + 各自的派生功率 */
export const DEFAULT_SELECTED: readonly SeriesKey[] = [
  'battery_voltage', 'battery_current', 'battery_power',
  'ac_voltage', 'ac_current', 'load_power',
]

/** 是否派生（计算）曲线：图例/表头/徽标上要标注，避免被当成实测值 */
export function isDerived(key: SeriesKey): boolean {
  return SERIES_DEFS[key]?.derivedFrom != null
}

function round3(v: number): number {
  const r = Math.round(v * 1000) / 1000
  return r === 0 ? 0 : r
}

/** 读单个实测测点：缺失/非有限数（NaN、Infinity）一律当无数据 */
export function readMetric(sample: DebugSample | null | undefined, key: MetricKey): number | null {
  const raw = sample?.metrics?.[key]
  return typeof raw === 'number' && Number.isFinite(raw) ? raw : null
}

/**
 * 读曲线值（含派生功率）。任一分量缺失 → null（曲线断线、表格显示 —）。
 * 派生功率不做越界判定，但**分量越界时一并作废**：脏值乘积（如 230V × 618.7A）
 * 会把功率轴也撑爆，等于脏值换个字段上屏。
 */
export function readSeries(sample: DebugSample | null | undefined, key: SeriesKey): number | null {
  const def = SERIES_DEFS[key]
  if (!def) return null
  if (!def.derivedFrom) return readMetric(sample, key as MetricKey)
  const [vk, ik] = def.derivedFrom
  const v = readMetric(sample, vk)
  const i = readMetric(sample, ik)
  if (v == null || i == null) return null
  if (isOutOfRange(vk, v) || isOutOfRange(ik, i)) return null
  return round3(v * i)
}

/** 值是否超出物理量程（脏值判据）；null 不算越界 */
export function isOutOfRange(key: SeriesKey, value: number | null): boolean {
  if (value == null) return false
  const range = SERIES_DEFS[key]?.range
  if (!range) return false
  return value < range[0] || value > range[1]
}

/** 该点是否可用于绘图：有值且未越界 */
export function isPlottable(key: SeriesKey, value: number | null): boolean {
  return value != null && !isOutOfRange(key, value)
}

/** 按测点精度格式化（不带单位）；无值返回占位符 */
export function formatSeriesValue(key: SeriesKey, value: number | null, placeholder = '--'): string {
  if (value == null) return placeholder
  const def = SERIES_DEFS[key]
  if (!def || !Number.isFinite(value)) return placeholder
  return value.toFixed(def.precision)
}

/** 量程文案（表格越界提示用）：如 "0 ~ 100 A" */
export function rangeText(key: SeriesKey): string {
  const def = SERIES_DEFS[key]
  if (!def?.range) return ''
  const [min, max] = def.range
  return `${min} ~ ${max} ${def.unit}`
}
