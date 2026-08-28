import { beforeEach, describe, it, expect, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { useLocation } from 'react-router-dom'
import { server } from '@/test/mocks/server'
import { mockLoginResponse } from '@/test/mocks/data'
import { renderWithProviders } from '@/test/test-utils'
import LoginPage from './index'
import useAuthStore from '@/stores/authStore'
import useLocaleStore from '@/stores/localeStore'

// Mock the SliderCaptchaModal to avoid complex rendering
vi.mock('@/components/SliderCaptcha/SliderCaptchaModal', () => ({
  default: ({ open, onSuccess }: { open: boolean; onSuccess: (token: string) => void }) => (
    open ? <button onClick={() => onSuccess('mock-captcha-token')}>完成滑块验证</button> : null
  ),
}))

const LocationObserver = () => {
  const location = useLocation()
  return <div data-testid="location-path">{location.pathname}</div>
}
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

  it('should render password login tab and code login tab only', () => {
    renderWithProviders(<LoginPage />)

    expect(screen.getByText('密码登录')).toBeInTheDocument()
    expect(screen.getByText('验证码登录')).toBeInTheDocument()
    // 注册 / 重置密码为独立视图（链接触发），不在 Tab 栏
    expect(screen.queryByText('注册')).not.toBeInTheDocument()
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
    // 组件 i18n 文案为「记住密码」（zh remember）
    expect(screen.getByText('记住密码')).toBeInTheDocument()
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

  it('should switch to register view with mainland china phone form by default', async () => {
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    await user.click(screen.getByText('立即注册'))

    // 表单区切换为注册视图：标题 + 默认中国大陆手机注册表单
    expect(screen.getByText('创建账号')).toBeInTheDocument()
    expect(screen.getByText('注册新账户开始使用')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('手机号')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('验证码')).toBeInTheDocument()
    expect(screen.getByText('中国 (CN)')).toBeInTheDocument()
    // Tab 栏在注册视图隐藏
    expect(screen.queryByText('密码登录')).not.toBeInTheDocument()
  })

  it('should submit phone register with selected country code', async () => {
    let capturedBody: Record<string, unknown> | undefined
    server.use(
      http.post('/api/v1/auth/register', async ({ request }) => {
        capturedBody = (await request.json()) as Record<string, unknown>
        return HttpResponse.json({ code: 0, message: 'success', data: { token: 't', user: { id: 9, nickname: 'u' } } })
      }),
    )
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    await user.click(screen.getByText('立即注册'))
    await user.type(screen.getByPlaceholderText('手机号'), '13800000099')
    await user.type(screen.getByPlaceholderText('验证码'), '123456')
    await user.type(screen.getByPlaceholderText('密码'), 'Admin123')
    await user.type(screen.getByPlaceholderText('确认密码'), 'Admin123')
    await user.click(screen.getByRole('button', { name: '注 册' }))

    await waitFor(() => {
      expect(capturedBody).toBeDefined()
    })
    // 默认选中中国大陆，注册请求必须携带国家代码供后端落库
    expect(capturedBody).toMatchObject({ phone: '13800000099', country: 'CN' })
  })

  it('should automatically login and navigate after phone registration', async () => {
    useAuthStore.getState().logout()
    server.use(
      http.post('/api/v1/auth/register', () => {
        return HttpResponse.json({
          code: 0,
          message: 'success',
          data: {
            access_token: 'registered-access-token',
            refresh_token: 'registered-refresh-token',
            user: { id: 9, phone: '13800000099', nickname: 'u', status: 1 },
            permissions: ['dashboard:view'],
          },
        })
      }),
    )
    const user = userEvent.setup()
    renderWithProviders(<><LoginPage /><LocationObserver /></>)

    await user.click(screen.getByText('立即注册'))
    await user.type(screen.getByPlaceholderText('手机号'), '13800000099')
    await user.type(screen.getByPlaceholderText('验证码'), '123456')
    await user.type(screen.getByPlaceholderText('密码'), 'Admin123')
    await user.type(screen.getByPlaceholderText('确认密码'), 'Admin123')
    await user.click(screen.getByRole('button', { name: '注 册' }))

    await waitFor(() => {
      const state = useAuthStore.getState()
      expect(state.isAuthenticated).toBe(true)
      expect(state.token).toBe('registered-access-token')
      expect(state.refreshToken).toBe('registered-refresh-token')
      expect(screen.getByTestId('location-path')).toHaveTextContent('/dashboard')
    })
  })
  it('should return to login view from register view via login link', async () => {
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    await user.click(screen.getByText('立即注册'))
    expect(screen.getByText('创建账号')).toBeInTheDocument()

    await user.click(screen.getByText('立即登录'))

    // 回到登录视图：标题恢复 + Tab 栏恢复
    expect(screen.getByText('欢迎回来')).toBeInTheDocument()
    expect(screen.getByText('密码登录')).toBeInTheDocument()
  })

  it('should switch to reset view when clicking forgot password link', async () => {
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    await user.click(screen.getByText('忘记密码？'))

    // 表单区切换为重置视图：标题 + 邮箱/手机号双通道 Segmented
    expect(screen.getAllByText('重置密码').length).toBeGreaterThanOrEqual(1)
    expect(screen.getByText('通过邮箱或手机号重置密码')).toBeInTheDocument()
    expect(screen.getByText('邮箱重置')).toBeInTheDocument()
    expect(screen.getByText('手机号重置')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('注册时使用的邮箱')).toBeInTheDocument()
    // Tab 栏在重置视图隐藏
    expect(screen.queryByText('密码登录')).not.toBeInTheDocument()
  })

  it('should show brand information', () => {
    renderWithProviders(<LoginPage />)

    expect(screen.getByText('CSERGY')).toBeInTheDocument()
    expect(screen.getByText('辰烁科技')).toBeInTheDocument()
  })

  it('should show feature descriptions', () => {
    renderWithProviders(<LoginPage />)

    expect(screen.getByText('云端集中监控')).toBeInTheDocument()
    expect(screen.getByText('远程设备管理')).toBeInTheDocument()
    expect(screen.getByText('深度数据分析')).toBeInTheDocument()
  })

  it('should show link to register from login tab', () => {
    renderWithProviders(<LoginPage />)

    expect(screen.getByText('还没有账号？')).toBeInTheDocument()
    expect(screen.getByText('立即注册')).toBeInTheDocument()
  })

  it('should not show code login link in password login form', () => {
    renderWithProviders(<LoginPage />)

    // 「验证码登录」仅存在于顶部 Tab 栏，密码表单内不再重复出现
    expect(screen.getAllByText('验证码登录').length).toBe(1)
  })

  it('should enter code login view with phone channel by default and switch to email channel', async () => {
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    // 点击 Tab 栏的「验证码登录」（唯一）
    await user.click(screen.getByText('验证码登录'))

    // 默认手机通道：Segmented 显示 手机号 / 邮箱，存在手机号输入、验证码输入与发码按钮
    expect(screen.getByText('手机号')).toBeInTheDocument()
    expect(screen.getByText('邮箱')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('手机号')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('验证码')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '发送验证码' })).toBeInTheDocument()

    // 切换到邮箱通道
    await user.click(screen.getByText('邮箱'))
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

  it('should show an immediate error when sending a login code to an unregistered phone', async () => {
    useAuthStore.getState().logout()
    server.use(
      http.post('/api/v1/auth/send-code', () => {
        return HttpResponse.json({ code: 4001, message: '该手机号未注册' })
      }),
    )
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    await user.click(screen.getByText('验证码登录'))
    await user.type(screen.getByPlaceholderText('手机号'), '13800000099')
    await user.click(screen.getByRole('button', { name: '发送验证码' }))
    await user.click(screen.getByRole('button', { name: '完成滑块验证' }))

    await waitFor(() => {
      expect(screen.getByText('该手机号未注册')).toBeInTheDocument()
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

  it('should reset password via phone channel in reset view', async () => {
    server.use(
      http.post('/api/v1/auth/reset-password', () => {
        return HttpResponse.json({ code: 0, message: 'success', data: null })
      }),
    )
    const user = userEvent.setup()
    renderWithProviders(<LoginPage />)

    // 切换到重置视图并选择手机号重置方式
    await user.click(screen.getByText('忘记密码？'))
    await user.click(screen.getByText('手机号重置'))

    expect(screen.getByPlaceholderText('手机号')).toBeInTheDocument()
    await user.type(screen.getByPlaceholderText('手机号'), '13800000001')
    await user.type(screen.getByPlaceholderText('验证码'), '123456')
    await user.type(screen.getByPlaceholderText('新密码'), 'Admin123')
    await user.type(screen.getByPlaceholderText('确认新密码'), 'Admin123')

    // 视图内提交按钮
    const submitBtn = screen.getAllByRole('button', { name: '重置密码' }).pop()!
    await user.click(submitBtn)

    // 重置成功后显示成功提示，自动切回登录视图
    await waitFor(() => {
      expect(screen.getByText('密码重置成功，请登录')).toBeInTheDocument()
    }, { timeout: 3000 })
    expect(screen.getByText('欢迎回来')).toBeInTheDocument()
  })
})
