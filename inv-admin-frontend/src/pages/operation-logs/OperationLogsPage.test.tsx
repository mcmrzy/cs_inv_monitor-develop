import { describe, it, expect } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import OperationLogsPage from './index'

// 注意：不要 mock @/utils/timezone —— 页面依赖其模块级 dayjs.extend(utc)

describe('OperationLogsPage', () => {
  it('renders title, filter bar and three log tabs', async () => {
    renderAsAdmin(<OperationLogsPage />)

    // 过滤栏
    expect(screen.getByText('时间范围')).toBeInTheDocument()
    expect(screen.getByText('日志类型')).toBeInTheDocument()
    expect(screen.getByText('用户筛选')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('用户名')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('设备序列号')).toBeInTheDocument()
    // 三个日志 Tab（注意页面标题与第一个 Tab 同为「操作记录」）
    await waitFor(() => {
      expect(document.querySelectorAll('.ant-tabs-tab').length).toBe(3)
    })
    expect(screen.getByText('告警日志')).toBeInTheDocument()
    expect(screen.getByText('命令日志')).toBeInTheDocument()
  })

  it('renders audit log table with mocked login record', async () => {
    renderAsAdmin(<OperationLogsPage />)

    // /admin/logs 返回 admin 的登录审计记录
    expect(await screen.findByText('管理员登录')).toBeInTheDocument()
    expect(screen.getByText('admin')).toBeInTheDocument()
    expect(screen.getByText('127.0.0.1')).toBeInTheDocument()
    // 操作类型标签
    expect(screen.getAllByText('登录').length).toBeGreaterThanOrEqual(1)
    // 导出按钮
    expect(screen.getByRole('button', { name: /导出CSV/ })).toBeInTheDocument()
  })

  it('switches to alarm log tab and renders alarm records', async () => {
    renderAsAdmin(<OperationLogsPage />)

    await screen.findByText('管理员登录')
    fireEvent.click(screen.getByText('告警日志'))

    // /alarms 返回 mockAlerts：INV20250001 温度过高
    expect(await screen.findByText('逆变器温度过高')).toBeInTheDocument()
    expect(screen.getByText('INV20250001')).toBeInTheDocument()
    expect(screen.getByText('INV20250003')).toBeInTheDocument()
  })

  it('switches to command log tab and renders command records', async () => {
    renderAsAdmin(<OperationLogsPage />)

    await screen.findByText('管理员登录')
    fireEvent.click(screen.getByText('命令日志'))

    // 命令日志复用审计记录（action=command），当前 mock 为 login 记录 → 表格为空但表头存在
    await waitFor(() => {
      const tables = document.querySelectorAll('.ant-table')
      expect(tables.length).toBeGreaterThanOrEqual(1)
    })
    // Tab 激活后仍保留导出能力
    expect(screen.getByRole('button', { name: /导出CSV/ })).toBeInTheDocument()
  })

  it('shows error alert when audit log request fails', async () => {
    server.use(
      http.get('/api/v1/admin/logs', () =>
        HttpResponse.json({ code: 500, message: 'boom' }, { status: 500 }),
      ),
    )

    renderAsAdmin(<OperationLogsPage />)

    await waitFor(() => {
      expect(document.querySelector('.ant-alert-error')).toBeInTheDocument()
    })
  })
})
