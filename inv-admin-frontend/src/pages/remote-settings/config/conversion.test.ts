import { describe, expect, it } from 'vitest'
import { resolveFieldMeta } from './conversion'

describe('L10 Collector 枚举契约', () => {
  it.each([
    ['set_output_priority', 1, 'solar_first'],
    ['set_output_priority', 4, 'solar_utility_battery'],
    ['set_battery_type', 1, 'agm'],
    ['set_battery_type', 3, 'lithium'],
    ['set_battery_type', 4, 'user_lead_acid'],
    ['set_charge_priority', 1, 'solar_first'],
    ['set_charge_priority', 3, 'solar_only'],
    ['set_ac_volt_range', 1, 'appliance'],
    ['set_ac_volt_range', 3, 'generator'],
    ['set_ac_output_mode', 1, 'ac_single_phase'],
    ['set_ac_output_mode', 5, 'ac_three_phase_l3'],
  ])('%s 的协议值 %s 对应 %s', (key, value, semanticKey) => {
    const meta = resolveFieldMeta(new Map(), key)
    expect(meta.kind).toBe('enum')
    expect(meta.enumOptions?.find((o) => o.value === value)?.semanticKey).toBe(semanticKey)
  })

  it('最大总充电电流允许设备原厂140A配置', () => {
    expect(resolveFieldMeta(new Map(), 'set_max_charge_current').max).toBe(140)
  })
})
