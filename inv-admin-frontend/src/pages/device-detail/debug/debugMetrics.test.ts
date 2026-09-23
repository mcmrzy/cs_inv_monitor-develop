/**
 * 测点模型单测：派生功率、越界判据、精度格式化。
 * 边界值来自现场（SN H1ZZX0023900002P 的 ARM 脏心跳：逆变电流 1334A、交流电流 618.7A）。
 */
import { describe, expect, it } from 'vitest'

import type { DebugSample } from '@/services/deviceApi'
import {
  DEFAULT_SELECTED,
  METRIC_KEYS,
  METRIC_DEFS,
  POWER_DEFS,
  SERIES_DEFS,
  formatSeriesValue,
  groupSeries,
  isDerived,
  isOutOfRange,
  isPlottable,
  rangeText,
  readMetric,
  readSeries,
  GROUPS,
} from './debugMetrics'

function sample(metrics: Partial<Record<string, number | null>>): DebugSample {
  return {
    time: '2026-09-20T08:00:00Z',
    received_at: null,
    quality_flags: 0,
    protocol_version: 2,
    metrics: {
      pv1_voltage: null, buck1_current: null, pv2_voltage: null, buck2_current: null,
      battery_voltage: null, battery_current: null, dc_bus_voltage: null, inv_current: null,
      ac_voltage: null, ac_current: null,
      ...metrics,
    } as DebugSample['metrics'],
  }
}

describe('debugMetrics 测点定义', () => {
  it('每个实测测点都有量程与精度，且默认勾选的 key 都存在', () => {
    for (const key of METRIC_KEYS) {
      const def = METRIC_DEFS[key]
      expect(def.range, `${key} 缺少量程`).not.toBeNull()
      expect(def.precision).toBeGreaterThanOrEqual(0)
      expect(isDerived(key)).toBe(false)
    }
    for (const key of DEFAULT_SELECTED) expect(SERIES_DEFS[key], `${key} 未定义`).toBeTruthy()
    expect(GROUPS.map((g) => g.key)).toEqual(['mppt', 'battery', 'inverter', 'load'])
  })

  it('每个分组都能给出「实测 + 计算功率」的完整曲线清单', () => {
    const battery = GROUPS.find((g) => g.key === 'battery')!
    expect(groupSeries(battery)).toEqual(['battery_voltage', 'battery_current', 'battery_power'])
    for (const key of groupSeries(battery)) expect(isDerived(key) === (key === 'battery_power')).toBe(true)
  })
})

describe('readSeries 派生功率', () => {
  it('P = U × I（电池：51.2V × 12.5A = 640W）', () => {
    const s = sample({ battery_voltage: 51.2, battery_current: 12.5 })
    expect(readSeries(s, 'battery_voltage')).toBe(51.2)
    expect(readSeries(s, 'battery_power')).toBe(640)
  })

  it('放电（电流为负）时功率为负，符号随电流', () => {
    const s = sample({ battery_voltage: 51.2, battery_current: -9.5 })
    expect(readSeries(s, 'battery_power')).toBeCloseTo(-486.4, 3)
  })

  it('逆变功率用交流电压（不是直流母线电压）', () => {
    const s = sample({ ac_voltage: 230, inv_current: 10, dc_bus_voltage: 380 })
    expect(readSeries(s, 'inv_power')).toBe(2300)
  })

  it('PV 正常工作电压 299V 不再被误杀，派生功率照常计算', () => {
    const s = sample({ pv1_voltage: 299, buck1_current: 8 })
    expect(readSeries(s, 'pv1_voltage')).toBe(299)
    expect(readSeries(s, 'pv1_power')).toBe(2392)
  })

  it('分量为 null → 功率为 null（曲线断线，表格显示 —）', () => {
    expect(readSeries(sample({ battery_voltage: 51.2 }), 'battery_power')).toBeNull()
    expect(readSeries(sample({ battery_current: 3 }), 'battery_power')).toBeNull()
  })

  it('分量越界（固件脏值）→ 功率一并作废，不让脏值乘积把功率轴撑爆', () => {
    // 现场实测：ac_current=618.7（量程 0~100）、inv_current=1334（量程 0~100）
    expect(readSeries(sample({ ac_voltage: 230, ac_current: 618.7 }), 'load_power')).toBeNull()
    expect(readSeries(sample({ ac_voltage: 230, inv_current: 1334 }), 'inv_power')).toBeNull()
  })

  it('非有限数（NaN/Infinity）按无数据处理', () => {
    expect(readMetric(sample({ ac_voltage: Number.NaN }), 'ac_voltage')).toBeNull()
    expect(readMetric(sample({ ac_voltage: Number.POSITIVE_INFINITY }), 'ac_voltage')).toBeNull()
  })
})

