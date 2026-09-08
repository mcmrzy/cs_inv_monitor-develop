import { describe, it, expect } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import InviteAcceptPage from './InviteAcceptPage'

// 注意：不要 mock @/utils/timezone —— 页面依赖其模块级 dayjs.extend(utc)

/** 通过内存路由渲染邀请接受页（页面依赖 useParams 读取 :token） */
function renderInvite(token?: string) {
  return renderAsAdmin(
    <MemoryRouter initialEntries={[token ? `/invite/accept/${token}` : '/invite/accept']}>
      <Routes>
        <Route path="/invite/accept/:token" element={<InviteAcceptPage />} />
        <Route path="/invite/accept" element={<InviteAcceptPage />} />
        <Route path="/dashboard" element={<div>dashboard-marker</div>} />
        <Route path="/login" element={<div>login-marker</div>} />
      </Routes>
    </MemoryRouter>,
    { withRouter: false },
  )
}

async function fillAndSubmit() {
  fireEvent.change(screen.getByPlaceholderText('请输入昵称'), { target: { value: '受邀用户' } })
  fireEvent.change(screen.getByPlaceholderText('请输入手机号'), { target: { value: '13800000005' } })
  fireEvent.change(screen.getByPlaceholderText('6-20 个字符'), { target: { value: 'Test1234' } })
  fireEvent.click(screen.getByRole('button', { name: '创建账号并接受邀请' }))
}

describe('InviteAcceptPage', () => {
  it('renders invitation form with nickname/phone/password fields', () => {
    renderInvite('valid-token')

    expect(screen.getByText('接受邀请')).toBeInTheDocument()
    expect(screen.getByText('创建账号并加入组织，享受渠道服务')).toBeInTheDocument()
    expect(screen.getByText('昵称')).toBeInTheDocument()
    expect(screen.getByText('手机号')).toBeInTheDocument()
    expect(screen.getByText('设置密码')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '创建账号并接受邀请' })).toBeInTheDocument()
  })

  it('shows fatal error alert when server rejects the token with 401', async () => {
    server.use(
      http.post('/api/v1/invite/accept', () =>
        HttpResponse.json({ code: 401, message: '邀请已失效' }, { status: 200 }),
      ),
    )

    renderInvite('expired-token')
    await fillAndSubmit()

    // 业务码 401 → 页面级致命错误提示 + 去登录按钮，表单被禁用
    expect(await screen.findByText('邀请链接无效或已失效')).toBeInTheDocument()
    expect(document.querySelector('.ant-alert-error')).toBeInTheDocument()
    await waitFor(() => {
      expect(screen.getByRole('button', { name: '去登录' })).toBeEnabled()
    })
    // 点击去登录 → 跳转登录页占位
    fireEvent.click(screen.getByRole('button', { name: '去登录' }))
    expect(screen.getByText('login-marker')).toBeInTheDocument()
  })

  it('logs in and navigates to dashboard on successful accept', async () => {
    server.use(
      http.post('/api/v1/invite/accept', () =>
        HttpResponse.json({
          code: 0,
          message: 'success',
          data: {
            invitation_id: 9,
            user: { id: 9, phone: '13800000005', nickname: '受邀用户', role: 3, status: 1 },
            access_token: 'invite-access-token',
            refresh_token: 'invite-refresh-token',
            permissions: ['dashboard:view'],
          },
        }),
      ),
    )

    renderInvite('valid-token')
    await fillAndSubmit()

    // 成功后 login() + navigate('/dashboard')
    expect(await screen.findByText('dashboard-marker')).toBeInTheDocument()
  })

  it('shows toast error for non-401 business failures', async () => {
    server.use(
      http.post('/api/v1/invite/accept', () =>
        HttpResponse.json({ code: 500, message: '服务器开小差' }, { status: 200 }),
      ),
    )

    renderInvite('valid-token')
    await fillAndSubmit()

    // 非 401 业务失败 → message 提示，不出现页面级 Alert
    await waitFor(() => {
      expect(document.querySelector('.ant-message')).toBeInTheDocument()
    })
    expect(document.querySelector('.ant-alert-error')).not.toBeInTheDocument()
  })

  it('validates required fields before submitting', async () => {
    renderInvite('valid-token')

    // 空表单直接提交 → 校验错误，不触发请求
    fireEvent.click(screen.getByRole('button', { name: '创建账号并接受邀请' }))

    await waitFor(() => {
      expect(document.querySelectorAll('.ant-form-item-explain-error').length).toBeGreaterThanOrEqual(3)
    })
    expect(document.querySelector('.ant-message')).not.toBeInTheDocument()
  })
})
