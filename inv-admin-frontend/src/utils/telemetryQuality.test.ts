import { describe, expect, it } from 'vitest'
import { decodeTelemetryQuality, parseQualityFlags } from './telemetryQuality'

describe('telemetry quality flags', () => {
  it('treats zero as a normal sample', () => {
    expect(decodeTelemetryQuality(0)).toEqual({
      value: 0,
      flags: [],
      unknownMask: 0,
      isNormal: true,
    })
  })

  it('decodes the storage contract and preserves unknown bits', () => {
    const decoded = decodeTelemetryQuality(0x8b)

    expect(decoded.flags.map((flag) => flag.key)).toEqual([
      'missing',
      'out_of_range',
      'out_of_order/backfill',
    ])
    expect(decoded.unknownMask).toBe(0x80)
    expect(decoded.isNormal).toBe(false)
  })

  it('accepts decimal and hexadecimal API strings without coercing invalid data', () => {
    expect(parseQualityFlags('8')).toBe(8)
    expect(parseQualityFlags('0x20')).toBe(32)
    expect(parseQualityFlags('-1')).toBeNull()
    expect(parseQualityFlags('not-a-mask')).toBeNull()
  })
})
