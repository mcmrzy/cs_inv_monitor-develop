/**
 * 设备详情 Tab 契约测试（第二轮审计修复回归）：
 *  - P0-1: DiagnosticsTab 自检/复位命令载荷使用 { command, params }（对齐 ControlRequest）
 *  - P0-2: InstallTab 电池配置 upsert 载荷包含 profile_id + capacity_ah（后端硬校验）
 *  - P1-1: BmsTab 功率 W→kW（/1000）、容量 Ah 直接展示（不再 /10）
 */
import { describe, it, expect, vi } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import DiagnosticsTab from './DiagnosticsTab'
import InstallTab from './InstallTab'
import BmsTab from './BmsTab'

vi.mock('@/lib/echarts', () => ({
  default: () => <div data-testid="echarts-mock">chart</div>,
}))

const API_BASE = '/api/v1'
const SN = 'INVCONTRACT01'

describe('DiagnosticsTab 命令契约（P0-1）', () => {
  it('自检命令载荷为 { command: "self_test", params: {} }', async () => {
    const bodies: Record<string, unknown>[] = []
    server.use(
      http.get(`${API_BASE}/devices/by-sn/${SN}/control-state`, () =>
        HttpResponse.json({
          code: 0, message: 'success',
          data: { sync_status: 'in_sync', desired: {}, reported: {} },
        })),
      http.get(`${API_BASE}/devices/by-sn/${SN}/commands`, () =>
        HttpResponse.json({ code: 0, message: 'success', data: { items: [], total: 0 } })),
      http.post(`${API_BASE}/devices/by-sn/${SN}/control`, async ({ request }) => {
        bodies.push(await request.json() as Record<string, unknown>)
        return HttpResponse.json({ code: 0, message: 'success', data: { task_id: 'task-1' } })
      }),
    )

    renderAsAdmin(<DiagnosticsTab sn={SN} />)

    const btn = await screen.findByRole('button', { name: /执行自检/ })
    await waitFor(() => expect(btn).not.toBeDisabled())
    fireEvent.click(btn)

    await waitFor(() => expect(bodies).toHaveLength(1))
    expect(bodies[0]).toEqual({ command: 'self_test', params: {} })
    expect(bodies[0].command_code).toBeUndefined()
    expect(bodies[0].args).toBeUndefined()
  })
})

describe('InstallTab 电池配置契约（P0-2）', () => {
  it('绑定电池配置载荷包含 profile_id 与 capacity_ah', async () => {
    const bodies: Record<string, unknown>[] = []
    server.use(
      http.get(`${API_BASE}/battery-profiles`, () =>
        HttpResponse.json({
          code: 0, message: 'success',
          data: [{
            id: 7, name: 'P48100', brand: 'TestBrand', nominal_voltage: 48,
            nominal_capacity: 100, chemistry: 'LiFePO4',
          }],
        })),
      http.get(`${API_BASE}/devices/by-sn/${SN}/battery-config`, () =>
        HttpResponse.json({ code: 0, message: 'success', data: {} })),
      http.put(`${API_BASE}/devices/by-sn/${SN}/battery-config`, async ({ request }) => {
        bodies.push(await request.json() as Record<string, unknown>)
        return HttpResponse.json({ code: 0, message: 'success', data: null })
      }),
    )

    renderAsAdmin(<InstallTab sn={SN} />)

    // 选择电池模板（选择后 capacity_ah 自动预填模板标称容量 100）
    await waitFor(() => {
      expect(document.querySelector('.ant-select')?.classList.contains('ant-select-disabled')).toBe(false)
    })
    fireEvent.mouseDown(document.querySelector('.ant-select-selector')!)
    fireEvent.click(await screen.findByText(/P48100/))

    fireEvent.click(await screen.findByRole('button', { name: /绑定电池配置/ }))

    await waitFor(() => expect(bodies).toHaveLength(1))
    expect(bodies[0].profile_id).toBe(7)
    expect(bodies[0].capacity_ah).toBe(100)
    expect((bodies[0] as Record<string, unknown>).installer_limits).toEqual(expect.any(Object))
  })
})

describe('BmsTab 单位换算（P1-1）', () => {
  it('充电功率 2200W 显示 2.20 kW，容量 100Ah 直接显示不再缩小', async () => {
    server.use(
      http.get(`${API_BASE}/devices/by-sn/${SN}/realtime`, () =>
        HttpResponse.json({
          code: 0, message: 'success',
          data: {
            online: true,
            data_time: new Date().toISOString(),
            realtime: {
              bat: {
                battery_charge_power: 2200, battery_discharge_power: 0,
                battery_soc: 80, battery_voltage: 51.2, battery_current: 43,
              },
              bms: {
                data: {
                  bms_online: 1, bms_soc: 80, bms_soh: 98,
                  bms_capacity_remain: 100, bms_capacity_full: 102.4, bms_capacity_design: 100,
                  bms_cycle_count: 12,
                  bms_cell_voltage_max: 3350, bms_cell_voltage_min: 3340, bms_cell_voltage_diff: 10,
                  bms_cell_temp_max: 30, bms_cell_temp_min: 28,
                  bms_mos_temp: 31, bms_env_temp: 25, bms_pcb_temp: 29,
                  bms_battery_work_mode: 1, bms_mos_status: 3,
                  bms_chg_request_current: 50, bms_chg_request_voltage: 58.4,
                  bms_fault_status: 0, bms_alarm_w0: 0, bms_alarm_w1: 0, bms_alarm_w2: 0,
                  bms_total_chg_capacity: 1234, bms_total_dsg_capacity: 1200,
                  bms_balance_bitmap: 0,
                },
              },
            },
          },
        })),
      http.get(`${API_BASE}/devices/by-sn/${SN}/telemetry`, () =>
        HttpResponse.json({ code: 0, message: 'success', data: { items: [], total: 0 } })),
    )

    renderAsAdmin(<BmsTab sn={SN} />)

    // 功率：2200W → /1000 → 2.20 kW（旧错误实现为 /10 → 220.00 kW）
    expect(await screen.findByText('2.20 kW')).toBeInTheDocument()
    // 容量：后端已是 Ah，直接展示（旧错误实现为 /10 → 10.0 Ah）
    expect(await screen.findByText('100.0 Ah')).toBeInTheDocument()
    expect(screen.getByText('102.4 Ah (FCC)')).toBeInTheDocument()
  })
})
