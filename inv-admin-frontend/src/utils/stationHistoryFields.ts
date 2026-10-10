import type { ModelFieldCapability } from '@/services/modelApi'

export const BMS_HISTORY_FIELDS: Record<string, { labelKey: string; unit: string }> = Object.fromEntries([
  ['soc', 'soc', '%'], ['soh', 'soh', '%'], ['voltage', 'voltage', 'V'], ['current', 'current', 'A'],
  ['capacity_remain', 'capacity_remain', 'Ah'], ['capacity_full', 'capacity_full', 'Ah'], ['capacity_design', 'capacity_design', 'Ah'],
  ['cycle_count', 'cycle_count', ''], ['temp_max', 'max_cell_temp', '°C'], ['temp_min', 'min_cell_temp', '°C'],
  ['mos_temp', 'mos_temp', '°C'], ['pcb_temp', 'pcb_temp', '°C'], ['env_temp', 'env_temp', '°C'],
  ['cell_voltage_max', 'max_cell_voltage', 'mV'], ['cell_voltage_min', 'min_cell_voltage', 'mV'],
  ['charging_voltage', 'charging_voltage', 'V'], ['charge_request_current', 'chg_request_current', 'A'],
  ['charge_request_voltage', 'chg_request_voltage', 'V'], ['total_charge_capacity', 'total_chg_capacity', 'Ah'],
  ['total_discharge_capacity', 'total_dsg_capacity', 'Ah'],
].map(([key, field, unit]) => [`bms_${key}`, { labelKey: `deviceDetail.summary.field.${field}`, unit }]))

export const HISTORY_GROUPS = [
  { id: 'pv', labelKey: 'station.pvParams' },
  { id: 'bat', labelKey: 'station.batteryParams' },
  { id: 'ac', labelKey: 'station.acParams' },
  { id: 'sys', labelKey: 'station.systemStatus' },
  { id: 'eng', labelKey: 'station.energyStats' },
  { id: 'other', labelKey: 'mon.other' },
] as const

export function historyFieldGroup(key: string, capability?: ModelFieldCapability): string {
  const code = capability?.group_code?.toLowerCase()
  if (['pv', 'mppt'].includes(code ?? '')) return 'pv'
  if (['bat', 'battery', 'bms', 'cell', 'cells'].includes(code ?? '')) return 'bat'
  if (['ac', 'grid', 'load'].includes(code ?? '')) return 'ac'
  if (['sys', 'diag', 'system', 'fan', 'sock'].includes(code ?? '')) return 'sys'
  if (['eng', 'energy'].includes(code ?? '')) return 'eng'
  if (/(energy|^daily_|^total_(pv|charge|discharge|load)$|^gen_)/i.test(key)) return 'eng'
  if (/^(pv|mppt)/i.test(key)) return 'pv'
  if (/^(batt|bat|bms|cell|soc|soh|overcharge|capacity_|cycle_count|protection_flag|balance|(?:max|min)_cell|max_(charge|discharge)_current|charge_(request|voltage)|discharge_cutoff)/i.test(key)) return 'bat'
  if (/^(ac|grid|meter|load|output|feed|bypass)/i.test(key)) return 'ac'
  if (/^(work_|inv|fan_|temp_|effic|runtime|fault|alarm|sys|boost|transform|buck|paired|online_socket|on_socket|dc_bus|mos_|ambient|parallel_charge)/i.test(key)) return 'sys'
  return 'other'
}

export function formatHistoryValue(value: unknown, capability?: ModelFieldCapability): string {
  if (value == null || value === '') return '--'
  if (typeof value === 'boolean') return value ? '1' : '0'
  if (typeof value === 'object') {
    const snapshot = value as Record<string, unknown>
    if (snapshot.layout !== 0 || snapshot.bms_online !== 1) return '--'
    return [typeof snapshot.soc === 'number' && Number.isFinite(snapshot.soc) ? `SOC ${snapshot.soc}%` : null,
      typeof snapshot.voltage === 'number' && Number.isFinite(snapshot.voltage) ? `${snapshot.voltage} V` : null].filter(Boolean).join(' · ') || '--'
  }
  const number = Number(value)
  if (!Number.isFinite(number)) return String(value)
  if (capability?.field_type === 'bitmask') return `0x${number.toString(16).toUpperCase()}`
  const decimals = capability?.decimal_places ?? (Number.isInteger(number) ? 0 : 2)
  return number.toFixed(Math.min(6, Math.max(0, decimals)))
}
