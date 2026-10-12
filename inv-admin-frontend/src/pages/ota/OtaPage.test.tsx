import { describe, it, expect } from 'vitest'
import { screen, waitFor, fireEvent } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin, renderWithProviders } from '@/test/test-utils'
import { mockManagerUser } from '@/test/mocks/data'
import { API_BASE } from '@/utils/urls'
import OtaPage from './index'

describe('OtaPage', () => {
  it('uploads a file with multiple selected standard hardware versions', async () => {
    let body = ''
    server.use(
      http.get(`${API_BASE}/ota/firmware`, () => HttpResponse.json({ code: 0, data: [{
        id: '901', model: 'L10', target_chip: 'esp', version: '1.0', release_status: 'published', file_size: 123,
        hardware_versions: ['HW-1'],
      }] })),
      http.get(`${API_BASE}/ota/hardware-versions`, () => HttpResponse.json({ code: 0, data: [
        { model: 'L10', version: 'HW-1' }, { model: 'L10', version: 'HW-2' },
      ] })),
      http.post(`${API_BASE}/ota/firmware`, async ({ request }) => {
        body = await request.text()
        return HttpResponse.json({ code: 0, data: { version: '2.0', target_chip: 'esp' } })
      }),
    )
    renderAsAdmin(<OtaPage />, { routerProps: { initialEntries: ['/ota?tab=firmware'] } })
    fireEvent.click(await screen.findByRole('button', { name: /上传固件/ }))
    const dialog = await screen.findByRole('dialog')
    let combos = dialog.querySelectorAll('[role="combobox"]')
    fireEvent.mouseDown(combos[0])
    fireEvent.click(await screen.findByText('L10', { selector: '.ant-select-item-option-content' }))
    fireEvent.mouseDown(combos[1])
    fireEvent.click(await screen.findByText('通信采集（ESP）', { selector: '.ant-select-item-option-content' }))
    combos = dialog.querySelectorAll('[role="combobox"]')
    fireEvent.mouseDown(combos[2])
    fireEvent.click(await screen.findByText('HW-1', { selector: '.ant-select-item-option-content' }))
    fireEvent.click(await screen.findByText('HW-2', { selector: '.ant-select-item-option-content' }))
    fireEvent.change(dialog.querySelector('input[type="file"]')!, { target: { files: [new File(['bytes'], 'fw.bin')] } })
    await screen.findByText('fw.bin')
    fireEvent.click(screen.getByRole('button', { name: /确.*定/ }))
    await waitFor(() => expect(body).toContain('name="hardware_versions"'))
    expect(body).toContain('["HW-1","HW-2"]')
    expect(body).toContain('name="model"')
  })
  it('limits batch selection and select-all to the explicit hardware range', async () => {
    server.use(
      http.get(`${API_BASE}/ota/firmware`, () => HttpResponse.json({ code: 0, data: [{
        id: '901', model: 'L10', target_chip: 'esp', version: '1.0', release_status: 'published',
        hardware_versions: ['HW-1'],
      }] })),
      http.get(`${API_BASE}/devices`, () => HttpResponse.json({ code: 0, data: { items: [
        { id: '1', sn: 'COMPATIBLE', model: 'L10', hardware_version: 'HW-1' },
        { id: '2', sn: 'OTHER-HARDWARE', model: 'L10', hardware_version: 'HW-2' },
        { id: '3', sn: 'UNKNOWN-HARDWARE', model: 'L10', hardware_version: '' },
      ], total: 3 } })),
    )
    renderAsAdmin(<OtaPage />, { routerProps: { initialEntries: ['/ota?tab=tasks'] } })
    fireEvent.click(await screen.findByRole('button', { name: /创建升级任务/ }))
    const dialog = await screen.findByRole('dialog')
    fireEvent.mouseDown(dialog.querySelector('[role="combobox"]')!)
    fireEvent.click(await screen.findByText('L10 · 通信采集 · 1.0 · HW-1', { selector: '.ant-select-item-option-content' }))
    fireEvent.click(screen.getByRole('button', { name: '下一步' }))
    expect(await screen.findByText('COMPATIBLE')).toBeInTheDocument()
    expect(screen.queryByText('OTHER-HARDWARE')).not.toBeInTheDocument()
    expect(screen.queryByText('UNKNOWN-HARDWARE')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('checkbox', { name: '全选' }))
    expect(await screen.findByText('已选择 1 台设备')).toBeInTheDocument()
  })
  it('shows unconfirmed hardware and does not claim no updates when compatibility is unknown', async () => {
    server.use(http.get(`${API_BASE}/ota/devices/:sn/firmware-overview`, ({ params }) => HttpResponse.json({
      code: 0, data: {
        device_sn: params.sn, device_model: 'SG-5K-D', hardware_version: '', hardware_state: 'unknown', is_online: true,
        modules: [{ target: 'arm', current_version: '1.0', latest_version: '', latest_firmware_id: 0,
          version_state: 'current', update_available: false, compatibility_reason: 'hardware_version_unknown' }],
      },
    })))
    renderAsAdmin(<OtaPage />)
    fireEvent.click((await screen.findAllByText('INV20250001'))[0])
    expect((await screen.findAllByText('硬件版本未确认')).length).toBeGreaterThan(0)
    expect(screen.queryByRole('button', { name: '升级' })).not.toBeInTheDocument()
  })

  it('lets an administrator supplement a legacy firmware range from the hardware directory', async () => {
    let submitted: any
    server.use(
      http.get(`${API_BASE}/ota/firmware`, () => HttpResponse.json({ code: 0, data: [{
        id: '901', model: 'L10', target_chip: 'esp', version: '1.0', release_status: 'published', file_size: 123,
        hardware_versions: [], created_at: '2026-10-01T00:00:00Z',
      }] })),
      http.get(`${API_BASE}/ota/hardware-versions`, () => HttpResponse.json({ code: 0, data: [{ model: 'L10', version: 'HW-2' }] })),
      http.put(`${API_BASE}/ota/firmware/901/hardware-versions`, async ({ request }) => {
        submitted = await request.json()
        return HttpResponse.json({ code: 0, data: {} })
      }),
    )
    renderAsAdmin(<OtaPage />, { routerProps: { initialEntries: ['/ota?tab=firmware'] } })
    fireEvent.click(await screen.findByRole('button', { name: '设置适用硬件' }))
    const dialog = await screen.findByRole('dialog')
    fireEvent.mouseDown(dialog.querySelector('[role="combobox"]')!)
    fireEvent.click(await screen.findByText('HW-2', { selector: '.ant-select-item-option-content' }))
    fireEvent.click(screen.getByRole('button', { name: /确.*定/ }))
    await waitFor(() => expect(submitted).toEqual({ hardware_versions: ['HW-2'] }))
  })
  it('renders five tabs for an admin', async () => {
    renderAsAdmin(<OtaPage />)

    expect(await screen.findByText('设备固件升级')).toBeInTheDocument()
    expect(screen.getByText('设备固件管理')).toBeInTheDocument()
    expect(screen.getByText('升级任务')).toBeInTheDocument()
    expect(screen.getByText('更新记录')).toBeInTheDocument()
    expect(screen.getByText('App版本管理')).toBeInTheDocument()
    expect(document.querySelectorAll('.ant-tabs-tab').length).toBeGreaterThanOrEqual(5)
  })

  it('does not expose package management UI', async () => {
    renderAsAdmin(<OtaPage />)

    await screen.findByText('设备固件升级')
    expect(screen.queryByText('升级包管理')).not.toBeInTheDocument()
    expect(screen.queryByText('创建升级包')).not.toBeInTheDocument()
    expect(screen.queryByText('升级包（上传自动组装）')).not.toBeInTheDocument()
  })

  it('shows device firmware overview on the default device tab', async () => {
    renderAsAdmin(<OtaPage />)

    expect(await screen.findByText('设备固件升级')).toBeInTheDocument()
    // 设备列表来自 devices API
    await waitFor(() => {
      const hasTable = document.querySelector('.ant-table')
      const hasEmpty = document.querySelector('.ant-empty')
      expect(hasTable || hasEmpty).toBeTruthy()
    })
  })

  it('switches to firmware management and lists firmwares with release status', async () => {
    renderAsAdmin(<OtaPage />)

    fireEvent.click(await screen.findByText('设备固件管理'))
    await waitFor(() => {
      const hasTable = document.querySelector('.ant-table')
      expect(hasTable).toBeTruthy()
    })
    // 发布生命周期标签
    expect(await screen.findAllByText('已发布')).not.toHaveLength(0)
  })

  it('switches to upgrade tasks and lists tasks', async () => {
    renderAsAdmin(<OtaPage />)

    fireEvent.click(await screen.findByText('升级任务'))
    await waitFor(() => {
      const hasTable = document.querySelector('.ant-table')
      const hasEmpty = document.querySelector('.ant-empty')
      expect(hasTable || hasEmpty).toBeTruthy()
    })
  })

  it('switches to aggregated update history tab', async () => {
    renderAsAdmin(<OtaPage />)

    fireEvent.click(await screen.findByText('更新记录'))
    await waitFor(() => {
      const hasTable = document.querySelector('.ant-table')
      const hasEmpty = document.querySelector('.ant-empty')
      expect(hasTable || hasEmpty).toBeTruthy()
    })
  })

  it('falls back to device tab when a non-admin lacks ota:view deep link', async () => {
    renderWithProviders(<OtaPage />, {
      initialUser: mockManagerUser,
      initialToken: 'mock-jwt-token',
      initialPermissions: ['devices:view'],
      routerProps: { initialEntries: ['/ota?tab=firmware'] },
    })

    // 无权打开管理 Tab 时应停留在设备固件升级
    expect(await screen.findByText('设备固件升级')).toBeInTheDocument()
    // 管理 Tab 不渲染
    await waitFor(() => {
      expect(screen.queryByText('设备固件管理')).not.toBeInTheDocument()
      expect(screen.queryByText('升级任务')).not.toBeInTheDocument()
    })
  })

  it('does not nest aggregate history under the device firmware tab', async () => {
    let aggregateHistoryRequests = 0
    server.use(
      http.get(`${API_BASE}/ota/history`, () => {
        aggregateHistoryRequests += 1
        return HttpResponse.json({ code: 0, data: { items: [], total: 0 } })
      }),
    )

    renderWithProviders(<OtaPage />, {
      initialUser: mockManagerUser,
      initialToken: 'mock-jwt-token',
      initialPermissions: ['devices:view'],
      routerProps: { initialEntries: ['/ota?tab=deviceFirmware'] },
    })

    // 设备固件升级页不再内嵌「全部更新记录」，聚合历史由独立 Tab 提供
    expect(await screen.findByText('选择设备')).toBeInTheDocument()
    expect(screen.queryByText('全部更新记录')).not.toBeInTheDocument()
  })

  it('keeps the tasks tab selected after consuming batch-create query parameters', async () => {
    renderWithProviders(<OtaPage />, {
      initialUser: mockManagerUser,
      initialToken: 'mock-jwt-token',
      initialPermissions: ['devices:view', 'ota:view', 'ota:create'],
      routerProps: { initialEntries: ['/ota?tab=tasks&create=1&sns=INV20250001'] },
    })

    const tasksTab = await screen.findByRole('tab', { name: '升级任务' })
    await waitFor(() => expect(tasksTab).toHaveAttribute('aria-selected', 'true'))
    expect((await screen.findAllByText('创建升级任务')).length).toBeGreaterThan(0)
  })

  it('renders legacy package tasks as generic read-only history', async () => {
    server.use(
      http.get(`${API_BASE}/ota/tasks`, () =>
        HttpResponse.json({
          code: 0,
          data: {
            items: [{
              id: 'legacy-1',
              name: '历史批次',
              task_type: 'package',
              model: 'SG-5K-D',
              target_version: 'V1.0.0',
              status: 'completed',
              execute_mode: 'immediate',
              rollout_percent: 100,
              total_devices: 1,
              success_count: 1,
              failed_count: 0,
              created_at: '2026-01-01T00:00:00Z',
              updated_at: '2026-01-01T00:00:00Z',
            }],
            total: 1,
          },
        }),
      ),
    )

    renderAsAdmin(<OtaPage />, {
      routerProps: { initialEntries: ['/ota?tab=tasks'] },
    })

    expect(await screen.findByText('历史任务')).toBeInTheDocument()
    expect(screen.queryByText('升级包')).not.toBeInTheDocument()
  })

  it('uses devices:control rather than ota permissions for device upgrade actions', { timeout: 30_000 }, async () => {
    renderWithProviders(<OtaPage />, {
      initialUser: mockManagerUser,
      initialToken: 'mock-jwt-token',
      initialPermissions: ['devices:view', 'devices:control'],
    })

    fireEvent.click((await screen.findAllByText('INV20250001'))[0])
    expect(await screen.findByRole('button', { name: /升级/ })).toBeInTheDocument()
    await screen.findByText('系统主控')
    expect(screen.getAllByRole('button', { name: /回退/ }).length).toBeGreaterThan(0)
  })

  it('does not accept ota:control as device-scoped control permission', async () => {
    renderWithProviders(<OtaPage />, {
      initialUser: mockManagerUser,
      initialToken: 'mock-jwt-token',
      initialPermissions: ['devices:view', 'ota:control'],
    })

    fireEvent.click((await screen.findAllByText('INV20250001'))[0])
    await screen.findByText('固件概览')
    expect(screen.queryByRole('button', { name: '升级' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /回退/ })).not.toBeInTheDocument()
  })

  it('hides remote upgrade actions when backend eligibility is false', async () => {
    server.use(
      http.get(`${API_BASE}/ota/devices/:sn/firmware-overview`, ({ params }) =>
        HttpResponse.json({
          code: 0,
          data: {
            device_sn: String(params.sn),
            device_model: 'SG-5K-D',
            is_online: true,
            modules: [{
              target: 'arm',
              current_version: '1.0.0',
              latest_firmware_id: 301,
              latest_version: '1.1.0',
              version_state: 'outdated',
              update_available: true,
              supported: true,
              connected: true,
              eligible: false,
              supported_channels: ['remote'],
              changelog: '',
            }],
          },
        }),
      ),
    )

    renderWithProviders(<OtaPage />, {
      initialUser: mockManagerUser,
      initialToken: 'mock-jwt-token',
      initialPermissions: ['devices:view', 'devices:control'],
    })

    fireEvent.click((await screen.findAllByText('INV20250001'))[0])
    await screen.findByText('固件概览')
    expect(screen.queryByRole('button', { name: '升级' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: '全部升级' })).not.toBeInTheDocument()
  })

  it('shows name, model, serial number and hardware version in the selected device card', async () => {
    server.use(
      http.get(`${API_BASE}/devices`, () =>
        HttpResponse.json({
          code: 0,
          data: {
            items: [{
              id: '1',
              sn: 'DETAIL-SN-001',
              alias: '屋顶逆变器',
              model: 'SG-5K-D',
              hardware_version: 'HW-2.0',
              status: 1,
            }],
            total: 1,
          },
        }),
      ),
    )

    renderWithProviders(<OtaPage />, {
      initialUser: mockManagerUser,
      initialToken: 'mock-jwt-token',
      initialPermissions: ['devices:view'],
    })

    fireEvent.click(await screen.findByText('屋顶逆变器'))
    expect((await screen.findAllByText('设备名称')).length).toBeGreaterThan(0)
    expect(screen.getByText('硬件版本')).toBeInTheDocument()
    expect(screen.getAllByText('DETAIL-SN-001').length).toBeGreaterThan(0)
    expect(screen.getAllByText('HW-2.0').length).toBeGreaterThan(0)
  })

  // 回归：左侧设备列表曾按 device.status === 'online' 字符串比较，而 /devices 下发的是
  // 数字 0/1/2，恒为 false，导致列表里每台设备都显示「离线」而右侧详情显示「在线」。
  it('renders numeric device status as online/fault/offline in the device picker', async () => {
    server.use(
      http.get(`${API_BASE}/devices`, () =>
        HttpResponse.json({
          code: 0,
          data: {
            items: [
              { id: '1', sn: 'ONLINE-SN-001', model: 'SG-5K-D', status: 1 },
              { id: '2', sn: 'FAULT-SN-002', model: 'SG-5K-D', status: 2 },
              { id: '3', sn: 'OFFLINE-SN-003', model: 'SG-5K-D', status: 0 },
            ],
            total: 3,
          },
        }),
      ),
    )

    renderAsAdmin(<OtaPage />)

    await screen.findByText('ONLINE-SN-001')
    expect(screen.getByText('在线')).toBeInTheDocument()
    // 2=故障 仍属在线设备，必须与纯离线区分开
    expect(screen.getByText('故障')).toBeInTheDocument()
    expect(screen.getByText('离线')).toBeInTheDocument()
  })

  // 发布 App 版本改为直接上传 APK：版本号/包名/体积/SHA-256 由服务端解析，
  // 前端不得再提交这些字段（否则又会与安装包本体不一致）。
  it('publishes an app version by uploading the APK without manual metadata', async () => {
    let rawBody = ''
    let requestSeen = false
    server.use(
      http.get(`${API_BASE}/ota/app/versions`, () =>
        HttpResponse.json({ code: 0, message: 'success', data: [] }),
      ),
      http.post(`${API_BASE}/ota/app/versions`, async ({ request }) => {
        requestSeen = true
        rawBody = await request.text()
        return HttpResponse.json({
          code: 0,
          message: 'success',
          data: { id: 1, version_name: '1.0.9', version_code: 10, package_name: 'com.csergy.app1' },
        })
      }),
    )

    renderAsAdmin(<OtaPage />)

    fireEvent.click(await screen.findByText('App版本管理'))
    const openButton = await screen.findByRole('button', { name: /上传安装包/ })
    fireEvent.click(openButton)

    // antd Modal 通过 portal 挂在 document.body 上，不在 render 容器内
    let fileInput: HTMLInputElement | null = null
    await waitFor(() => {
      fileInput = document.querySelector('.ant-modal input[type="file"]')
      expect(fileInput).toBeTruthy()
    })
    const apk = new File(['apk-bytes'], 'app-release.apk', {
      type: 'application/vnd.android.package-archive',
    })
    fireEvent.change(fileInput as unknown as HTMLInputElement, { target: { files: [apk] } })
    // 选中的安装包出现在上传列表中，说明 beforeUpload 已接管文件
    expect(await screen.findByText('app-release.apk')).toBeInTheDocument()

    fireEvent.click(await screen.findByRole('button', { name: '上传并发布' }))

    await waitFor(() => {
      expect(requestSeen).toBe(true)
    })

    // 直接断言 multipart 原始报文包含哪些字段，避免依赖运行时 FormData 解析
    expect(rawBody).toContain('name="file"')
    expect(rawBody).toContain('name="platform"')
    expect(rawBody).toContain('name="rollout_percentage"')
    // 这些字段必须由服务端从 APK 解析，前端不得提交
    for (const field of ['version_code', 'version_name', 'download_url', 'file_size', 'file_sha256', 'file_md5']) {
      expect(rawBody).not.toContain(`name="${field}"`)
    }
    // 本用例渲染整页 OTA（ProTable + 多个 antd 组件）并跨 portal 操作弹窗，
    // CI 带 v8 覆盖率运行时明显慢于本地，需显式放宽超时（默认 5s 会误判超时）。
  }, 30_000)
})
