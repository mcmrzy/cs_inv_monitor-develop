import { describe, it, expect, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import DownloadPage from './index'

const LATEST_URL = '/api/v1/ota/app/latest'

const releasePayload = (overrides: Record<string, unknown> = {}) => ({
  code: 0,
  message: 'success',
  data: {
    available: true,
    platform: 'android',
    version_code: 10,
    version_name: '1.0.9',
    download_url: 'https://download.jiuxiaoyw.online/firmware/apps/android/app.apk',
    file_name: 'com.csergy.app1-1.0.9-10-1.apk',
    file_size: 103_716_290,
    file_sha256: 'a'.repeat(64),
    package_name: 'com.csergy.app1',
    min_sdk: 29,
    target_sdk: 36,
    changelog: '- 修复夜间误报\n- 优化配网流程',
    is_force: false,
    published_at: '2026-09-10T02:00:00Z',
    ...overrides,
  },
})

describe('DownloadPage', () => {
  it('renders app title, subtitle and feature list', async () => {
    server.use(http.get(LATEST_URL, () => HttpResponse.json(releasePayload())))

    renderAsAdmin(<DownloadPage />)

    expect(screen.getByText('辰烁光伏逆变')).toBeInTheDocument()
    expect(screen.getByText('光伏电站智能监控平台')).toBeInTheDocument()
    expect(screen.getByText('实时监控')).toBeInTheDocument()
    expect(screen.getByText('数据分析')).toBeInTheDocument()
    expect(screen.getByText('告警推送')).toBeInTheDocument()
    expect(screen.getByText('远程运维')).toBeInTheDocument()
  })

  it('renders download button, platform chips and security tip', async () => {
    server.use(http.get(LATEST_URL, () => HttpResponse.json(releasePayload())))

    renderAsAdmin(<DownloadPage />)

    const btn = await screen.findByRole('button', { name: /下载 Android 安装包/ })
    expect(btn).toBeEnabled()
    expect(screen.getByText('Android 专用')).toBeInTheDocument()
    expect(screen.getByText(/官方正版/)).toBeInTheDocument()
  })

  // 旧实现读错了响应层级（把 AxiosResponse 当 data 用），版本信息永远不显示；
  // 本用例锁定「公开接口 → 页面展示版本元数据」这条真实链路。
  it('shows the released version metadata returned by the public release API', async () => {
    server.use(http.get(LATEST_URL, () => HttpResponse.json(releasePayload())))

    renderAsAdmin(<DownloadPage />)

    // 版本号同时出现在顶部徽标与规格表，断言存在即可
    expect((await screen.findAllByText('v1.0.9')).length).toBeGreaterThan(0)
    expect(screen.getByText('com.csergy.app1')).toBeInTheDocument()
    expect(screen.getByText('a'.repeat(64))).toBeInTheDocument()
    expect(screen.getByText('Android 10+')).toBeInTheDocument()
    // 体积同时出现在顶部标签与规格表（103716290 B ≈ 98.9 MB）
    expect(screen.getAllByText(/98\.9 MB/).length).toBeGreaterThan(0)
    // 更新说明按行拆分成条目
    expect(screen.getByText('修复夜间误报')).toBeInTheDocument()
    expect(screen.getByText('优化配网流程')).toBeInTheDocument()
  })

  it('disables the download action when no release is published yet', async () => {
    server.use(
      http.get(LATEST_URL, () =>
        HttpResponse.json({ code: 0, message: 'success', data: { available: false } }),
      ),
    )

    renderAsAdmin(<DownloadPage />)

    const btn = await screen.findByRole('button', { name: /安装包准备中/ })
    expect(btn).toBeDisabled()
    expect(screen.getByText('最新版本正在发布，请稍后刷新页面重试。')).toBeInTheDocument()
  })

  it('still renders the full page when the release API fails', async () => {
    server.use(
      http.get(LATEST_URL, () => HttpResponse.json({ code: 500, message: 'boom' }, { status: 500 })),
    )

    renderAsAdmin(<DownloadPage />)

    expect(screen.getByText('辰烁光伏逆变')).toBeInTheDocument()
    const btn = await screen.findByRole('button', { name: /安装包准备中/ })
    expect(btn).toBeDisabled()
  })

  it('copies the SHA-256 checksum to the clipboard', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    Object.assign(navigator, { clipboard: { writeText } })
    server.use(http.get(LATEST_URL, () => HttpResponse.json(releasePayload())))

    renderAsAdmin(<DownloadPage />)

    const copyButtons = await screen.findAllByRole('button', { name: '复制' })
    copyButtons[0].click()

    await waitFor(() => {
      expect(writeText).toHaveBeenCalledWith('a'.repeat(64))
    })
    expect(await screen.findByText('已复制')).toBeInTheDocument()
  })
})
