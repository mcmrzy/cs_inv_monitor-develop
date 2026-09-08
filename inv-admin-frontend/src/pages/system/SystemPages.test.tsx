import { describe, it, expect } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import SystemConfigPage from './SystemConfig'
import SystemMonitorPage from './SystemMonitor'

// 注意：不要 mock @/utils/timezone —— 页面依赖其模块级 dayjs.extend(utc)

describe('SystemConfigPage', () => {
  it('renders title with two tabs and help center form', async () => {
    renderAsAdmin(<SystemConfigPage />)

    expect(screen.getByText('通知与文档配置')).toBeInTheDocument()
    await waitFor(() => {
      expect(document.querySelectorAll('.ant-tabs-tab').length).toBe(2)
    })
    expect(screen.getByText('帮助文档配置')).toBeInTheDocument()
    expect(screen.getByText('邮件模板配置')).toBeInTheDocument()
    // 帮助中心配置表单
    expect(screen.getByText('帮助中心配置')).toBeInTheDocument()
    expect(screen.getByText('客服电话')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('请输入客服电话号码')).toBeInTheDocument()
  })

  it('loads help center config from system-config API into form and FAQ list', async () => {
    server.use(
      http.get('/api/v1/admin/system-config', () =>
        HttpResponse.json({
          code: 0,
          message: 'success',
          data: {
            help_center: {
              docs: { device: 'https://docs.example.com/device', app: '', system: '' },
              phone: '400-800-8888',
              faqs: [{ q: '如何绑定设备？', a: '在设备页扫码绑定' }],
            },
          },
        }),
      ),
    )

    renderAsAdmin(<SystemConfigPage />)

    await waitFor(() => {
      expect(screen.getByPlaceholderText('请输入客服电话号码')).toHaveValue('400-800-8888')
    })
    expect(screen.getByText('如何绑定设备？')).toBeInTheDocument()
    expect(screen.getByText('在设备页扫码绑定')).toBeInTheDocument()
  })

  it('renders email template table on email templates tab', async () => {
    server.use(
      http.get('/api/v1/email/templates', () =>
        HttpResponse.json({
          code: 0,
          message: 'success',
          data: [
            {
              template_key: 'invite',
              subject: '邀请加入 CSERGY',
              html_body: '<p>hello</p>',
              enabled: true,
              updated_at: '2026-01-01T00:00:00Z',
            },
          ],
        }),
      ),
    )

    renderAsAdmin(<SystemConfigPage />)

    await screen.findByText('帮助文档配置')
    fireEvent.click(screen.getByText('邮件模板配置'))

    // 模板列表渲染
    expect(await screen.findByText('邀请加入 CSERGY')).toBeInTheDocument()
    expect(screen.getByText('invite')).toBeInTheDocument()
    // 测试邮件发送区
    expect(screen.getByPlaceholderText(/邮箱/)).toBeInTheDocument()
  })
})

describe('SystemMonitorPage', () => {
  it('renders title, big screen entry and five tabs', async () => {
    renderAsAdmin(<SystemMonitorPage />)

    expect(screen.getByText('系统监控')).toBeInTheDocument()
    await waitFor(() => {
      expect(document.querySelectorAll('.ant-tabs-tab').length).toBe(5)
    })
    // 「系统健康」同时出现在 Tab 与健康面板标题中，用 getAllByText 断言 Tab 存在
    expect(screen.getAllByText('系统健康').length).toBeGreaterThanOrEqual(1)
    expect(screen.getByText('数据管道')).toBeInTheDocument()
    expect(screen.getByText('运营统计')).toBeInTheDocument()
    expect(screen.getByText('系统日志')).toBeInTheDocument()
    // 大屏入口按钮
    expect(screen.getByRole('button', { name: /大屏/ })).toBeInTheDocument()
  })

  it('renders system health metrics from admin system-health API', async () => {
    renderAsAdmin(<SystemMonitorPage />)

    // /admin/system-health: cpu=12.5 → 13%, memory=45.2 → 45%
    await waitFor(() => {
      const texts = Array.from(document.querySelectorAll('.ant-progress-text')).map((e) => e.textContent)
      expect(texts).toContain('13%')
      expect(texts).toContain('45%')
    })
    // CPU 使用率面板 + 服务状态（数据库/Redis/MQTT 已连接）
    expect(screen.getByText('CPU使用率')).toBeInTheDocument()
    await waitFor(() => {
      expect(screen.getAllByText('已连接').length).toBe(3)
    })
    expect(screen.getByText('1.0.0')).toBeInTheDocument()
  })
})
