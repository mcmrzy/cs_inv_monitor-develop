import { afterEach, describe, expect, it, vi } from 'vitest'
import { deviceApi } from '@/services/deviceApi'
import { AxiosHeaders } from 'axios'
import { commonBatchFields, executeDeviceSettings, type BatchTarget } from './remoteBatch'

vi.mock('@/services/deviceApi', () => ({ deviceApi: {
  sendCommand: vi.fn(), getCommands: vi.fn(), getControlState: vi.fn(),
} }))

const field = {
  param_key: 'set_modbus_power_saving', group_code: 'general', sub_group: '',
  control_type: 'boolean' as const, unit: '', scale: 1, display_name_key: '', sort_order: 1,
}
const target: BatchTarget = {
  online: true, modelMismatch: false, schema: [field], reported: {},
  capabilities: [{ command_code: field.param_key, is_enabled: true }],
}
const response = (data: unknown) => ({ data: { data }, status: 200, statusText: 'OK', headers: {}, config: { headers: new AxiosHeaders() } })

afterEach(() => vi.resetAllMocks())

describe('batch remote configuration', () => {
  it('offers only fields enabled, visible and authorized for every selected device', () => {
    const allowed = (code: string) => code === 'devices:control'
    expect(commonBatchFields([target, { ...target }], allowed)).toEqual([field])
    for (const changed of [
      { ...target, online: false },
      { ...target, modelMismatch: true },
      { ...target, capabilities: [{ ...target.capabilities[0], is_enabled: false }] },
      { ...target, capabilities: [{ ...target.capabilities[0], permission_code: 'device:system' }] },
      { ...target, schema: [{ ...field, visibility: { param: 'mode', eq: 1 } }], reported: { mode: 0 } },
    ]) {
      expect(commonBatchFields([target, changed], allowed)).toEqual([])
    }
  })

  it('tracks each task ID and stops the remaining writes when readback is unconfirmed', async () => {
    vi.mocked(deviceApi.sendCommand).mockResolvedValueOnce(response({ task_id: 'first' }))
    vi.mocked(deviceApi.sendCommand).mockResolvedValueOnce(response({ task_id: 'second' }))
    vi.mocked(deviceApi.getCommands).mockResolvedValueOnce(response({ items: [
      { task_id: 'first', status: 'success', data: { stage: 'applied' } },
    ] }))
    vi.mocked(deviceApi.getCommands).mockResolvedValueOnce(response({ items: [
      { task_id: 'first', status: 'success', data: { stage: 'applied' } },
      { task_id: 'second', status: 'submitted', result_message: 'stored' },
    ] }))
    vi.mocked(deviceApi.getControlState).mockResolvedValue(response({ reported: { first_param: 1 } }))

    const result = await executeDeviceSettings('SN / 3', { first_param: true, second_param: 2, third_param: 3 }, new AbortController().signal)
    expect(vi.mocked(deviceApi.sendCommand).mock.calls).toEqual([
      ['SN%20%2F%203', { command: 'first_param', params: { value: true } }],
      ['SN%20%2F%203', { command: 'second_param', params: { value: 2 } }],
    ])
    expect(result).toMatchObject({ status: 'incomplete', tasks: [
      { key: 'first_param', taskId: 'first', state: 'applied', reported: 1 },
      { key: 'second_param', taskId: 'second', state: 'submitted', message: 'stored' },
      { key: 'third_param', state: 'not_sent' },
    ] })
  })
})
