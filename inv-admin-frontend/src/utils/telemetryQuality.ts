export interface TelemetryQualityFlag {
  mask: number
  key: string
  label: string
}

// Keep this mapping aligned with inv_device_server/internal/telemetry/model.go.
// OUT_OF_ORDER is also the storage layer's compatibility marker for backfill.
export const TELEMETRY_QUALITY_FLAGS: readonly TelemetryQualityFlag[] = [
  { mask: 0x01, key: 'missing', label: '缺失值 (missing)' },
  { mask: 0x02, key: 'out_of_range', label: '数值越界 (out_of_range)' },
  { mask: 0x04, key: 'time_drift', label: '设备时钟异常 (time_drift)' },
  { mask: 0x08, key: 'out_of_order/backfill', label: '乱序/回填 (out_of_order/backfill)' },
  { mask: 0x10, key: 'counter_reset', label: '累计量复位 (counter_reset)' },
  { mask: 0x20, key: 'comm_fault', label: '通信异常 (comm_fault)' },
]

export interface DecodedTelemetryQuality {
  value: number | null
  flags: TelemetryQualityFlag[]
  unknownMask: number
  isNormal: boolean | null
}

export function parseQualityFlags(input: unknown): number | null {
  if (typeof input === 'number') {
    return Number.isInteger(input) && input >= 0 ? input : null
  }
  if (typeof input !== 'string' || input.trim() === '') return null
  const text = input.trim()
  if (!/^(?:0x[0-9a-f]+|\d+)$/i.test(text)) return null
  const parsed = Number.parseInt(text, text.toLowerCase().startsWith('0x') ? 16 : 10)
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : null
}

export function decodeTelemetryQuality(input: unknown): DecodedTelemetryQuality {
  const value = parseQualityFlags(input)
  if (value === null) {
    return { value: null, flags: [], unknownMask: 0, isNormal: null }
  }
  const knownMask = TELEMETRY_QUALITY_FLAGS.reduce((mask, flag) => mask | flag.mask, 0)
  return {
    value,
    flags: TELEMETRY_QUALITY_FLAGS.filter((flag) => (value & flag.mask) !== 0),
    unknownMask: value & ~knownMask,
    isNormal: value === 0,
  }
}

