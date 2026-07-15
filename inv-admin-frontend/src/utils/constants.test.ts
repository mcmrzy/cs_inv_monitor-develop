import { describe, it, expect } from 'vitest'
import {
  parseFaultCode,
  getAlarmLevelDisplay,
  ROLE_MAP,
  DEVICE_STATUS_MAP,
  ALARM_LEVEL_MAP,
  ALARM_CODE_LEVEL,
  ALARM_CODE_MESSAGE,
  ROLE_COLORS,
} from './constants'

describe('parseFaultCode', () => {
  it('should parse decimal string', () => {
    expect(parseFaultCode('5')).toBe(5)
    expect(parseFaultCode('0')).toBe(0)
  })

  it('should parse hex string', () => {
    expect(parseFaultCode('0x0A')).toBe(10)
    expect(parseFaultCode('0X0F')).toBe(15)
  })

  it('should parse number directly', () => {
    expect(parseFaultCode(3)).toBe(3)
    expect(parseFaultCode(0)).toBe(0)
  })

  it('should return -1 for null/undefined', () => {
    expect(parseFaultCode(null)).toBe(-1)
    expect(parseFaultCode(undefined)).toBe(-1)
  })

  it('should return -1 for invalid strings', () => {
    expect(parseFaultCode('abc')).toBe(-1)
    expect(parseFaultCode('')).toBe(-1)
  })
})

describe('getAlarmLevelDisplay', () => {
  it('should use alarm code mapping when code is valid', () => {
    const display = getAlarmLevelDisplay(1, 0) // code 1 = level 3 (严重)
    expect(display.label).toBe('严重')
    expect(display.color).toBe('#ff4d4f')
  })

  it('should fall back to alarm_level when code is not in map', () => {
    const display = getAlarmLevelDisplay(99, 2) // code 99 not in map, use level 2
    expect(display.label).toBe('警告')
    expect(display.color).toBe('#fa8c16')
  })

  it('should handle string alarm level', () => {
    const display = getAlarmLevelDisplay(99, 'warning')
    expect(display.label).toBe('警告')
  })

  it('should handle null fault code', () => {
    const display = getAlarmLevelDisplay(null, 1)
    expect(display.label).toBe('提示')
  })

  it('should handle hex fault code', () => {
    const display = getAlarmLevelDisplay('0x06', 0) // 0x06 = 6 = level 2
    expect(display.label).toBe('警告')
  })
})

describe('Constants maps', () => {
  it('ROLE_MAP should cover the complete database role contract', () => {
    expect(ROLE_MAP['0']).toBe('超级管理员')
    expect(ROLE_MAP['1']).toBe('管理员')
    expect(ROLE_MAP['2']).toBe('运营商')
    expect(ROLE_MAP['3']).toBe('经销商')
    expect(ROLE_MAP['4']).toBe('安装商')
    expect(ROLE_MAP['5']).toBe('终端用户')
  })

  it('DEVICE_STATUS_MAP should cover numeric and string statuses', () => {
    expect(DEVICE_STATUS_MAP['0'].label).toBe('离线')
    expect(DEVICE_STATUS_MAP['1'].label).toBe('在线')
    expect(DEVICE_STATUS_MAP['2'].label).toBe('故障')
    expect(DEVICE_STATUS_MAP['online'].label).toBe('在线')
    expect(DEVICE_STATUS_MAP['offline'].label).toBe('离线')
    expect(DEVICE_STATUS_MAP['fault'].label).toBe('故障')
  })

  it('ALARM_LEVEL_MAP should have 3 numeric levels', () => {
    expect(ALARM_LEVEL_MAP['1'].label).toBe('提示')
    expect(ALARM_LEVEL_MAP['2'].label).toBe('警告')
    expect(ALARM_LEVEL_MAP['3'].label).toBe('严重')
  })

  it('ALARM_CODE_LEVEL should map known codes', () => {
    expect(ALARM_CODE_LEVEL[0]).toBe(1) // info
    expect(ALARM_CODE_LEVEL[1]).toBe(3) // fault
    expect(ALARM_CODE_LEVEL[6]).toBe(2) // warning
  })

  it('ALARM_CODE_MESSAGE should have descriptions', () => {
    expect(ALARM_CODE_MESSAGE[0]).toBe('故障恢复，系统正常')
    expect(ALARM_CODE_MESSAGE[1]).toBe('逆变器过温保护')
  })

  it('ROLE_COLORS should have one color for every database role', () => {
    expect(Object.keys(ROLE_COLORS)).toEqual(['0', '1', '2', '3', '4', '5'])
  })
})
