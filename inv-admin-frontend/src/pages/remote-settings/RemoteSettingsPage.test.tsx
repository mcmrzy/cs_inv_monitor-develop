import { fireEvent, screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { describe, expect, it } from 'vitest'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import RemoteSettingsPage from './index'

const sn = 'PANEL-3KU-01'
const prefix = `/api/v1/devices/by-sn/${sn}`
const ok = (data: unknown) => HttpResponse.json({ code: 0, data })
const cases = [
  { name: 'device detail link', path: `/remote-settings?sn=${sn}` },
  { name: 'menu selection', path: '/remote-settings' },
]

describe.each(cases)('remote settings from $name', ({ path }) => {
  it('requests a new configuration and displays the report and query task', async () => {
    let queried = false
    server.use(
      http.get(prefix, () => ok({ device: { sn, model: '3KU', reported_model: '3KU' }, online_status: { online: true } })),
      http.get(`${prefix}/config-schema`, () => ok([])),
      http.get(`${prefix}/control-capabilities`, () => ok([{ command_code: 'query_config', is_enabled: true }])),
      http.get(`${prefix}/control-state`, () => ok({ reported: { set_modbus_power_saving: true }, reported_at: queried ? '2026-11-24T03:00:01Z' : '2026-11-24T03:00:00Z' })),
      http.get(`${prefix}/commands`, () => ok({ items: queried ? [{ task_id: 'read-task-id', command_name: 'query_config', status: 'success', data: { stage: 'completed' } }] : [], total: Number(queried), page: 1, page_size: 100 })),
      http.post(`${prefix}/control`, async ({ request }) => {
        const payload = await request.json()
        if (JSON.stringify(payload) !== JSON.stringify({ command: 'query_config', params: {} })) return HttpResponse.json({ code: 400 }, { status: 400 })
        queried = true
        return ok({ task_id: 'read-task-id' })
      }),
    )
    localStorage.setItem('remote-settings-device-sn', sn)
    renderAsAdmin(<RemoteSettingsPage />, { routerProps: { initialEntries: [path] } })
    const read = await screen.findByRole('button', { name: /读取当前/ })
    await waitFor(() => expect(read).toBeEnabled())
    fireEvent.click(read)
    expect(await screen.findByText('read-task-id')).toBeInTheDocument()
    expect(screen.getByText(/上次配置回报/)).toBeInTheDocument()
    expect(queried).toBe(true)
  })

  it('disables the read and power commands for a mismatched binding', async () => {
    server.use(
      http.get(prefix, () => ok({ device: { sn, model: '6KU', reported_model: '3KU' }, online_status: { online: true } })),
      http.get(`${prefix}/config-schema`, () => ok([])),
      http.get(`${prefix}/control-capabilities`, () => ok([
        { command_code: 'query_config', is_enabled: true },
        { command_code: 'ac_on', is_enabled: true },
      ])),
      http.get(`${prefix}/control-state`, () => ok({ reported: {} })),
      http.get(`${prefix}/commands`, () => ok({ items: [], total: 0, page: 1, page_size: 100 })),
    )
    localStorage.setItem('remote-settings-device-sn', sn)
    renderAsAdmin(<RemoteSettingsPage />, { routerProps: { initialEntries: [path] } })
    expect(await screen.findByText(/上报机型与系统绑定/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /读取当前/ })).toBeDisabled()
    expect(await screen.findByRole('button', { name: /开关机状态未知/ })).toBeDisabled()
  })
})

it('offers one power action and changes it after completion and telemetry refresh', async () => {
  let outputOn = false
  const commands: string[] = []
  server.use(
    http.get(prefix, () => ok({ device: { sn, model: '3KU' }, online_status: { online: true } })),
    http.get(`${prefix}/config-schema`, () => ok([])),
    http.get(`${prefix}/control-capabilities`, () => ok([
      { command_code: 'ac_on', is_enabled: true }, { command_code: 'ac_off', is_enabled: true },
    ])),
    http.get(`${prefix}/control-state`, () => ok({ reported: {} })),
    http.get(`${prefix}/realtime`, () => ok({ online: true, realtime: { ac: { ac_output_voltage: outputOn ? 230 : 0 } } })),
    http.get(`${prefix}/commands`, () => ok({
      items: commands.length ? [{ task_id: 'power-task', command_name: 'ac_on', status: 'success', data: { stage: 'completed' } }] : [],
      total: commands.length, page: 1, page_size: 100,
    })),
    http.post(`${prefix}/control`, async ({ request }) => {
      const body = await request.json() as { command: string }
      commands.push(body.command)
      outputOn = true
      return ok({ task_id: 'power-task' })
    }),
  )
  renderAsAdmin(<RemoteSettingsPage />, { routerProps: { initialEntries: [`/remote-settings?sn=${sn}`] } })
  const start = await screen.findByRole('button', { name: '交流开机' })
  expect(screen.queryByRole('button', { name: '交流关机' })).not.toBeInTheDocument()
  fireEvent.click(start)
  expect(commands).toEqual([])
  fireEvent.click(await screen.findByRole('button', { name: /确认执行/ }))
  expect(await screen.findByRole('button', { name: '交流关机' })).toBeEnabled()
  expect(screen.queryByRole('button', { name: '交流开机' })).not.toBeInTheDocument()
  expect(commands).toEqual(['ac_on'])
})