describe('越界判据', () => {
  it('PV 电压 0~530V：正常工作电压与 <60V 残压都有效，>530V 才判脏', () => {
    // 现场误杀：299V 正常工作电压曾被旧界 0~150 剔除
    expect(isOutOfRange('pv1_voltage', 299)).toBe(false)
    expect(isOutOfRange('pv2_voltage', 299)).toBe(false)
    // <60V 为残压/无输入，与 heartbeat_v3 的 pvVoltageFloor 语义一致：有效
    expect(isOutOfRange('pv1_voltage', 11)).toBe(false)
    expect(isOutOfRange('pv2_voltage', 45)).toBe(false)
    expect(isOutOfRange('pv1_voltage', 520)).toBe(false)
    expect(isOutOfRange('pv1_voltage', 530)).toBe(false)
    expect(isOutOfRange('pv1_voltage', 531)).toBe(true)
    // 量程文案随界值联动，不再出现 0 ~ 150 V
    expect(rangeText('pv1_voltage')).toBe('0 ~ 530 V')
  })

  it('超出物理量程判越界，null 与派生量不判', () => {
    expect(isOutOfRange('ac_current', 618.7)).toBe(true)
    expect(isOutOfRange('ac_current', 4.8)).toBe(false)
    expect(isOutOfRange('battery_current', -9.5)).toBe(false)
    expect(isOutOfRange('battery_current', -160)).toBe(true)
    expect(isOutOfRange('battery_power', 1e6)).toBe(false)
    expect(isOutOfRange('ac_current', null)).toBe(false)
  })

  it('isPlottable 只放行「有值且未越界」', () => {
    expect(isPlottable('inv_current', 8)).toBe(true)
    expect(isPlottable('inv_current', 1334)).toBe(false)
    expect(isPlottable('inv_current', null)).toBe(false)
  })

  it('rangeText 给出提醒文案', () => {
    expect(rangeText('inv_current')).toBe('0 ~ 100 A')
    expect(rangeText('battery_power')).toBe('')
  })
})

describe('formatSeriesValue', () => {
  it('按测点精度格式化，float32 噪声不再上屏', () => {
    // 后端规整前的原始 JSON 形态
    expect(formatSeriesValue('battery_voltage', 51.20000076293945)).toBe('51.20')
    expect(formatSeriesValue('ac_voltage', 229.8000030517578)).toBe('229.80')
    expect(formatSeriesValue('load_power', 1087.3)).toBe('1087.3')
  })

  it('无值给占位符', () => {
    expect(formatSeriesValue('ac_current', null)).toBe('--')
    expect(formatSeriesValue('ac_current', null, '—')).toBe('—')
  })
})

describe('派生功率定义完备性', () => {
  it('每个功率定义都能追溯到两个实测测点', () => {
    for (const [key, def] of Object.entries(POWER_DEFS)) {
      expect(def.derivedFrom, `${key} 缺少来源`).toBeTruthy()
      for (const src of def.derivedFrom!) expect(METRIC_DEFS[src], `${key} 来源 ${src} 不存在`).toBeTruthy()
      expect(def.axis).toBe('power')
      expect(def.unit).toBe('W')
    }
  })
})
