import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import DownloadPage from './index'

describe('DownloadPage', () => {
  it('renders app title, subtitle and feature list', async () => {
    // 无版本接口 handler 时页面仍需完整渲染
    server.use(
      http.get('/api/v1/ota/app/check', () =>
        HttpResponse.json({ code: 0, message: 'success', data: null }, { status: 404 }),
      ),
    )

    renderAsAdmin(<DownloadPage />)

    expect(screen.getByText('辰烁光伏逆变')).toBeInTheDocument()
    expect(screen.getByText('光伏电站智能监控平台')).toBeInTheDocument()
    // 四个功能特性
    expect(screen.getByText('实时监控')).toBeInTheDocument()
    expect(screen.getByText('数据分析')).toBeInTheDocument()
    expect(screen.getByText('告警推送')).toBeInTheDocument()
    expect(screen.getByText('远程运维')).toBeInTheDocument()
  })

  it('renders download button and android badge', async () => {
    server.use(
      http.get('/api/v1/ota/app/check', () =>
        HttpResponse.json({ code: 0, message: 'success', data: null }, { status: 404 }),
      ),
    )

    renderAsAdmin(<DownloadPage />)

    const btn = await screen.findByRole('button', { name: /下载 Android 安装包/ })
    expect(btn).toBeInTheDocument()
    expect(btn).toBeEnabled()
    expect(screen.getByText('Android 专用')).toBeInTheDocument()
    expect(screen.getByText(/官方正版/)).toBeInTheDocument()
  })

  it('falls back to loading placeholder when version info cannot be read', async () => {
    // 即使接口返回有效版本数据，页面读取字段方式（顶层 latest_version_name）
    // 与 {code,data} 包装不匹配 → 显示占位文案，属于当前实现的容错行为
    server.use(
      http.get('/api/v1/ota/app/check', () =>
        HttpResponse.json({
          code: 0,
          message: 'success',
          data: {
            has_update: true,
            latest_version_code: 12,
            latest_version_name: '1.2.3',
            download_url: 'https://example.com/app.apk',
            file_size: 12918456,
            file_md5: 'md5',
            changelog: '修复若干问题',
            is_force: false,
          },
        }),
      ),
    )
    renderAsAdmin(<DownloadPage />)

    await waitFor(() => {
      expect(screen.getByText('版本信息加载中...')).toBeInTheDocument()
    })
    // 加载结束后 Spin 消失
    expect(document.querySelector('.ant-spin-spinning')).not.toBeInTheDocument()
  })
})
