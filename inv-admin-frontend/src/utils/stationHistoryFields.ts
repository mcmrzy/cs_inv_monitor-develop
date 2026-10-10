import type { ModelFieldCapability } from '@/services/modelApi'

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
  if (typeof value === 'object') return '--'
  const number = Number(value)
  if (!Number.isFinite(number)) return String(value)
  if (capability?.field_type === 'bitmask') return `0x${number.toString(16).toUpperCase()}`
  const decimals = capability?.decimal_places ?? (Number.isInteger(number) ? 0 : 2)
  return number.toFixed(Math.min(6, Math.max(0, decimals)))
}
