import { describe, expect, it } from 'vitest'
import { bmsAvailability, cellExtrema, parseBmsSummary, summaryFlags, summaryTimestamp, SUMMARY_FIELDS } from './bmsSummary'

export const NOW = Date.parse('2026-10-08T08:00:00Z')
export function sample(overrides: Record<string, unknown> = {}) {
  return { layout: 0, bms_online: 1, battery_count: 1, soc_raw: 726, age_ms: 8_000,
    soc: 72.6, soh: 97.8, soh_raw: 978, voltage: 52.78, current: -8.4,
    expires_at: new Date(NOW + 210_000).toISOString(), updated_at: new Date(NOW - 8_000).toISOString(), reported_at: new Date(NOW).toISOString(),
    capacity_remain: 43.56, capacity_full: 60, capacity_design: 64, cycle_count: 128,
    warning_flag: 0, protection_flag: 0, status_fault_flag: (1 << 9) | (1 << 11), balance_status: 1 << 4,
    cell_voltages: [3298, 3301, 3296, 3302, 3304, 3299, 3300, 3297, 3303, 3295, 3301, 3299, 3302, 3298, 3300, 0],
    cell_temperatures: [null, null, null, null], max_cell_voltage: 3500, min_cell_voltage: 3295,
    max_cell_temp: null, min_cell_temp: null, mos_temp: -3.2, pcb_temp: 32.8, env_temp: 26.4,
    battery_mode: 2, battery_status: 1, system_mode: 0, charging_voltage: null,
    total_chg_capacity_raw: 4294967295, total_dsg_capacity_raw: 129430,
    chg_request_current_raw: 3000, chg_request_voltage_raw: -5600,
    raw_bytes: Array.from({ length: 100 }, (_, i) => i), ...overrides }
}
const parse = (v = sample()) => parseBmsSummary({ bms_summary: v })!

describe('CMD08 summary normalization', () => {
  it('preserves all engineering values, raw quantities, bytes and fixed slots', () => {
    const v = sample(), parsed = parse(v)
    expect(Object.keys(parsed.values)).toEqual([...SUMMARY_FIELDS])
    for (const key of SUMMARY_FIELDS) expect(parsed.values[key]).toEqual(v[key as keyof typeof v] ?? null)
    expect(parsed.values.current).toBe(-8.4)
    expect(parsed.values.chg_request_voltage_raw).toBe(-5600)
    expect(parsed.rawBytes).toHaveLength(100)
    expect(parsed.cells).toHaveLength(16)
    expect(parsed.cells[15]).toBeNull()
  })
  it('supports flat and wrapped snapshots but not missing legacy data', () => {
    expect(parseBmsSummary({ bms_summary: { data: sample(), timestamp: NOW / 1000 } })).toEqual(parse())
    expect(parseBmsSummary({ bms: { bms_online: 1 } })).toBeNull()
    expect(parseBmsSummary({ bms_summary: 'invalid', bms: {} })).not.toBeNull()
  })
  it('does not manufacture cells or bytes from invalid inputs', () => {
    const parsed = parse(sample({ cell_voltages: [0, null, '', '3300', -1, 1.5, 65536], raw_bytes: Array(100).fill(256) }))
    expect(parsed.cells).toEqual(Array(16).fill(null))
    expect(parsed.rawBytes).toBeNull()
  })
  it('derives extrema only from valid cells, not reported extrema', () => {
    expect(cellExtrema(parse().cells)).toMatchObject({ count: 15, max: 3304, min: 3295, spread: 9, maxIndex: 4, minIndex: 9 })
    expect(cellExtrema(Array(16).fill(null))).toMatchObject({ max: null, min: null, spread: null })
  })
})
describe('Independent BMS freshness', () => {
  it('remains valid between 180s heartbeats and expires at its own deadline', () => {
    expect(bmsAvailability(parse(), NOW + 150_000)).toBe('live')
    expect(bmsAvailability(parse(), NOW + 210_000)).toBe('expired')
  })
  it.each([{}, { expires_at: null }, { expires_at: '2026-10-08T08:03:30' }, { expires_at: 'not-a-date' }, { expires_at: '2026-02-30T08:00:00Z' }, { expires_at: new Date(NOW + 215_001).toISOString() }])('treats missing/invalid expiry as unknown: %j', overrides => {
    const v = Object.keys(overrides).length ? sample(overrides) : sample({ expires_at: undefined })
    expect(bmsAvailability(parse(v), NOW)).toBe('unknown')
  })
  it.each([{ bms_online: 0 }, { battery_count: 0 }, { soc_raw: 255 }, { age_ms: 120001 }])('offline marker: %j', overrides => {
    expect(bmsAvailability(parse(sample(overrides)), NOW)).toBe('offline')
  })
  it.each([{ bms_online: null }, { battery_count: null }, { soc_raw: null }, { age_ms: null }, { age_ms: -1 }, { layout: 1 }])('unknown marker: %j', overrides => {
    expect(bmsAvailability(parse(sample(overrides)), NOW)).toBe('unknown')
  })
  it('accepts explicit timezone offsets but not impossible calendar dates', () => {
    expect(summaryTimestamp('2026-10-08T16:00:00+08:00')).toBe(NOW)
    expect(summaryTimestamp('2026-10-08T24:00:00Z')).toBeNull()
  })
})
describe('CMD08 flag layout', () => {
  it('operating states are not faults', () => {
    const flags = summaryFlags(parse(sample({ status_fault_flag: [8, 9, 10, 11, 12, 14, 15].reduce((v, bit) => v | (1 << bit), 0) })))
    expect(flags.fault.active).toEqual([])
    expect(flags.operations.active).toHaveLength(7)
    expect(flags.activeCount).toBe(0)
    expect(flags.allKnown).toBe(true)
  })
  it('separates warning/protection and actual fault definitions', () => {
    const flags = summaryFlags(parse(sample({ warning_flag: 2, protection_flag: 1 << 6, status_fault_flag: (1 << 4) | (1 << 9) })))
    expect(flags.warning.active).toEqual([{ bit: 1, key: 'cellUv' }])
    expect(flags.protection.active).toEqual([{ bit: 6, key: 'sc' }])
    expect(flags.fault.active).toEqual([{ bit: 4, key: 'cellFault' }])
    expect(flags.activeCount).toBe(3)
  })
  it('reserved and missing flags are not claimed healthy', () => {
    expect(summaryFlags(parse(sample({ warning_flag: 1 << 6, status_fault_flag: 1 << 13 }))).allKnown).toBe(false)
    expect(summaryFlags(parse(sample({ warning_flag: null }))).allKnown).toBe(false)
  })
})
