import { act, cleanup, render, waitFor } from '@testing-library/react'
import { QueryClientProvider } from '@tanstack/react-query'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createTestQueryClient } from '@/test/test-utils'
import { useDeviceConfig } from './useDeviceConfig'

const mocks = vi.hoisted(() => ({
  success: vi.fn(), info: vi.fn(), error: vi.fn(), warning: vi.fn(),
  sendCommand: vi.fn(), getControlState: vi.fn(),
}))
vi.mock('antd', () => ({ App: { useApp: () => ({ message: mocks, modal: {} }) } }))
vi.mock('@/hooks/useTranslation', () => ({ default: () => ({ t: (key: string) => key }) }))
vi.mock('@/services/deviceApi', () => ({ deviceApi: {
  getConfigSchema: async () => ({ data: { data: [] } }),
  getControlCapabilities: async () => ({ data: { data: [] } }),
  getCommands: async () => ({ data: { data: { items: [] } } }),
  getControlState: mocks.getControlState, sendCommand: mocks.sendCommand,
} }))

let cfg: ReturnType<typeof useDeviceConfig>
let state: Record<string, unknown>
function Harness({ sn = 'test-sn' }: { sn?: string }) {
  cfg = useDeviceConfig(sn)
  return null
}
async function setup() {
  const client = createTestQueryClient()
  const view = render(<QueryClientProvider client={client}><Harness /></QueryClientProvider>)
  await waitFor(() => expect(cfg.stateLoading).toBe(false))
  return view
}

beforeEach(() => {
  vi.clearAllMocks()
  state = {
    reported: { set_output_priority: 1 }, desired: { set_output_priority: 0, set_buzzer: 1 },
    reported_at: '2026-10-20T01:00:00Z', reported_revision: 10,
  }
  mocks.getControlState.mockImplementation(async () => ({ data: { data: state } }))
  mocks.sendCommand.mockResolvedValue({ data: { data: { task_id: 'read-1' } } })
})
afterEach(() => { cleanup(); vi.useRealTimers() })

describe('设备实际参数与读取闭环', () => {
  it('设备回报值覆盖历史下发值，未回报字段保持未知', async () => {
    await setup()
    expect(cfg.getEditValue('set_output_priority')).toBe(1)
    expect(cfg.getSummaryValue('set_output_priority')).toBe(1)
    expect(cfg.getEditValue('set_buzzer')).toBeUndefined()
    expect(cfg.getSummaryValue('set_buzzer')).toBeUndefined()
    expect(cfg.isSynced('set_output_priority')).toBe('pending')
  })

  it('指令发出后继续等待，新回报即使版本不变也完成读取', async () => {
    await setup()
    vi.useFakeTimers()
    await act(async () => { await cfg.readCurrent() })
    expect(cfg.reading).toBe(true)
    expect(mocks.success).not.toHaveBeenCalled()
    await act(async () => { await vi.advanceTimersByTimeAsync(1_001) })
    expect(cfg.reading).toBe(true)
    state = { ...state, reported_at: '2026-10-20T01:00:01Z', reported: { set_output_priority: 2 } }
    await act(async () => { await vi.advanceTimersByTimeAsync(1_001) })
    expect(cfg.reading).toBe(false)
    expect(cfg.getEditValue('set_output_priority')).toBe(2)
    expect(mocks.success).toHaveBeenCalledWith('remote.readSuccess')
  })

  it('旧回报或仅下发意图更新不能完成读取，30秒后提示超时', async () => {
    await setup()
    vi.useFakeTimers()
    await act(async () => { await cfg.readCurrent() })
    state = { ...state, updated_at: '2026-10-20T01:01:00Z', desired: { set_output_priority: 2 } }
    await act(async () => { await vi.advanceTimersByTimeAsync(30_000) })
    expect(cfg.reading).toBe(false)
    expect(mocks.success).not.toHaveBeenCalled()
    expect(mocks.warning).toHaveBeenCalledWith('remote.readTimeout')
  })

  it('命令下发失败时结束读取并显示错误', async () => {
    await setup()
    mocks.sendCommand.mockRejectedValueOnce(new Error('offline'))
    await act(async () => { await cfg.readCurrent() })
    expect(cfg.reading).toBe(false)
    expect(mocks.error).toHaveBeenCalledWith('remote.commandSendFailed: offline')
    expect(mocks.success).not.toHaveBeenCalled()
  })

  it('空配置回报不会把本次读取标记为成功', async () => {
    await setup()
    vi.useFakeTimers()
    await act(async () => { await cfg.readCurrent() })
    state = { ...state, reported_at: '2026-10-20T01:00:01Z', reported: {} }
    await act(async () => { await vi.advanceTimersByTimeAsync(1_001) })
    expect(cfg.reading).toBe(true)
    expect(mocks.success).not.toHaveBeenCalled()
  })

  it('重复点击只下发一次读取命令', async () => {
    await setup()
    await act(async () => { await Promise.all([cfg.readCurrent(), cfg.readCurrent()]) })
    expect(mocks.sendCommand).toHaveBeenCalledTimes(1)
    expect(mocks.sendCommand).toHaveBeenCalledWith('test-sn', { command: 'query_config', params: {} })
  })

  it('离开设备工作区后忽略尚未完成的查询响应', async () => {
    const view = await setup()
    let finish!: () => void
    mocks.sendCommand.mockImplementationOnce(() => new Promise<void>((resolve) => { finish = resolve }))
    let read!: Promise<void>
    await act(async () => { read = cfg.readCurrent(); await Promise.resolve() })
    await waitFor(() => expect(mocks.sendCommand).toHaveBeenCalledTimes(1))
    view.unmount()
    await act(async () => { finish(); await read })
    expect(mocks.success).not.toHaveBeenCalled()
    expect(mocks.warning).not.toHaveBeenCalled()
  })
})
