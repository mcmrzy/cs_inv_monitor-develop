import { beforeEach, describe, it, expect, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
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

  it('should show remember me checkbox', () => {
    renderWithProviders(<LoginPage />)
    expect(screen.getByText('记住我')).toBeInTheDocument()
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

    expect(screen.getByText('通过邮箱重置密码')).toBeInTheDocument()
  })

  it('should navigate to reset when clicking forgot password link', async () => {
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    await user.click(screen.getByText('忘记密码？'))

    // Should switch to reset form
    expect(screen.getByText('通过邮箱重置密码')).toBeInTheDocument()
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
})
