import { describe, expect, it } from 'vitest'
import { measuredGridPower } from './gridPower'

describe('measuredGridPower', () => {
  it('includes AC supply to the load and battery', () => {
    expect(measuredGridPower({ ac_input_power: 1200, ac_charge_power: 600 })).toBe(1800)
    expect(measuredGridPower({ ac: { data: { ac_input_power: 1200 } }, chr: { data: { ac_charge_power: 600 } } })).toBe(1800)
  })
  it('preserves measured zero and signed meter power', () => {
    expect(measuredGridPower({ grid_power: 0, ac_input_power: 900 })).toBe(0)
    expect(measuredGridPower({ meter_power: -500 })).toBe(-500)
  })
  it('keeps missing data unknown and never substitutes output or apparent power', () => {
    expect(measuredGridPower({ ac_power: 2000, ac_input_apparent_power: 2200 })).toBeNull()
    expect(measuredGridPower({ grid_power: NaN, ac_charge_power: 300 })).toBe(300)
  })
})
