import type { CommandRecord } from './types'

export interface ControlCapability {
  command_code: string
  is_enabled: boolean
  permission_code?: string
}

export function getAcOutputState(realtime: Record<string, unknown> | null): boolean | undefined {
  if (!realtime) return
  const explicit = realtime.ac_output_on ?? realtime.ac_on
  if (typeof explicit === 'boolean') return explicit
  const ac = realtime.ac as Record<string, unknown> | undefined
  const voltage = [ac?.ac_output_voltage, realtime.ac_output_voltage, realtime.ac_voltage, ac?.voltage, realtime.output_voltage]
    .find((value): value is number => typeof value === 'number' && Number.isFinite(value) && value >= 0)
  if (voltage !== undefined) return voltage > 0
  const power = ac?.output_power ?? realtime.output_power
  if (typeof power === 'number' && Number.isFinite(power) && power > 0) return true
}

export function canUseCapability(
  capability: ControlCapability | undefined,
  hasPermission: (code: string) => boolean,
  schemaPermission?: string,
) {
  return capability?.is_enabled === true && hasPermission('devices:control') &&
    (!capability.permission_code || hasPermission(capability.permission_code)) &&
    (!schemaPermission || hasPermission(schemaPermission))
}

interface DeviceDetail {
  sn?: string
  model?: string
  reported_model?: string
  device_type?: string
  status?: number | string
}

export function getDeviceControlContext(data: (DeviceDetail & {
  device?: DeviceDetail
  online_status?: { online?: boolean }
}) | null | undefined, sn: string) {
  const device = data?.device ?? data
  if (device?.sn !== sn) return null
  const reported = device.reported_model?.trim().toUpperCase()
  const assigned = device.model?.trim().toUpperCase()
  const modelMismatch = Boolean(reported && assigned &&
    ['PWR2KH12H1', '3KU', '6KU', '12KU'].includes(reported) && reported !== assigned)
  const online = data?.online_status?.online ?? (device.status === 1 || device.status === 2 || device.status === 'online')
  return { online, modelMismatch, label: device.model || device.device_type }
}

export function getTaskId(data: { task_id?: unknown } | undefined): string | undefined {
  const id = data?.task_id
  if (typeof id === 'number' && Number.isFinite(id)) return String(id)
  if (typeof id === 'string' && id.trim()) return id
}

export function commandErrorDetail(error: unknown): string {
  const err = error as { response?: { data?: { reject_detail?: string; message?: string } }; message?: string } | undefined
  return err?.response?.data?.reject_detail || err?.response?.data?.message || err?.message || ''
}

export function commandReadback(record: CommandRecord | undefined, power = false) {
  const stage = record?.data?.stage ?? record?.response_data?.stage ?? record?.stage
  if (['failed', 'cancelled', 'timeout'].includes(record?.status ?? '') || record?.success === false) return 'failed'
  if (record?.status === 'submitted' || stage === 'submitted') return 'submitted'
  if ((record?.status === 'success' || record?.status === 'applied') &&
      (stage === 'applied' || (power && stage === 'completed'))) return 'applied'
  return 'pending'
}