it('finds new catalog fields and device-reported read-only settings on the main page', async () => {
  server.use(
    http.get(prefix, () => ok({ device: { sn, model: '6KU' }, online_status: { online: true } })),
    http.get(`${prefix}/config-schema`, () => ok([
      { param_key: 'set_future_input_limit', group_code: 'application', control_type: 'number', scale: 1, sort_order: 80 },
      { param_key: 'set_modbus_bms_address', group_code: 'hybrid', sub_group: 'bms', control_type: 'number', scale: 1, sort_order: 81, catalog_access: 'panel_only' },
    ])),
    http.get(`${prefix}/control-capabilities`, () => ok([])),
    http.get(`${prefix}/control-state`, () => ok({ reported: { set_buzzer: 1, set_future_input_limit: 42 }, desired: { old_pending_key: 1 } })),
    http.get(`${prefix}/commands`, () => ok({ items: [], total: 0, page: 1, page_size: 100 })),
  )
  renderAsAdmin(<RemoteSettingsPage />, { routerProps: { initialEntries: [`/remote-settings?sn=${sn}`] } })
  const search = await screen.findByRole('searchbox', { name: '搜索参数' })
  fireEvent.change(search, { target: { value: 'future_input' } })
  expect(await screen.findByText('set_future_input_limit')).toBeInTheDocument()
  fireEvent.change(search, { target: { value: '蜂鸣器' } })
  expect(await screen.findByText('蜂鸣器')).toBeInTheDocument()
  expect(screen.getByText('仅设备回报')).toBeInTheDocument()
  expect(screen.queryByRole('switch')).not.toBeInTheDocument()
  fireEvent.change(search, { target: { value: 'modbus_bms_address' } })
  expect(await screen.findByText('BMS 地址')).toBeInTheDocument()
  expect(screen.getByText('仅面板设置')).toBeInTheDocument()
  expect(screen.queryByRole('spinbutton')).not.toBeInTheDocument()
  fireEvent.change(search, { target: { value: 'old_pending_key' } })
  expect(await screen.findByText('未找到匹配的参数')).toBeInTheDocument()
})

it('tracks the returned task ID when a setting is changed from the menu', async () => {
  let submitted = false
  server.use(
    http.get(prefix, () => ok({ device: { sn, model: '6KU' }, online_status: { online: true } })),
    http.get(`${prefix}/config-schema`, () => ok([
      { param_key: 'set_buzzer', group_code: 'general', control_type: 'boolean', scale: 1, sort_order: 2 },
    ])),
    http.get(`${prefix}/control-capabilities`, () => ok([{ command_code: 'set_buzzer', is_enabled: true }])),
    http.get(`${prefix}/control-state`, () => ok({ reported: { set_buzzer: 0 } })),
    http.get(`${prefix}/commands`, () => ok({
      items: submitted ? [{ task_id: 'menu-write-task', command_code: 'set_buzzer', status: 'success', data: { stage: 'applied' } }] : [],
      total: Number(submitted), page: 1, page_size: 100,
    })),
    http.post(`${prefix}/control`, async ({ request }) => {
      const body = await request.json()
      if (JSON.stringify(body) !== JSON.stringify({ command: 'set_buzzer', params: { value: true } })) {
        return HttpResponse.json({ code: 400 }, { status: 400 })
      }
      submitted = true
      return ok({ task_id: 'menu-write-task' })
    }),
  )
  localStorage.setItem('remote-settings-device-sn', sn)
  renderAsAdmin(<RemoteSettingsPage />, { routerProps: { initialEntries: ['/remote-settings'] } })
  const control = await screen.findByRole('switch')
  await waitFor(() => expect(control).toBeEnabled())
  fireEvent.click(control)
  fireEvent.click(await screen.findByRole('button', { name: '确认执行' }))
  expect(await screen.findByText('menu-write-task')).toBeInTheDocument()
  expect(submitted).toBe(true)
})
