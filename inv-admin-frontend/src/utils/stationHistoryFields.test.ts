import { describe, expect, it } from 'vitest'
import type { ModelFieldCapability } from '@/services/modelApi'
import { formatHistoryValue, historyFieldGroup } from './stationHistoryFields'

describe('history field presentation', () => {
  it('keeps missing readings distinct from zero and preserves state values', () => {
    expect(formatHistoryValue(null)).toBe('--')
    expect(formatHistoryValue(0)).toBe('0')
    expect(formatHistoryValue('charging')).toBe('charging')
    expect(formatHistoryValue('not_available')).toBe('not_available')
    expect(formatHistoryValue(230.456, { decimal_places: 1 } as ModelFieldCapability)).toBe('230.5')
    expect(formatHistoryValue(8, { field_type: 'bitmask' } as ModelFieldCapability)).toBe('0x8')
  })

  it('uses model groups and separates energy counters from instantaneous power', () => {
    expect(historyFieldGroup('ac_charge_energy_daily')).toBe('eng')
    expect(historyFieldGroup('battery_power')).toBe('bat')
    expect(historyFieldGroup('dc_bus_voltage')).toBe('sys')
    expect(historyFieldGroup('charge_request_current_x10')).toBe('bat')
    expect(historyFieldGroup('max_charge_current')).toBe('bat')
    expect(historyFieldGroup('max_discharge_current')).toBe('bat')
    expect(historyFieldGroup('custom_cell', { group_code: 'bms' } as ModelFieldCapability)).toBe('bat')
  })
})
