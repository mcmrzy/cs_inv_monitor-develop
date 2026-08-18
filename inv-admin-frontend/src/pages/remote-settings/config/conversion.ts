// 数据层换算与元数据解析
//
// 关键事实（已核对后端实现）：
//  1. V2.1 协议（docs/CS-L10-6K2_MQTT_上报协议设计_V2.1.md §9.1）起，config reported/desired
//     的值即为工程单位（物理量）——ESP32 固件读取 ARM 原始量纲后按参数 scale 换算再组包，
//     服务器与前端无需再换算（device-communication/telemetry/config_v2.go 同注）。
//  2. 后端 device_config_schema.scale 为 ARM→工程 倍率：physical = raw × schemaScale
//     （如 set_output_voltage scale=0.1，raw 2300 → 230.0 V），与本文件"用户侧倍率"互为倒数。
//  3. sendCommand 沿用现有命令构造：{ command: param_key, params: { value: 工程单位值 } }，
//     服务端按 schema min/max（工程单位）校验。
//
// 因此：换算函数 rawToPhysical/physicalToRaw 按任务书公式实现并导出（兼容原始量纲来源），
// normalizeIncoming 对 control-state 值做防御式归一：默认视为工程单位直用；仅当数值明显
// 超出物理量程、且除以倍率后落回量程时，判定为原始量纲并还原。

import type { ConfigSchemaItem, ControlKind, StaticFieldMeta } from './fields'
import { STATIC_FIELD_META } from './fields'

export interface EnumOption {
  value: number
  /** 语义键（标签走 i18n config.enum.<semanticKey>，缺失时直接显示） */
  semanticKey: string
}

export interface ResolvedFieldMeta {
  paramKey: string
  kind: ControlKind
  /** 用户侧倍率：raw = physical × scale（如 0.1V 分辨率字段 scale=10） */
  scale: number
  unit?: string
  min?: number
  max?: number
  step?: number
  enumOptions?: EnumOption[]
  visibility?: { param: string; eq?: number; ne?: number }
  confirm?: boolean
  /** 元数据来源：后端 schema 或静态兜底 */
  fromBackend: boolean
}

/** 后端 schema.scale（physical = raw × s）→ 用户侧倍率（raw = physical × 1/s） */
function backendScaleToMultiplier(s: number | null | undefined): number {
  if (!s || s <= 0 || s === 1) return 1
  return Math.round((1 / s) * 1000) / 1000
}

function enumOptionsFromMap(enumMap: Record<string, string> | null | undefined): EnumOption[] | undefined {
  if (!enumMap) return undefined
  const entries = Object.entries(enumMap)
  if (entries.length === 0) return undefined
  return entries
    .map(([raw, semantic]) => ({ value: Number(raw), semanticKey: semantic }))
    .filter((o) => Number.isFinite(o.value))
    .sort((a, b) => a.value - b.value)
}

/**
 * 解析字段最终元数据：后端 device_config_schema 优先，缺失项用静态定义兜底。
 */
export function resolveFieldMeta(
  schemaMap: Map<string, ConfigSchemaItem>,
  paramKey: string,
): ResolvedFieldMeta {
  const backend = schemaMap.get(paramKey)
  const fallback: StaticFieldMeta | undefined = STATIC_FIELD_META[paramKey]

  if (backend) {
    const enumOptions = enumOptionsFromMap(backend.enum_map)
    // 充电优先级虽然后端登记为 enum，UI 层固定用可排序列表呈现
    const kind: ControlKind =
      backend.control_type === 'boolean'
        ? 'boolean'
        : fallback?.kind === 'priority'
          ? 'priority'
          : backend.control_type === 'enum' || enumOptions
            ? 'enum'
            : fallback?.kind ?? 'number'
    return {
      paramKey,
      kind,
      scale: backendScaleToMultiplier(backend.scale),
      unit: backend.unit || fallback?.unit,
      min: backend.min ?? fallback?.min,
      max: backend.max ?? fallback?.max,
      step: backend.step ?? fallback?.step,
      enumOptions: enumOptions ?? fallback?.enumKeys?.map((k, i) => ({ value: i, semanticKey: k })),
      visibility: backend.visibility?.param
        ? { param: backend.visibility.param, eq: backend.visibility.eq, ne: backend.visibility.ne }
        : fallback?.visibility,
      confirm: backend.confirmation_mode === 'modal' || fallback?.confirm,
      fromBackend: true,
    }
  }

  if (fallback) {
    return {
      paramKey,
      kind: fallback.kind,
      scale: fallback.scale,
      unit: fallback.unit,
      min: fallback.min,
      max: fallback.max,
      step: fallback.step,
      enumOptions: fallback.enumKeys?.map((k, i) => ({ value: i, semanticKey: k })),
      visibility: fallback.visibility,
      confirm: fallback.confirm,
      fromBackend: false,
    }
  }

  // 完全未知参数（仅高级模式可能出现）：原始数值直显
  return { paramKey, kind: 'number', scale: 1, fromBackend: false }
}

// ── 换算函数（任务书公式：读取 = raw/scale，写入 = round(value×scale)）──

export function rawToPhysical(raw: number, meta: Pick<ResolvedFieldMeta, 'scale'>): number {
  if (!meta.scale || meta.scale === 1) return raw
  return Math.round((raw / meta.scale) * 1000) / 1000
}

export function physicalToRaw(value: number, meta: Pick<ResolvedFieldMeta, 'scale'>): number {
  if (!meta.scale || meta.scale === 1) return Math.round(value)
  return Math.round(value * meta.scale)
}

/**
 * control-state 入值归一：V2.1 起为工程单位直用；防御式兼容仍以原始量纲上报的旧固件
 * （数值超出物理量程且 raw/scale 落回量程时还原），避免误伤合法物理值。
 */
export function normalizeIncoming(raw: unknown, meta: ResolvedFieldMeta): number | undefined {
  if (raw === undefined || raw === null || raw === '') return undefined
  const num = Number(raw)
  if (!Number.isFinite(num)) return undefined
  if (meta.kind === 'boolean' || meta.kind === 'enum' || meta.kind === 'priority') return num
  if (!meta.scale || meta.scale === 1) return num
  if (meta.max !== undefined && Math.abs(num) > meta.max && meta.min !== undefined) {
    const scaled = rawToPhysical(num, meta)
    if (scaled >= meta.min && scaled <= meta.max) return scaled
  }
  return num
}

/** 显示小数位：由 step 决定（0.01→2、0.1→1、≥1→0） */
export function decimalsFor(meta: Pick<ResolvedFieldMeta, 'step'>): number {
  const step = meta.step
  if (!step || step <= 0 || !Number.isFinite(step)) return 0
  return Math.min(3, Math.max(0, Math.ceil(-Math.log10(step)) ))
}

export function formatNumber(value: number, meta: Pick<ResolvedFieldMeta, 'step' | 'unit'>): string {
  const text = value.toFixed(decimalsFor(meta))
  return meta.unit ? `${text} ${meta.unit}` : text
}

/** 单位本地化（后端 schema 返回中文单位如「节」，英文界面转为通用写法） */
export function displayUnit(unit: string | undefined, lang: string): string {
  if (!unit) return ''
  if (lang === 'en' && unit === '节') return 'cells'
  return unit
}
