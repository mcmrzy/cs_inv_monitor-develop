/**
 * 分析工具单测：序列剔除、窗口统计、纵轴范围（正负对称）、质量位、CSV 导出。
 */
import { describe, expect, it } from 'vitest'

import type { DebugSample } from '@/services/deviceApi'
import {
  buildAxisRange,
  buildCsv,
  buildSeriesValues,
  computeSeriesStat,
  formatStatRange,
  niceCeil,
  qualityFlagsOf,
  qualitySeverity,
} from './debugAnalysis'

function sample(metrics: Record<string, number | null>, extra: Partial<DebugSample> = {}): DebugSample {
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
    ...extra,
  }
}

describe('buildSeriesValues', () => {
  it('越界点不参与绘图但被计数（曲线留空 = 断线）', () => {
    const samples = [
      sample({ ac_current: 4.8 }),
      sample({ ac_current: 618.7 }), // 现场脏值
      sample({ ac_current: 4.9 }),
      sample({ ac_current: null }),
    ]
    const { values, dropped, valid } = buildSeriesValues(samples, 'ac_current')
    expect(values).toEqual([4.8, null, 4.9, null])
    expect(dropped).toBe(1)
    expect(valid).toBe(2)
  })

  it('派生功率同理：分量越界时该点无功率', () => {
    const samples = [
      sample({ ac_voltage: 230, ac_current: 4.8 }),
      sample({ ac_voltage: 230, ac_current: 618.7 }),
    ]
    const { values, dropped } = buildSeriesValues(samples, 'load_power')
    expect(values[0]).toBe(1104)
    expect(values[1]).toBeNull()
    expect(dropped).toBe(0)
  })
})

describe('computeSeriesStat', () => {
  const samples = [
    sample({ battery_voltage: 51.2, battery_current: 12 }),
    sample({ battery_voltage: 52.0, battery_current: -9 }),
    sample({ battery_voltage: 51.6, battery_current: 3 }),
    sample({ battery_voltage: 999, battery_current: 0 }), // 越界，不进统计
  ]

  it('窗口统计只用有效点（越界不污染 min/max）', () => {
    const stat = computeSeriesStat(samples, 'battery_voltage')
    expect(stat.min).toBe(51.2)
    expect(stat.max).toBe(52)
    expect(stat.valid).toBe(3)
    expect(stat.dropped).toBe(1)
    expect(stat.avg).toBeCloseTo((51.2 + 52 + 51.6) / 3, 6)
    expect(stat.last).toBe(51.6)
  })

  it('功率统计跟随电流符号（最小值可为负）', () => {
    const stat = computeSeriesStat(samples, 'battery_power')
    expect(stat.max).toBeCloseTo(51.2 * 12, 3)
    expect(stat.min).toBeCloseTo(52 * -9, 3)
    expect(formatStatRange('battery_power', stat)).toBe(`${(52 * -9).toFixed(1)} ~ ${(51.2 * 12).toFixed(1)} W`)
  })

  it('全空窗口给 null，不抛错', () => {
    const stat = computeSeriesStat([sample({})], 'inv_current')
    expect(stat).toMatchObject({ valid: 0, min: null, max: null, avg: null, last: null })
    expect(formatStatRange('inv_current', stat)).toBe('')
  })
})

describe('纵轴范围', () => {
  it('对称轴：以 0 为中心，向上取整到好看刻度', () => {
    expect(buildAxisRange([-9.5, 12], true)).toEqual([-15, 15])
    expect(buildAxisRange([51.2, 52], true)).toEqual([-60, 60])
    expect(buildAxisRange([0, 0], true)).toEqual([-1, 1])
    expect(buildAxisRange([], true)).toBeNull()
  })

  it('紧凑轴：贴数据，有负值才向下扩', () => {
    expect(buildAxisRange([51.2, 52], false)).toEqual([0, 60])
    expect(buildAxisRange([-9.5, 12], false)).toEqual([-10, 15])
  })

  it('niceCeil 生成 1/1.2/1.5/2/2.5/3/4/5/6/7.5/8/10 档', () => {
    expect(niceCeil(0)).toBe(0)
    expect(niceCeil(1.1)).toBe(1.2)
    expect(niceCeil(12)).toBe(12)
    expect(niceCeil(12.1)).toBe(15)
    expect(niceCeil(618)).toBe(750)
    expect(niceCeil(-9.5)).toBe(10)
  })
})

describe('质量位判读', () => {
  it('按位映射到可读文案，且区分严重度', () => {
    expect(qualityFlagsOf(0)).toEqual([])
    expect(qualitySeverity(0)).toBeNull()
    expect(qualityFlagsOf(2).map((f) => f.labelKey)).toEqual(['deviceDetail.debug.quality.outOfRange'])
    expect(qualitySeverity(2)).toBe('error')
    expect(qualitySeverity(1)).toBe('warning')
    // 越界(2) + 缺组(1) → 取更严重的 error
    expect(qualityFlagsOf(3).length).toBe(2)
    expect(qualitySeverity(3)).toBe('error')
  })
})

describe('CSV 导出', () => {
  const options = {
    timezone: 'Asia/Shanghai',
    headers: { time: '时间', quality: '质量', series: { battery_voltage: '电池电压 (V)' } },
    qualityText: (flags: number) => (flags === 0 ? '正常' : '越界'),
  }

  it('带 BOM、时间升序、越界值加 ! 标记', () => {
    const samples = [
      sample({ battery_voltage: 51.2 }, { time: '2026-09-20T08:00:00Z' }),
      sample({ battery_voltage: 999 }, { time: '2026-09-20T08:00:05Z', quality_flags: 2 }),
    ]
    const csv = buildCsv(samples, ['battery_voltage'], options)
    const lines = csv.replace('\uFEFF', '').trim().split('\r\n')
    expect(lines[0]).toBe('时间,质量,电池电压 (V)')
    expect(lines[1]).toBe('2026-09-20 16:00:00,正常,51.20')
    expect(lines[2]).toBe('2026-09-20 16:00:05,越界,999.00 V!')
  })

  it('缺失值导出为空单元格', () => {
    const csv = buildCsv([sample({})], ['battery_voltage'], options)
    expect(csv.replace('\uFEFF', '').trim().split('\r\n')[1]).toBe('2026-09-20 16:00:00,正常,')
  })

  it('含逗号的文案按 CSV 规则转义', () => {
    const csv = buildCsv(
      [sample({ battery_voltage: 51.2 })],
      ['battery_voltage'],
      { ...options, headers: { time: '时,间', quality: '质量', series: {} } },
    )
    // series 未给文案时退回 key；含逗号的表头加引号
    expect(csv.split('\r\n')[0]).toBe('\uFEFF"时,间",质量,battery_voltage')
  })
})
