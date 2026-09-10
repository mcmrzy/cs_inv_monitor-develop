import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { fireEvent } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import { API_BASE } from '@/utils/urls'
import OtaPage from './index'

describe('OtaPage', () => {
  it('renders upgrade tasks and firmware library tabs', async () => {
    renderAsAdmin(<OtaPage />)

    expect(await screen.findByText('升级任务')).toBeInTheDocument()
    expect(screen.getByText('固件库')).toBeInTheDocument()
    expect(document.querySelectorAll('.ant-tabs-tab').length).toBeGreaterThanOrEqual(2)
  })

  it('shows upgrade task statistics cards', async () => {
    renderAsAdmin(<OtaPage />)

    await waitFor(() => {
      // 任务统计（总数/进行中/成功/失败等）
      const stats = document.querySelectorAll('.ant-statistic, .ant-pro-card')
      expect(stats.length).toBeGreaterThan(0)
    })
  })

  it('lists upgrade tasks from the OTA tasks API', async () => {
    renderAsAdmin(<OtaPage />)

    // ota/tasks handler 返回 mockUpgradeTasks；表格出现分页或数据行
    await waitFor(() => {
      const hasTable = document.querySelector('.ant-table')
      const hasEmpty = document.querySelector('.ant-empty')
      expect(hasTable || hasEmpty).toBeTruthy()
    })
  })

  it('switches to the firmware library tab and lists firmwares', async () => {
    renderAsAdmin(<OtaPage />)

    fireEvent.click(await screen.findByText('固件库'))
    // ota/firmware handler 返回 mockFirmwares（ARM/ESP 固件）
    await waitFor(() => {
      const hasTable = document.querySelector('.ant-table')
      expect(hasTable).toBeTruthy()
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
  })
})
