export const SUMMARY_FIELDS = [
  'layout', 'bms_online', 'age_ms', 'reported_at', 'expires_at', 'updated_at',
  'battery_count', 'voltage', 'current', 'soc', 'soh', 'soc_raw', 'soh_raw',
  'capacity_remain', 'capacity_full', 'capacity_design', 'warning_flag',
  'protection_flag', 'status_fault_flag', 'balance_status', 'cell_voltages',
  'cell_temperatures', 'cycle_count', 'max_cell_voltage', 'min_cell_voltage',
  'max_cell_temp', 'min_cell_temp', 'mos_temp', 'pcb_temp', 'env_temp',
  'battery_mode', 'battery_status', 'total_chg_capacity_raw', 'total_dsg_capacity_raw',
  'chg_request_current_raw', 'chg_request_voltage_raw', 'system_mode',
  'charging_voltage', 'raw_bytes',
] as const

type SummaryField = typeof SUMMARY_FIELDS[number]
export type SummaryValues = Partial<Record<SummaryField, unknown>>
export interface BmsSummary {
  values: SummaryValues
  cells: (number | null)[]
  rawBytes: number[] | null
}
export type BmsAvailability = 'live' | 'offline' | 'expired' | 'unknown'
export const summaryNumber = (value: unknown): number | null =>
  typeof value === 'number' && Number.isFinite(value) ? value : null
export const summaryWord = (value: unknown): number | null => {
  const n = summaryNumber(value)
  return n !== null && Number.isInteger(n) && n >= 0 && n <= 0xffff ? n : null
}

export function parseBmsSummary(realtime: Record<string, unknown> | null | undefined): BmsSummary | null {
  const raw = realtime?.bms_summary
  if (raw == null) return null
  const object = (value: unknown): Record<string, unknown> =>
    value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {}
  const outer = object(raw)
  const source = 'data' in outer ? object(outer.data) : outer
  const values = Object.fromEntries(SUMMARY_FIELDS.map(key => [key, source[key] ?? null])) as SummaryValues
  const incoming = Array.isArray(values.cell_voltages) ? values.cell_voltages : []
  const cells = Array.from({ length: 16 }, (_, i) => {
    const n = summaryNumber(incoming[i])
    return n !== null && Number.isInteger(n) && n > 0 && n <= 0xffff ? n : null
  })
  const bytes = values.raw_bytes
  const rawBytes = Array.isArray(bytes) && bytes.length === 100 && bytes.every(n =>
    typeof n === 'number' && Number.isInteger(n) && n >= 0 && n <= 255) ? bytes as number[] : null
  return { values, cells, rawBytes }
}

export function summaryTimestamp(value: unknown): number | null {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) return null
  const [year, month, day, hour, minute, second] = value.slice(0, 19).split(/[-T:]/).map(Number)
  const calendar = new Date(Date.UTC(year, month - 1, day))
  if (calendar.getUTCFullYear() !== year || calendar.getUTCMonth() !== month - 1 || calendar.getUTCDate() !== day || hour > 23 || minute > 59 || second > 59) return null
  const n = Date.parse(value)
  return Number.isFinite(n) ? n : null
}

// BMS freshness is independent of the inverter's data_time/online envelope.
export function bmsAvailability(summary: BmsSummary, now = Date.now()): BmsAvailability {
  const v = summary.values
  if (v.layout !== 0) return 'unknown'
  const expiry = summaryTimestamp(v.expires_at)
  if (expiry === null || expiry > now + 215_000) return 'unknown'
  if (expiry <= now) return 'expired'
  const count = summaryWord(v.battery_count), soc = summaryWord(v.soc_raw), age = summaryNumber(v.age_ms)
  if (v.bms_online === 0 || count === 0 || soc === 255 || (age !== null && age > 120_000)) return 'offline'
  if (v.bms_online !== 1 || count === null || count > 255 || soc === null || age === null || !Number.isInteger(age) || age < 0) return 'unknown'
  return 'live'
}

export function cellExtrema(cells: (number | null)[]) {
  const valid = cells.filter((v): v is number => v !== null)
  const max = valid.length ? Math.max(...valid) : null
  const min = valid.length ? Math.min(...valid) : null
  return { count: valid.length, max, min, spread: max !== null && min !== null ? max - min : null,
    maxIndex: max !== null ? cells.indexOf(max) : null, minIndex: min !== null ? cells.indexOf(min) : null }
}

const warningBits: Record<number, string> = {
  0: 'cellOv', 1: 'cellUv', 2: 'packOv', 3: 'packUv', 4: 'chgOc', 5: 'dsgOc',
  8: 'chgOt', 9: 'dsgOt', 10: 'chgUt', 11: 'dsgUt', 12: 'envOt', 13: 'envUt', 14: 'mosOt', 15: 'socLow',
}
const protectionBits: Record<number, string> = {
  0: 'cellOv', 1: 'cellUv', 2: 'packOv', 3: 'packUv', 4: 'chgOc', 5: 'dsgOc',
  6: 'sc', 7: 'chargerOv', 8: 'chgOt', 9: 'dsgOt', 10: 'chgUt', 11: 'dsgUt',
  12: 'mosOt', 13: 'envOt', 14: 'envUt',
}
const faultBits: Record<number, string> = { 0: 'chgMosFault', 1: 'dsgMosFault', 2: 'ntcBreak', 4: 'cellFault', 5: 'afeComm' }
const operationBits: Record<number, string> = {
  8: 'charging', 9: 'discharging', 10: 'chargeMosOn', 11: 'dischargeMosOn',
  12: 'chargeLimiter', 14: 'chargeReversed', 15: 'heater',
}
export interface SummaryFlag { bit: number; key: string }
function decode(word: unknown, definitions: Record<number, string>, ignore: Record<number, string> = {}) {
  const value = summaryWord(word)
  const active: SummaryFlag[] = [], reserved: number[] = []
  if (value !== null) for (let bit = 0; bit < 16; bit++) {
    if (!(value & (1 << bit))) continue
    if (definitions[bit]) active.push({ bit, key: definitions[bit] })
    else if (!ignore[bit]) reserved.push(bit)
  }
  return { value, active, reserved, known: value !== null && reserved.length === 0 }
}
export function summaryFlags(summary: BmsSummary) {
  const v = summary.values
  const warning = decode(v.warning_flag, warningBits)
  const protection = decode(v.protection_flag, protectionBits)
  const fault = decode(v.status_fault_flag, faultBits, operationBits)
  const operations = decode(v.status_fault_flag, operationBits, faultBits)
  const activeCount = warning.active.length + protection.active.length + fault.active.length
  return { warning, protection, fault, operations, activeCount,
    allKnown: warning.known && protection.known && fault.known }
}
