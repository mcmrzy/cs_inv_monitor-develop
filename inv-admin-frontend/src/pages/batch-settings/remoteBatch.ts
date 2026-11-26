import { deviceApi } from '@/services/deviceApi'
import type { ConfigSchemaItem } from '../remote-settings/config/fields'
import { canUseCapability, commandErrorDetail, commandReadback, getDeviceControlContext, getTaskId, type ControlCapability } from '../remote-settings/controlContract'
import type { CommandRecord, ControlState } from '../remote-settings/types'

export interface BatchTarget {
  online: boolean
  modelMismatch: boolean
  schema: ConfigSchemaItem[]
  capabilities: ControlCapability[]
  reported: Record<string, unknown>
}

export type SettingValue = number | boolean
export type BatchTask = {
  key: string
  taskId?: string
  state: 'applied' | 'submitted' | 'failed' | 'timeout' | 'unknown' | 'not_sent'
  message?: string
  reported?: unknown
}
export type DeviceBatchResult = { sn: string; status: 'applied' | 'failed' | 'incomplete'; tasks: BatchTask[] }

export async function loadBatchTarget(sn: string): Promise<BatchTarget> {
  const apiSn = encodeURIComponent(sn)
  const [detail, schema, capabilities, controlState] = await Promise.all([
    deviceApi.getDeviceBySn(apiSn), deviceApi.getConfigSchema(apiSn),
    deviceApi.getControlCapabilities(apiSn), deviceApi.getControlState(apiSn),
  ])
  const context = getDeviceControlContext(detail.data?.data, sn)
  if (!context) throw new Error('Device details did not match the requested SN')
  return {
    ...context,
    schema: schema.data.data,
    capabilities: capabilities.data.data,
    reported: controlState.data.data?.reported ?? {},
  }
}

function visible(item: ConfigSchemaItem, reported: BatchTarget['reported']) {
  const rule = item.visibility
  if (!rule?.param) return true
  const raw = reported[rule.param]
  if (raw == null || raw === '') return false
  const value = Number(raw)
  if (!Number.isFinite(value)) return false
  if (rule.in) return rule.in.includes(value)
  if (rule.eq !== undefined) return value === rule.eq
  if (rule.ne !== undefined) return value !== rule.ne
  return true
}

export function commonBatchFields(targets: BatchTarget[], hasPermission: (code: string) => boolean) {
  if (!targets.length || targets.some((target) => !target.online || target.modelMismatch)) return []
  const fieldsByTarget = targets.map((target) => {
    const caps = new Map(target.capabilities.map((cap) => [cap.command_code, cap]))
    return new Map(target.schema.filter((item) =>
      canUseCapability(caps.get(item.param_key), hasPermission, item.permission_code) && visible(item, target.reported),
    ).map((item) => [item.param_key, item]))
  })
  return [...fieldsByTarget[0].values()].flatMap((field) => {
    const matches = fieldsByTarget.map((fields) => fields.get(field.param_key))
    if (!matches.every((match) => match && match.control_type === field.control_type && match.unit === field.unit)) return []
    if (field.control_type === 'enum') {
      const enumMap = Object.fromEntries(Object.entries(field.enum_map ?? {}).filter(([value, label]) =>
        Number.isFinite(Number(value)) && matches.every((match) => match?.enum_map?.[value] === label),
      ))
      return Object.keys(enumMap).length ? [{ ...field, enum_map: enumMap }] : []
    }
    if (field.control_type === 'boolean') return [field]
    // The same engineering-unit value must be valid on all devices.
    const min = Math.max(...matches.map((match) => match?.min ?? -Infinity))
    const max = Math.min(...matches.map((match) => match?.max ?? Infinity))
    if (min > max || matches.some((match) => match?.step !== field.step)) return []
    return [{ ...field, min: Number.isFinite(min) ? min : null, max: Number.isFinite(max) ? max : null }]
  })
}

export function isBatchValueValid(field: ConfigSchemaItem, value: SettingValue | undefined) {
  if (field.control_type === 'boolean') return typeof value === 'boolean'
  if (typeof value !== 'number' || !Number.isFinite(value)) return false
  if (field.control_type === 'enum') return Object.prototype.hasOwnProperty.call(field.enum_map ?? {}, String(value))
  return value >= (field.min ?? -Infinity) && value <= (field.max ?? Infinity)
}

export async function executeDeviceSettings(sn: string, changes: Record<string, SettingValue>, signal: AbortSignal): Promise<DeviceBatchResult> {
  const apiSn = encodeURIComponent(sn)
  const tasks: BatchTask[] = []
  for (const [key, value] of Object.entries(changes)) {
    if (signal.aborted || tasks.some((task) => task.state !== 'applied')) {
      tasks.push({ key, state: 'not_sent' })
      continue
    }

    const task: BatchTask = { key, state: 'unknown' }
    tasks.push(task)
    try {
      const response = await deviceApi.sendCommand(apiSn, { command: key, params: { value } })
      task.taskId = getTaskId(response.data?.data)
    } catch (error) {
      const response = (error as { response?: { status?: number; data?: { code?: number } } } | undefined)?.response
      const status = response?.status === 200 ? response.data?.code : response?.status
      task.state = typeof status === 'number' && status >= 400 && status < 500 ? 'failed' : 'unknown'
      task.message = commandErrorDetail(error)
    }
    if (!task.taskId) continue

    const deadline = Date.now() + 35_000
    while (!signal.aborted && Date.now() < deadline) {
      try {
        const response = await deviceApi.getCommands(apiSn, { page: 1, page_size: 100 })
        const record = (response.data?.data?.items as CommandRecord[] | undefined)?.find((item) => String(item.task_id) === task.taskId)
        const outcome = commandReadback(record)
        if (outcome !== 'pending') {
          task.state = outcome
          task.message = record?.result_message
          break
        }
      } catch (error) {
        task.message = commandErrorDetail(error)
      }
      if (!signal.aborted) await new Promise((resolve) => setTimeout(resolve, 1_000))
    }
    if (task.state === 'unknown' && !signal.aborted) task.state = 'timeout'
  }

  if (!signal.aborted && tasks.some((task) => task.taskId)) {
    const response = await deviceApi.getControlState(apiSn).catch(() => undefined)
    const state: ControlState | undefined = response?.data?.data
    for (const task of tasks) task.reported = state?.reported?.[task.key]
  }
  const status = tasks.every((task) => task.state === 'applied') ? 'applied'
    : tasks.some((task) => ['applied', 'submitted', 'timeout', 'unknown'].includes(task.state)) ? 'incomplete' : 'failed'
  return { sn, status, tasks }
}
