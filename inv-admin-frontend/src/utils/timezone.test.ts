import { describe, it, expect } from 'vitest'
import { formatInTimezone, toUTCString, getTimezoneLabel, TIMEZONE_LIST } from './timezone'

describe('formatInTimezone', () => {
  it('should format UTC time in Shanghai timezone', () => {
    const result = formatInTimezone('2026-01-01T00:00:00Z', 'Asia/Shanghai')
    expect(result).toBe('2026-01-01 08:00:00')
  })

  it('should format UTC time in New York timezone', () => {
    const result = formatInTimezone('2026-07-01T12:00:00Z', 'America/New_York')
    expect(result).toBe('2026-07-01 08:00:00')
  })

  it('should return "-" for null/undefined input', () => {
    expect(formatInTimezone(null, 'Asia/Shanghai')).toBe('-')
    expect(formatInTimezone(undefined, 'Asia/Shanghai')).toBe('-')
  })

  it('should use custom format', () => {
    const result = formatInTimezone('2026-01-01T00:00:00Z', 'Asia/Shanghai', 'YYYY/MM/DD')
    expect(result).toBe('2026/01/01')
  })

  it('should default to Asia/Shanghai when timezone is null', () => {
    const result = formatInTimezone('2026-01-01T00:00:00Z', null)
    expect(result).toBe('2026-01-01 08:00:00')
  })
})

describe('getTimezoneLabel', () => {
  it('should return Chinese label for zh locale', () => {
    expect(getTimezoneLabel('Asia/Shanghai', 'zh')).toBe('UTC+8 上海')
  })

  it('should return English label for en locale', () => {
    expect(getTimezoneLabel('Asia/Shanghai', 'en')).toBe('UTC+8 Shanghai')
  })

  it('should default to zh locale', () => {
    expect(getTimezoneLabel('Asia/Shanghai')).toBe('UTC+8 上海')
  })

  it('should return timezone id for unknown timezone', () => {
    expect(getTimezoneLabel('Unknown/Zone')).toBe('Unknown/Zone')
  })
})

describe('TIMEZONE_LIST', () => {
  it('should contain common timezones', () => {
    const ids = TIMEZONE_LIST.map((t) => t.id)
    expect(ids).toContain('Asia/Shanghai')
    expect(ids).toContain('America/New_York')
    expect(ids).toContain('Europe/London')
    expect(ids).toContain('Asia/Tokyo')
  })

  it('should have offset for each timezone', () => {
    for (const tz of TIMEZONE_LIST) {
      expect(tz.offset).toMatch(/^[+-]\d{2}:\d{2}$/)
    }
  })

  it('should have both Chinese and English labels', () => {
    for (const tz of TIMEZONE_LIST) {
      expect(tz.labelZh).toBeTruthy()
      expect(tz.labelEn).toBeTruthy()
    }
  })
})
