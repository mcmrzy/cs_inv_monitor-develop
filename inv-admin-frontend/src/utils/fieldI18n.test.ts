import { describe, expect, it } from 'vitest'
import { humanizeFieldKey, localizeFieldName } from './fieldI18n'

describe('fieldI18n', () => {
  it('keeps common device acronyms readable', () => {
    expect(humanizeFieldKey('pv1_voltage_max')).toBe('PV1 Voltage Max')
    expect(humanizeFieldKey('battery_soc')).toBe('Battery SOC')
    expect(humanizeFieldKey('bms_fault_code')).toBe('BMS Fault Code')
  })

  it('does not leak a Chinese backend label into English UI', () => {
    expect(localizeFieldName('ac_voltage', '输出电压', 'en')).toBe('AC Voltage')
    expect(localizeFieldName('ac_voltage', '输出电压', 'zh')).toBe('输出电压')
  })
})
