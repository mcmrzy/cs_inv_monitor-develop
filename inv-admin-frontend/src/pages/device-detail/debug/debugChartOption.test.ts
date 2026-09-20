/**
 * 曲线 option 单测：三条纵轴、正负对称、越界剔除、派生功率虚线、tooltip 精度。
 * 现场数据（SN H1ZZX0023900002P）：逆变电流 1334A、交流电流 618.7A 两个脏值。
 */
import { describe, expect, it } from 'vitest'

import type { DebugSample } from '@/services/deviceApi'
import { buildDebugChartOption } from './debugChartOption'
import type { SeriesKey } from './debugMetrics'

const LABELS: Record<string, string> = {
  battery_voltage: '电池电压',
  battery_current: '电池电流',
  battery_power: '电池功率（计算）',
  ac_voltage: '交流电压',
  inv_current: '逆变电流',
  inv_power: '逆变功率（计算）',
}

const AXIS_NAMES = { voltage: 'V', current: 'A', power: 'W' } as const

function sample(metrics: Record<string, number | null>, time?: string): DebugSample {
  return {
    time: time ?? '2026-09-20T08:00:00Z',
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

function build(samples: DebugSample[], selected: SeriesKey[], symmetric = true) {
  return buildDebugChartOption({
    samples,
    selected,
    labels: LABELS,
    timezone: 'Asia/Shanghai',
    symmetric,
    axisNames: AXIS_NAMES,
  })
}

const lineSeries = (option: Record<string, any>) => option.series.filter((s: any) => s.type === 'line')

describe('buildDebugChartOption', () => {
  it('无样本或所选曲线全无数据时返回 null（UI 退化为空态）', () => {
    expect(build([], ['ac_voltage']).option).toBeNull()
    expect(build([sample({})], ['ac_voltage']).option).toBeNull()
  })

  it('越界脏值不画曲线，且计入 dropped（界面据此明示剔除数量）', () => {
    const samples = [
      sample({ ac_voltage: 230, inv_current: 8 }, '2026-09-20T08:00:00Z'),
      sample({ ac_voltage: 231, inv_current: 1334 }, '2026-09-20T08:00:05Z'),
      sample({ ac_voltage: 229, inv_current: 9 }, '2026-09-20T08:00:10Z'),
    ]
    const { option, dropped } = build(samples, ['inv_current'])
    expect(dropped).toBe(1)
    const data = lineSeries(option!)[0].data
    // 纵轴不会被 1334 撑着：范围只按 8~9A 取
    expect(data[1]).toBeNull()
    const yAxis = (option!.yAxis as any[])[0]
    expect(yAxis.max).toBeLessThan(20)
  })

  it('三条纵轴：电压左轴、电流右轴、计算功率右侧偏移轴', () => {
    const samples = [sample({ battery_voltage: 51.2, battery_current: 12, ac_voltage: 230 })]
    const { option } = build(samples, ['battery_voltage', 'battery_current', 'battery_power'])
    const axes = option!.yAxis as any[]
    expect(axes).toHaveLength(3)
    expect(axes[0]).toMatchObject({ position: 'left', name: 'V' })
    expect(axes[1]).toMatchObject({ position: 'right', name: 'A', offset: 0 })
    expect(axes[2]).toMatchObject({ position: 'right', name: 'W', offset: 54 })
    const lines = lineSeries(option!)
    expect(lines.map((s: any) => s.yAxisIndex)).toEqual([0, 1, 2])
  })

  it('正负轴：三条纵轴都跨 0，且每条轴标一次零线', () => {
    const samples = [sample({ battery_voltage: 51.2, battery_current: -9.5 })]
    const { option } = build(samples, ['battery_voltage', 'battery_current'], true)
    for (const axis of option!.yAxis as any[]) {
      expect(axis.min).toBeLessThan(0)
      expect(axis.max).toBeGreaterThan(0)
      expect(axis.min).toBe(-axis.max)
    }
    const zeroLines = lineSeries(option!).filter((s: any) =>
      (s.markLine?.data ?? []).some((d: any) => d.yAxis === 0))
    expect(zeroLines).toHaveLength(2)
  })

  it('关闭正负轴：贴数据压缩（电压轴从 0 起）', () => {
    const samples = [sample({ battery_voltage: 51.2, battery_current: 12 })]
    const { option } = build(samples, ['battery_voltage', 'battery_current'], false)
    const axes = option!.yAxis as any[]
    expect(axes.some((a) => a.min === 0)).toBe(true)
    expect(axes.every((a) => a.min === -a.max)).toBe(false)
  })

  it('派生功率用虚线，实测曲线用实线', () => {
    const samples = [sample({ battery_voltage: 51.2, battery_current: 12 })]
    const { option } = build(samples, ['battery_voltage', 'battery_power'])
    const lines = lineSeries(option!)
    expect(lines[0].lineStyle.type).toBe('solid')
    expect(lines[1].lineStyle.type).toBe('dashed')
  })

  it('tooltip 按测点精度格式化（不再有 51.20000076293945）', () => {
    const samples = [sample({ battery_voltage: 51.20000076293945, battery_current: 12 })]
    const { option } = build(samples, ['battery_voltage', 'battery_power'])
    const formatter = (option!.tooltip as any).formatter as (p: unknown) => string
    const html = formatter([
      { axisValueLabel: '16:00:00', seriesName: LABELS.battery_voltage, color: '#34d399', value: 51.20000076293945 },
      { axisValueLabel: '16:00:00', seriesName: LABELS.battery_power, color: '#6ee7b7', value: 614.4 },
    ])
    expect(html).toContain('51.20 V')
    expect(html).toContain('614.4 W')
    expect(html).not.toContain('51.20000076293945')
  })

  it('图例只列有数据的曲线，且带上「计算」后缀区分', () => {
    const samples = [sample({ battery_voltage: 51.2, battery_current: 12 })]
    const { option } = build(samples, ['battery_voltage', 'battery_power', 'ac_voltage'])
    const legend = option!.legend as any
    expect(legend.data).toEqual([LABELS.battery_voltage, LABELS.battery_power])
  })

  it('最新点脉冲光斑与曲线一一对应（≤6 条时）', () => {
    const samples = [sample({ battery_voltage: 51.2, battery_current: 12 })]
    const { option } = build(samples, ['battery_voltage', 'battery_current'])
    const dots = (option!.series as any[]).filter((s) => s.type === 'effectScatter')
    expect(dots).toHaveLength(2)
    expect(dots[0].data).toEqual([[0, 51.2]])
  })
})
