/** Measured net grid power: positive import, negative export; null means unreported. */
export function measuredGridPower(rt: Record<string, any> | null | undefined): number | null {
  const read = (key: string, group?: string): number | null => {
    const section = group ? (rt?.[group]?.data ?? rt?.[group]) : undefined
    const value = rt?.[key] ?? section?.[key]
    return typeof value === 'number' && Number.isFinite(value) ? value : null
  }
  const meter = read('grid_power') ?? read('meter_power')
  if (meter != null) return meter
  const input = read('ac_input_power', 'ac')
  const charge = read('ac_charge_power', 'chr') ?? read('ac_charge_power', 'ac')
  return input == null && charge == null ? null : (input ?? 0) + (charge ?? 0)
}
