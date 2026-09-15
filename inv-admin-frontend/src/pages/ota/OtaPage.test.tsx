import { describe, it, expect } from 'vitest'
import { screen, waitFor, fireEvent } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin, renderWithProviders } from '@/test/test-utils'
import { mockManagerUser } from '@/test/mocks/data'
import { API_BASE } from '@/utils/urls'
import OtaPage from './index'

describe('OtaPage', () => {
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
