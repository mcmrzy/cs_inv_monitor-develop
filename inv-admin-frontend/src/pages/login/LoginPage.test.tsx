import { beforeEach, describe, it, expect, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { mockLoginResponse } from '@/test/mocks/data'
import { renderWithProviders } from '@/test/test-utils'
import LoginPage from './index'
import useAuthStore from '@/stores/authStore'
import useLocaleStore from '@/stores/localeStore'

// Mock the SliderCaptchaModal to avoid complex rendering
vi.mock('@/components/SliderCaptcha/SliderCaptchaModal', () => ({
  default: () => null,
}))

describe('LoginPage', () => {
  beforeEach(() => {
    useLocaleStore.setState({ lang: 'zh' })
  })

  it('should render the login form', () => {
    renderWithProviders(<LoginPage />)

    // Should show welcome text
    expect(screen.getByText('欢迎回来')).toBeInTheDocument()
    expect(screen.getByText('登录您的账户以继续')).toBeInTheDocument()
  })

  it('should render the English login experience when English is selected', () => {
    renderWithProviders(<LoginPage />, { initialLang: 'en' })

    expect(screen.getByText('Welcome Back')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('Phone / Email')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('Password')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Sign In' })).toBeInTheDocument()
  })

  it('should render login tab, register tab, and reset tab', () => {
    renderWithProviders(<LoginPage />)

    expect(screen.getByText('密码登录')).toBeInTheDocument()
    expect(screen.getByText('注册')).toBeInTheDocument()
    expect(screen.getByText('重置密码')).toBeInTheDocument()
  })

  it('should show account and password input fields', () => {
    renderWithProviders(<LoginPage />)

    const accountInput = screen.getByPlaceholderText('手机号 / 邮箱')
    expect(accountInput).toBeInTheDocument()

    const passwordInput = screen.getByPlaceholderText('密码')
    expect(passwordInput).toBeInTheDocument()
  })

  it('should show remember account checkbox', () => {
    renderWithProviders(<LoginPage />)
    // 组件 i18n 文案为「记住账号」（zh remember）
    expect(screen.getByText('记住账号')).toBeInTheDocument()
  })

  it('should show forgot password link', () => {
    renderWithProviders(<LoginPage />)
    expect(screen.getByText('忘记密码？')).toBeInTheDocument()
  })

  it('should submit login form with valid credentials', async () => {
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    const accountInput = screen.getByPlaceholderText('手机号 / 邮箱')
    const passwordInput = screen.getByPlaceholderText('密码')
    const submitBtn = screen.getByText('登 录')

    await user.type(accountInput, 'admin@example.com')
    await user.type(passwordInput, 'Admin123')
    await user.click(submitBtn)

    // Should trigger successful login
    await waitFor(() => {
      const state = useAuthStore.getState()
      expect(state.isAuthenticated).toBe(true)
      expect(state.token).toBe('mock-jwt-token')
    })
  })

  it('should show error on failed login', async () => {
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    const accountInput = screen.getByPlaceholderText('手机号 / 邮箱')
    const passwordInput = screen.getByPlaceholderText('密码')
    const submitBtn = screen.getByText('登 录')

    await user.type(accountInput, 'bad@example.com')
    await user.type(passwordInput, 'wrongpass')
    await user.click(submitBtn)

    // Should show error message
    await waitFor(() => {
      // The error message should appear (either from the server or default)
      const errorElements = document.querySelectorAll('.ant-alert-error')
      expect(errorElements.length).toBeGreaterThan(0)
    })
  })

  it('should navigate to register tab when clicking register', async () => {
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    await user.click(screen.getByText('注册'))

    expect(screen.getByText('创建账号')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('手机号')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('邮箱')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('昵称')).toBeInTheDocument()
  })

  it('should navigate to reset tab when clicking reset tab', async () => {
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    // Click the reset tab button (not the link)
    const resetTabButton = screen.getAllByText('重置密码')[0]
    await user.click(resetTabButton)

    expect(screen.getByText('通过邮箱或手机号重置密码')).toBeInTheDocument()
  })

  it('should navigate to reset when clicking forgot password link', async () => {
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    await user.click(screen.getByText('忘记密码？'))

    // Should switch to reset form
    expect(screen.getByText('通过邮箱或手机号重置密码')).toBeInTheDocument()
  })

  it('should show brand information', () => {
    renderWithProviders(<LoginPage />)

    expect(screen.getByText('CSERGY')).toBeInTheDocument()
    expect(screen.getByText('辰烁科技')).toBeInTheDocument()
  })

  it('should show feature descriptions', () => {
    renderWithProviders(<LoginPage />)

    expect(screen.getByText('云端集中监控')).toBeInTheDocument()
    expect(screen.getByText('智能告警引擎')).toBeInTheDocument()
    expect(screen.getByText('深度数据分析')).toBeInTheDocument()
  })

  it('should show link to register from login tab', () => {
    renderWithProviders(<LoginPage />)

    expect(screen.getByText('还没有账号？')).toBeInTheDocument()
    expect(screen.getByText('立即注册')).toBeInTheDocument()
  })

  it('should show code login entry link in password login form', () => {
    renderWithProviders(<LoginPage />)

    expect(screen.getByText('验证码登录')).toBeInTheDocument()
  })

  it('should enter code login view with phone channel by default and switch to email channel', async () => {
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    await user.click(screen.getByText('验证码登录'))

    // 默认手机号短信通道：存在手机号输入、验证码输入与发码按钮（修复旧版缺验证码输入框的缺陷）
    expect(screen.getByText('手机号短信')).toBeInTheDocument()
    expect(screen.getByText('邮箱验证码')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('手机号')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('验证码')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '发送验证码' })).toBeInTheDocument()

    // 切换到邮箱验证码通道
    await user.click(screen.getByText('邮箱验证码'))
    expect(screen.getByPlaceholderText('邮箱')).toBeInTheDocument()
    expect(screen.queryByPlaceholderText('手机号')).not.toBeInTheDocument()
  })

  it('should show error when sending sms code without phone number', async () => {
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    await user.click(screen.getByText('验证码登录'))
    await user.click(screen.getByRole('button', { name: '发送验证码' }))

    await waitFor(() => {
      expect(screen.getByText('请先输入手机号')).toBeInTheDocument()
    })
  })

  it('should login with phone verification code', async () => {
    useAuthStore.getState().logout()
    server.use(
      http.post('/api/v1/auth/phone-code-login', () => {
        return HttpResponse.json(mockLoginResponse)
      }),
    )
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    await user.click(screen.getByText('验证码登录'))
    await user.type(screen.getByPlaceholderText('手机号'), '13800000001')
    await user.type(screen.getByPlaceholderText('验证码'), '123456')
    await user.click(screen.getByRole('button', { name: '手机号登录' }))

    await waitFor(() => {
      const state = useAuthStore.getState()
      expect(state.isAuthenticated).toBe(true)
      expect(state.token).toBe('mock-jwt-token')
    })
  })

  it('should reset password via phone channel', async () => {
    server.use(
      http.post('/api/v1/auth/reset-password', () => {
        return HttpResponse.json({ code: 0, message: 'success', data: null })
      }),
    )
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    // 切到重置 Tab 并选择手机号重置方式
    await user.click(screen.getAllByText('重置密码')[0])
    await user.click(screen.getByText('手机号重置'))

    expect(screen.getByPlaceholderText('手机号')).toBeInTheDocument()
    await user.type(screen.getByPlaceholderText('手机号'), '13800000001')
    await user.type(screen.getByPlaceholderText('验证码'), '123456')
    await user.type(screen.getByPlaceholderText('新密码'), 'Admin123')
    await user.type(screen.getByPlaceholderText('确认新密码'), 'Admin123')

    // 提交按钮与主 Tab 按钮同名，取 DOM 靠后的表单提交按钮
    const submitBtn = screen.getAllByRole('button', { name: '重置密码' }).pop()!
    await user.click(submitBtn)

    // 重置成功后回到登录视图
    await waitFor(() => {
      expect(screen.getByText('欢迎回来')).toBeInTheDocument()
    })
  })
})
