import { useState, useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { Form, Input, Button, Checkbox, App, Space, Alert, Dropdown, Segmented, Select } from 'antd'
import { UserOutlined, LockOutlined, MailOutlined, PhoneOutlined, SafetyOutlined, CloudOutlined, LineChartOutlined, GlobalOutlined, ApiOutlined } from '@ant-design/icons'
import useAuthStore from '@/stores/authStore'
import useLocaleStore from '@/stores/localeStore'
import api from '@/services/api'
import type { User } from '@/types'
import countriesList from '../../utils/continentsData'
import SliderCaptchaModal from '@/components/SliderCaptcha/SliderCaptchaModal'

// Maps the backend user object (snake_case is_system_admin) to the frontend User type.
function mapBackendUser(raw: Record<string, unknown>): User {
  return {
    ...(raw as unknown as User),
    isSystemAdmin: Boolean(raw.is_system_admin ?? raw.isSystemAdmin ?? (raw.role === 0)),
  }
}

// 登录背景图片（放在public目录，不需要import）
const loginBackgrounds = [
  '/images/login/login-bg-1.jpg',
  '/images/login/login-bg-2.jpg',
  '/images/login/login-bg-3.jpg',
  '/images/login/login-bg-4.jpg',
  '/images/login/login-bg-5.jpg',
  '/images/login/login-bg-6.jpg',
  '/images/login/login-bg-7.jpg',
  '/images/login/login-bg-8.jpg',
  '/images/login/login-bg-9.jpg',
]
const getRandomBg = () => loginBackgrounds[Math.floor(Math.random() * loginBackgrounds.length)]

type ActiveTab = 'login' | 'loginByCode' | 'register' | 'reset'

// 从洲与国家映射中提取所有国家选项（扁平化数组）
const flattenedCountries = countriesList.flatMap((continent: any) => 
  continent.countries.map((c: any) => ({ value: c.code, label: `${c.name} (${c.code})`, countryName: c.name }))
)
const getCountryName = (value: string) => {
  const found = flattenedCountries.find(c => c.value === value)
  return found?.countryName || ''
}
type Lang = 'zh' | 'en'

const i18n: Record<Lang, Record<string, string>> = {
  zh: {
    brand: '辰烁科技', brandSub: 'CSERGY', title: '光伏逆变器\n智能监控平台',
    subtitle: '一站式管理您的光伏逆变器设备',
    f1Title: '云端集中监控', f1Desc: '实时采集设备数据，多电站统一管理',
    f2Title: '远程设备管理', f2Desc: '远程配置与控制，设备状态实时掌握',
    f3Title: '深度数据分析', f3Desc: '发电效率统计，设备性能对比分析',
    welcome: '欢迎回来', createAcc: '创建账号', resetPwd: '重置密码',
    welcomeSub: '登录您的账户以继续', createSub: '注册新账户开始使用', resetSub: '通过邮箱或手机号重置密码',
    login: '密码登录', loginByCode: '验证码登录',
    account: '手机号 / 邮箱', password: '密码', remember: '记住密码', forgot: '忘记密码？',
    submitLogin: '登 录', noAccount: '还没有账号？', goRegister: '立即注册',
    phone: '手机号', email: '邮箱', code: '验证码', sendCode: '发送验证码', resendCode: 's 后重发',
    loginByPhoneCode: '手机号登录', loginByEmailCode: '邮箱登录',
    usePwdLogin: '密码登录',
    resetChannelEmail: '邮箱重置', resetChannelPhone: '手机号重置',
    nicknameOptional: '昵称（选填）',
    nickname: '昵称', confirmPassword: '确认密码', newPassword: '新密码', confirmNewPwd: '确认新密码',
    submitRegister: '注 册', hasAccount: '已有账号？', goLogin: '立即登录',
    submitReset: '重置密码', goBack: '返回登录', emailPlaceholder: '注册时使用的邮箱',
    footer: '© 2026 辰烁科技 · 光伏逆变器智能监控平台',
    errLogin: '登录失败，请检查手机号/邮箱和密码是否正确',
    errRegister: '注册失败，请检查信息后重试',
    errReset: '重置失败，请检查邮箱和验证码是否正确',
    errSendCode: '验证码发送失败，请稍后重试',
    errEmailFirst: '请先输入邮箱',
    errPwdMismatch: '两次输入的密码不一致',
    successLogin: '登录成功', successRegister: '注册成功，请登录', successReset: '密码重置成功，请登录', successCodeSent: '验证码已发送到邮箱',
    errEmailFormat: '邮箱格式不正确', errPhoneFormat: '手机号格式不正确', errPwdMin: '密码至少 6 位，需包含字母和数字',
    errPhoneFirst: '请先输入手机号', successCodeSentPhone: '验证码已发送到手机',
    captchaRequired: '请完成验证后重试',
    errUserNotFound: '用户不存在或账号未注册', errAccountDisabled: '账户已禁用', errWrongPassword: '密码错误',
    errPhoneRegistered: '该手机号已注册', errCodeInvalid: '验证码错误或已过期', errAlreadyRegistered: '该账号已注册',
    errRequestFailed: '请求失败，请稍后重试',
  },
  en: {
    brand: 'CHENSHUO', brandSub: 'TECHNOLOGY', title: 'Solar Inverter\nSmart Monitoring Platform',
    subtitle: 'All-in-one inverter management',
    f1Title: 'Cloud Monitoring', f1Desc: 'Real-time data, multi-station management',
    f2Title: 'Remote Device Mgmt', f2Desc: 'Remote config & control, real-time device status',
    f3Title: 'Data Analytics', f3Desc: 'Generation stats, device performance comparison',
    welcome: 'Welcome Back', createAcc: 'Create Account', resetPwd: 'Reset Password',
    welcomeSub: 'Sign in to your account', createSub: 'Register a new account', resetSub: 'Reset via email or phone',
    login: 'Password Login', loginByCode: 'Code Login',
    account: 'Phone / Email', password: 'Password', remember: 'Remember password', forgot: 'Forgot password?',
    submitLogin: 'Sign In', noAccount: "Don't have an account? ", goRegister: 'Register',
    phone: 'Phone', email: 'Email', code: 'Verification Code', sendCode: 'Send Code', resendCode: 's',
    loginByPhoneCode: 'Phone Login', loginByEmailCode: 'Email Login',
    usePwdLogin: 'Password Login',
    resetChannelEmail: 'Email', resetChannelPhone: 'Phone',
    nicknameOptional: 'Nickname (optional)',
    nickname: 'Nickname', confirmPassword: 'Confirm Password', newPassword: 'New Password', confirmNewPwd: 'Confirm New Password',
    submitRegister: 'Sign Up', hasAccount: 'Already have an account? ', goLogin: 'Sign In',
    submitReset: 'Reset Password', goBack: 'Back to Login', emailPlaceholder: 'Your registered email',
    footer: '© 2026 CSERGY · Solar Inverter Smart Monitoring Platform',
    errLogin: 'Login failed. Please check your phone/email and password.',
    errRegister: 'Registration failed. Please check your info and try again.',
    errReset: 'Reset failed. Please check your email and verification code.',
    errSendCode: 'Failed to send code. Please try again later.',
    errEmailFirst: 'Please enter your email first',
    errPwdMismatch: 'Passwords do not match',
    successLogin: 'Login successful', successRegister: 'Registered! Please sign in.', successReset: 'Password reset! Please sign in.', successCodeSent: 'Code sent to your email',
    errEmailFormat: 'Invalid email format', errPhoneFormat: 'Invalid phone number', errPwdMin: 'At least 6 chars with letters and numbers',
    errPhoneFirst: 'Please enter your phone number first', successCodeSentPhone: 'Code sent to your phone',
    captchaRequired: 'Complete the security verification and try again.',
    errUserNotFound: 'User not found or account is not registered', errAccountDisabled: 'This account is disabled', errWrongPassword: 'Incorrect password',
    errPhoneRegistered: 'This phone number is already registered', errCodeInvalid: 'The verification code is invalid or expired', errAlreadyRegistered: 'This account is already registered',
    errRequestFailed: 'Request failed. Please try again later.',
  },
}

const LoginPage: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [activeTab, setActiveTab] = useState<ActiveTab>('login')
  const [countdown, setCountdown] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const [captchaOpen, setCaptchaOpen] = useState(false)
  const [codeChannel, setCodeChannel] = useState<'phone' | 'email'>('phone')
  const [resetChannel, setResetChannel] = useState<'email' | 'phone'>('email')
  const [bgImage] = useState(() => getRandomBg())
  const captchaResolveRef = useRef<((token: string) => void) | null>(null)
  const captchaRejectRef = useRef<((reason?: any) => void) | null>(null)
  const { lang, setLang } = useLocaleStore()
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const navigate = useNavigate()
  const { login } = useAuthStore()
  const { message } = App.useApp()
  const [registerForm] = Form.useForm()
  const [loginForm] = Form.useForm()
  const [phoneCodeForm] = Form.useForm()
  const [emailCodeForm] = Form.useForm()
  const [resetForm] = Form.useForm()
  const [phoneResetForm] = Form.useForm()
  const [countryCode, setCountryCode] = useState<'cn' | 'overseas'>('cn')
  const [phoneRegisterForm] = Form.useForm()
  const [selectedCountryCode, setSelectedCountryCode] = useState<'CN' | string>('CN') // 默认中国

  // 从 localStorage 读取保存的账号和密码并自动填充
  useEffect(() => {
    const savedAccount = localStorage.getItem('remembered_account')
    const savedPassword = localStorage.getItem('remembered_password')
    if (savedAccount) {
      loginForm.setFieldsValue({ account: savedAccount, password: savedPassword || '', remember: true })
    }
  }, [loginForm])

  const t = i18n[lang]
  const localizeAuthError = (payload: any, fallback: string) => {
    const byCode: Record<number, string> = {
      4001: t.errUserNotFound,
      4002: t.errAccountDisabled,
      4003: t.errWrongPassword,
      4004: t.errPhoneRegistered,
      4005: t.errCodeInvalid,
      4008: t.errEmailFormat,
      4009: t.errAlreadyRegistered,
      4010: t.errRequestFailed,
      4032: t.captchaRequired,
    }
    const localized = byCode[Number(payload?.code)]
    return localized || payload?.message || fallback
  }

  useEffect(() => {
    if (countdown > 0) {
      timerRef.current = setInterval(() => {
        setCountdown((prev) => { if (prev <= 1) { clearInterval(timerRef.current!); return 0 }; return prev - 1 })
      }, 1000)
    }
    return () => { if (timerRef.current) clearInterval(timerRef.current) }
  }, [countdown])

  const showError = (msg: string) => { setError(msg); setTimeout(() => setError(null), 6000) }

  // 显示验证码弹窗，返回 Promise
  const showCaptcha = (): Promise<string> => {
    return new Promise((resolve, reject) => {
      captchaResolveRef.current = resolve
      captchaRejectRef.current = reject
      setCaptchaOpen(true)
    })
  }

  // 验证码验证成功
  const onCaptchaSuccess = (token: string) => {
    setCaptchaOpen(false)
    if (captchaResolveRef.current) {
      captchaResolveRef.current(token)
      captchaResolveRef.current = null
      captchaRejectRef.current = null
    }
  }

  // 验证码取消
  const onCaptchaCancel = () => {
    setCaptchaOpen(false)
    if (captchaRejectRef.current) {
      captchaRejectRef.current(new Error('用户取消验证'))
      captchaResolveRef.current = null
      captchaRejectRef.current = null
    }
  }

  // 执行登录请求
  const performLogin = async (values: { account: string; password: string }, captchaToken?: string) => {
    setLoading(true); setError(null)
    try {
      const headers: Record<string, string> = {}
      if (captchaToken) {
        headers['X-Captcha-Token'] = captchaToken
      }
      const res = await api.post('/auth/login', { account: values.account, password: values.password }, { headers })
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) {
        // 如果需要验证码（错误码 4032），弹出验证码
        if (d.code === 4032) {
          try {
            const token = await showCaptcha()
            await performLogin(values, token)
            return
          } catch {
            showError(t.captchaRequired)
            return
          }
        }
        showError(localizeAuthError(d, t.errLogin))
        return
      }
      const data = (d?.data ?? d) as { token?: string; accessToken?: string; access_token?: string; refresh_token?: string; refreshToken?: string; permissions?: string[]; user: User }
      if (!data.user) { showError(t.errLogin); return }
      login(data.token ?? data.accessToken ?? data.access_token ?? '', data.refresh_token ?? data.refreshToken ?? '', mapBackendUser(data.user as unknown as Record<string, unknown>), data.permissions ?? [])
      message.success(t.successLogin)
      navigate('/dashboard', { replace: true })
    } catch (err: any) {
      const errData = err?.response?.data
      // 如果需要验证码，弹出验证码
      if (errData?.code === 4032) {
        try {
          const token = await showCaptcha()
          await performLogin(values, token)
          return
        } catch {
          showError(t.captchaRequired)
          return
        }
      }
      showError(localizeAuthError(errData, t.errLogin))
    }
    finally { setLoading(false) }
  }

  // 登录按钮点击
  const onLogin = async (values: { account: string; password: string; remember?: boolean }) => {
    await performLogin(values)
    // 登录成功后保存账号和密码（performLogin 成功会 navigate，所以这里只在未跳转时执行）
    if (values.remember) {
      localStorage.setItem('remembered_account', values.account)
      localStorage.setItem('remembered_password', values.password)
    } else {
      localStorage.removeItem('remembered_account')
      localStorage.removeItem('remembered_password')
    }
  }

  // 海外邮箱注册（仅需邮箱 + 邮箱验证码 + 密码，昵称选填）
  const onRegister = async (values: { email: string; password: string; nickname?: string; code: string }) => {
    setLoading(true); setError(null)
    try {
      const payload: Record<string, any> = {
        email: values.email,
        password: values.password,
        code: values.code,
        country: selectedCountryCode,
      }
      if (values.nickname) payload.nickname = values.nickname
      const res = await api.post('/auth/email-register', payload)
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) { showError(localizeAuthError(d, t.errRegister)); return }
      message.success(t.successRegister); setActiveTab('login')
    } catch (err: any) { showError(localizeAuthError(err?.response?.data, t.errRegister)) }
    finally { setLoading(false) }
  }

  // 中国大陆手机号注册（手机号 + 短信验证码 + 密码）
  const onPhoneRegister = async (values: { phone: string; code: string; password: string }) => {
    setLoading(true); setError(null)
    try {
      const res = await api.post('/auth/register', { ...values, country: selectedCountryCode })
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) { showError(localizeAuthError(d, t.errRegister)); return }
      message.success(t.successRegister); setActiveTab('login')
    } catch (err: any) { showError(localizeAuthError(err?.response?.data, t.errRegister)) }
    finally { setLoading(false) }
  }

  const onResetPassword = async (values: { email: string; code: string; new_password: string }) => {
    setLoading(true); setError(null)
    try {
      const res = await api.post('/auth/email-reset-password', values)
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) { showError(localizeAuthError(d, t.errReset)); return }
      message.success(t.successReset); setActiveTab('login')
    } catch (err: any) { showError(localizeAuthError(err?.response?.data, t.errReset)) }
    finally { setLoading(false) }
  }

  // 手机号验证码重置密码
  const onPhoneResetPassword = async (values: { phone: string; code: string; new_password: string }) => {
    setLoading(true); setError(null)
    try {
      const res = await api.post('/auth/reset-password', values)
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) { showError(localizeAuthError(d, t.errReset)); return }
      message.success(t.successReset); setActiveTab('login')
    } catch (err: any) { showError(localizeAuthError(err?.response?.data, t.errReset)) }
    finally { setLoading(false) }
  }

  // 手机号验证码登录
  const onPhoneCodeLogin = async (values: { phone: string; code: string }) => {
    setLoading(true); setError(null)
    try {
      const res = await api.post('/auth/phone-code-login', values)
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) { showError(localizeAuthError(d, t.errLogin)); return }
      const data = (d?.data ?? d) as { token?: string; accessToken?: string; access_token?: string; refresh_token?: string; refreshToken?: string; permissions?: string[]; user: User }
      if (!data.user) { showError(t.errLogin); return }
      login(data.token ?? data.accessToken ?? data.access_token ?? '', data.refresh_token ?? data.refreshToken ?? '', mapBackendUser(data.user as unknown as Record<string, unknown>), data.permissions ?? [])
      message.success(t.successLogin)
      navigate('/dashboard', { replace: true })
    } catch (err: any) { showError(localizeAuthError(err?.response?.data, t.errLogin)) }
    finally { setLoading(false) }
  }

  // 邮箱验证码登录
  const onEmailCodeLogin = async (values: { email: string; code: string }) => {
    setLoading(true); setError(null)
    try {
      const res = await api.post('/auth/email-code-login', values)
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) { showError(localizeAuthError(d, t.errLogin)); return }
      const data = (d?.data ?? d) as { token?: string; accessToken?: string; access_token?: string; refresh_token?: string; refreshToken?: string; permissions?: string[]; user: User }
      if (!data.user) { showError(t.errLogin); return }
      login(data.token ?? data.accessToken ?? data.access_token ?? '', data.refresh_token ?? data.refreshToken ?? '', mapBackendUser(data.user as unknown as Record<string, unknown>), data.permissions ?? [])
      message.success(t.successLogin)
      navigate('/dashboard', { replace: true })
    } catch (err: any) { showError(localizeAuthError(err?.response?.data, t.errLogin)) }
    finally { setLoading(false) }
  }

  // 发送邮箱验证码（需要先完成滑块验证）
  const sendEmailCode = async (email: string, type: 'register' | 'reset' | 'login') => {
    if (countdown > 0) return
    try {
      // 先弹出滑块验证
      const captchaToken = await showCaptcha()
      const apiType = type === 'reset' ? 'reset_password' : type
      const headers = { 'X-Captcha-Token': captchaToken }
      const res = await api.post('/auth/send-email-code', { email, type: apiType }, { headers })
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) { showError(localizeAuthError(d, t.errSendCode)); return }
      message.success(t.successCodeSent); setCountdown(60)
    } catch (err: any) {
      if (err?.message === '用户取消验证') return
      showError(localizeAuthError(err?.response?.data, t.errSendCode))
    }
  }

  // 发送短信验证码（需要先完成滑块验证；type: login/register/reset_password）
  const sendSmsCode = async (phone: string, type: 'login' | 'reset' | 'register') => {
    if (countdown > 0) return
    try {
      // 先弹出滑块验证
      const captchaToken = await showCaptcha()
      const apiType = type === 'reset' ? 'reset_password' : type
      const headers = { 'X-Captcha-Token': captchaToken }
      const res = await api.post('/auth/send-code', { phone, type: apiType }, { headers })
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) { showError(localizeAuthError(d, t.errSendCode)); return }
      message.success(t.successCodeSentPhone); setCountdown(60)
    } catch (err: any) {
      if (err?.message === '用户取消验证') return
      showError(localizeAuthError(err?.response?.data, t.errSendCode))
    }
  }

  const inputStyle = { borderRadius: 10, height: 56, fontSize: 17 }

  const CodeButton = ({ field, type, form, channel }: { field: string; type: 'register' | 'reset' | 'login'; form: any; channel: 'email' | 'phone' }) => (
    <Button disabled={countdown > 0}
      onClick={() => {
        const val = form.getFieldValue(field)
        if (!val) { showError(channel === 'email' ? t.errEmailFirst : t.errPhoneFirst); return }
        if (channel === 'email') sendEmailCode(val, type)
        else sendSmsCode(val, type)
      }}
      style={{ height: 56, borderRadius: '0 10px 10px 0', borderColor: '#d9d9d9', minWidth: 110, fontSize: 15, color: countdown > 0 ? '#6b7280' : '#1677ff' }}>
      {countdown > 0 ? `${countdown}${t.resendCode}` : t.sendCode}
    </Button>
  )

  const langMenu = {
    items: [{ key: 'zh', label: '中文' }, { key: 'en', label: 'English' }],
    onClick: ({ key }: { key: string }) => setLang(key as Lang),
  }

  return (
    <div style={{
      minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center',
      backgroundImage: `url(${bgImage}), linear-gradient(135deg, #1a1f36 0%, #2d3561 100%)`,
      backgroundSize: 'cover', backgroundPosition: 'center', backgroundRepeat: 'no-repeat',
      padding: '40px 20px', position: 'relative',
    }}>
      {/* Light overlay for readability */}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(15, 23, 42, 0.3)' }} />

      {/* Frosted glass card */}
      <div style={{
        position: 'relative', zIndex: 1, width: '100%', maxWidth: 1060,
        borderRadius: 24, overflow: 'hidden',
        background: 'rgba(255, 255, 255, 0.12)',
        border: '1px solid rgba(255, 255, 255, 0.2)',
        boxShadow: '0 8px 48px rgba(0, 0, 0, 0.2), inset 0 1px 0 rgba(255, 255, 255, 0.15)',
        display: 'flex', minHeight: '78vh',
      }}>
        {/* Left - Brand */}
        <div style={{
          flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'flex-start',
          padding: '60px 48px 48px', position: 'relative',
          background: 'rgba(255, 255, 255, 0.06)',
          backdropFilter: 'blur(32px) saturate(1.3)',
          WebkitBackdropFilter: 'blur(32px) saturate(1.3)',
          borderRight: '1px solid rgba(255, 255, 255, 0.1)',
        }}>
          <div style={{ paddingTop: 4 }}>
            <div style={{ marginBottom: 36 }}>
              <span style={{ fontSize: 32, fontWeight: 800, color: '#fff', letterSpacing: 2 }}>CSERGY</span>
              <span style={{ fontSize: 32, fontWeight: 300, color: 'rgba(255,255,255,0.3)', margin: '0 8px' }}>|</span>
              <span style={{ fontSize: 32, fontWeight: 800, color: '#fff' }}>辰烁科技</span>
            </div>

            <div style={{ fontSize: 42, fontWeight: 700, color: '#fff', lineHeight: 1.25, marginBottom: 40, letterSpacing: '-0.5px', whiteSpace: 'pre-line', textShadow: '0 2px 12px rgba(0,0,0,0.15)' }}>{t.title}</div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 22, maxWidth: 400, marginBottom: 40 }}>
              {[
                { icon: <CloudOutlined />, title: t.f1Title, desc: t.f1Desc, color: '#93c5fd' },
                { icon: <ApiOutlined />, title: t.f2Title, desc: t.f2Desc, color: '#86efac' },
                { icon: <LineChartOutlined />, title: t.f3Title, desc: t.f3Desc, color: '#fcd34d' },
              ].map((f, i) => (
                <div key={i} style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
                  <div style={{ width: 42, height: 42, borderRadius: 10, flexShrink: 0, background: 'rgba(255,255,255,0.12)', backdropFilter: 'blur(8px)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: f.color, fontSize: 20, border: '1px solid rgba(255,255,255,0.1)' }}>{f.icon}</div>
                  <div>
                    <div style={{ fontSize: 16, fontWeight: 600, color: '#fff', marginBottom: 4 }}>{f.title}</div>
                    <div style={{ fontSize: 13, color: 'rgba(255,255,255,0.5)', lineHeight: 1.6 }}>{f.desc}</div>
                  </div>
                </div>
              ))}
            </div>

            <div style={{ fontSize: 15, color: 'rgba(255,255,255,0.55)', lineHeight: 1.8, maxWidth: 420, whiteSpace: 'pre-line' }}>{t.subtitle}</div>
          </div>
        </div>

        {/* Right - Form */}
        <div style={{
          width: 460, display: 'flex', flexDirection: 'column',
          background: 'rgba(255, 255, 255, 0.75)',
          backdropFilter: 'blur(20px)',
          WebkitBackdropFilter: 'blur(20px)',
        }}>
          {/* Top bar with language switcher */}
          <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '16px 24px' }}>
            <Dropdown menu={langMenu} placement="bottomRight">
              <Button type="text" icon={<GlobalOutlined style={{ fontSize: 18 }} />} style={{ color: '#64748b', fontSize: 15, height: 40, padding: '0 14px' }}>
                {lang === 'zh' ? 'English' : '中文'}
              </Button>
            </Dropdown>
          </div>

          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '0 36px 40px' }}>
            <div style={{ width: '100%', maxWidth: 360, animation: 'fadeInUp 0.4s ease-out' }}>
              {/* Header：随视图切换（登录 / 创建账号 / 重置密码） */}
              <div style={{ marginBottom: 24 }}>
                <div style={{ fontSize: 30, fontWeight: 700, color: '#0f172a', marginBottom: 6 }}>
                  {activeTab === 'register' ? t.createAcc : activeTab === 'reset' ? t.resetPwd : t.welcome}
                </div>
                <div style={{ color: '#475569', fontSize: 17 }}>
                  {activeTab === 'register' ? t.createSub : activeTab === 'reset' ? t.resetSub : t.welcomeSub}
                </div>
              </div>

              {/* Error */}
              {error && (
                <Alert message={error} type="error" showIcon closable onClose={() => setError(null)}
                  style={{ marginBottom: 16, borderRadius: 10, animation: 'fadeInUp 0.2s ease-out' }} />
              )}

              {/* Tab switcher（注册/重置视图隐藏） */}
              {(activeTab === 'login' || activeTab === 'loginByCode') && (
              <div style={{ display: 'flex', background: '#f1f5f9', borderRadius: 10, padding: 3, marginBottom: 24 }}>
                {([['login', t.login], ['loginByCode', t.loginByCode]] as const).map(([tab, label]) => (
                  <button key={tab} onClick={() => { setActiveTab(tab as ActiveTab); setCountdown(0); setError(null) }} style={{
                    flex: 1, padding: '10px 0', border: 'none', borderRadius: 8, cursor: 'pointer',
                    fontSize: 14, fontWeight: 500, transition: 'all 0.2s ease',
                    background: activeTab === tab ? '#fff' : 'transparent',
                    color: activeTab === tab ? '#1677ff' : '#475569',
                    boxShadow: activeTab === tab ? '0 1px 3px rgba(0,0,0,0.06)' : 'none',
                  }}>{label}</button>
                ))}
              </div>
              )}

              {/* Login */}
              {activeTab === 'login' && (
                <Form form={loginForm} name="login" onFinish={onLogin} size="large" initialValues={{ remember: true }}>
                  <Form.Item name="account" rules={[{ required: true, message: lang === 'zh' ? '请输入手机号或邮箱' : 'Phone or email required' }]}>
                    <Input prefix={<UserOutlined style={{ color: '#94a3b8' }} />} placeholder={t.account} style={inputStyle} />
                  </Form.Item>
                  <Form.Item name="password" rules={[{ required: true, message: lang === 'zh' ? '请输入密码' : 'Password required' }]}>
                    <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.password} style={inputStyle} />
                  </Form.Item>
                  <Form.Item>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                      <Form.Item name="remember" valuePropName="checked" noStyle><Checkbox>{t.remember}</Checkbox></Form.Item>
                      <a onClick={() => { setActiveTab('reset'); setCountdown(0); setError(null) }} style={{ color: '#1677ff', fontSize: 16, fontWeight: 500 }}>{t.forgot}</a>
                    </div>
                  </Form.Item>
                  <Form.Item>
                    <Button type="primary" htmlType="submit" loading={loading} block style={{ height: 56, borderRadius: 10, fontSize: 18, fontWeight: 600, background: 'linear-gradient(135deg, #0D47A1 0%, #1677ff 100%)', border: 'none', boxShadow: '0 2px 8px rgba(22,119,255,0.25)' }}>{t.submitLogin}</Button>
                  </Form.Item>
                  <div style={{ textAlign: 'center' }}>
                    <span style={{ color: '#475569', fontSize: 17 }}>{t.noAccount}</span>
                    <a onClick={() => { setActiveTab('register'); setCountryCode('cn'); setCountdown(0); setError(null) }} style={{ color: '#1677ff', marginLeft: 4, fontWeight: 500, fontSize: 17 }}>{t.goRegister}</a>
                  </div>
                </Form>
              )}

              {/* LoginByCode - 验证码登录（手机号短信 / 邮箱双通道） */}
              {activeTab === 'loginByCode' && (
                <div>
                  <Segmented
                    block
                    value={codeChannel}
                    onChange={(v) => { setCodeChannel(v as 'phone' | 'email'); setCountdown(0) }}
                    options={[
                      { label: t.phone, value: 'phone' },
                      { label: t.email, value: 'email' },
                    ]}
                    style={{ marginBottom: 24 }}
                  />
                  {codeChannel === 'phone' ? (
                    <Form form={phoneCodeForm} name="phoneCodeLogin" onFinish={onPhoneCodeLogin} size="large">
                      <Form.Item name="phone" rules={[{ required: true, message: lang === 'zh' ? '请输入手机号' : 'Phone required' }, { pattern: /^1[3-9]\d{9}$/, message: t.errPhoneFormat }]}>
                        <Input prefix={<PhoneOutlined style={{ color: '#94a3b8' }} />} placeholder={t.phone} style={inputStyle} />
                      </Form.Item>
                      <Form.Item>
                        <Space.Compact style={{ width: '100%' }}>
                          <Form.Item name="code" noStyle rules={[{ required: true, message: lang === 'zh' ? '请输入验证码' : 'Code required' }]}>
                            <Input prefix={<SafetyOutlined style={{ color: '#94a3b8' }} />} placeholder={t.code} style={{ ...inputStyle, borderRadius: '10px 0 0 10px' }} />
                          </Form.Item>
                          <CodeButton field="phone" type="login" form={phoneCodeForm} channel="phone" />
                        </Space.Compact>
                      </Form.Item>
                      <Form.Item>
                        <Button type="primary" htmlType="submit" loading={loading} block style={{ height: 56, borderRadius: 10, fontSize: 18, fontWeight: 600, background: 'linear-gradient(135deg, #0D47A1 0%, #1677ff 100%)', border: 'none', boxShadow: '0 2px 8px rgba(22,119,255,0.25)' }}>{t.loginByPhoneCode}</Button>
                      </Form.Item>
                    </Form>
                  ) : (
                    <Form form={emailCodeForm} name="emailCodeLogin" onFinish={onEmailCodeLogin} size="large">
                      <Form.Item name="email" rules={[{ required: true, message: lang === 'zh' ? '请输入邮箱' : 'Email required' }, { type: 'email', message: t.errEmailFormat }]}>
                        <Input prefix={<MailOutlined style={{ color: '#94a3b8' }} />} placeholder={t.email} style={inputStyle} />
                      </Form.Item>
                      <Form.Item>
                        <Space.Compact style={{ width: '100%' }}>
                          <Form.Item name="code" noStyle rules={[{ required: true, message: lang === 'zh' ? '请输入验证码' : 'Code required' }]}>
                            <Input prefix={<MailOutlined style={{ color: '#94a3b8' }} />} placeholder={t.code} style={{ ...inputStyle, borderRadius: '10px 0 0 10px' }} />
                          </Form.Item>
                          <CodeButton field="email" type="login" form={emailCodeForm} channel="email" />
                        </Space.Compact>
                      </Form.Item>
                      <Form.Item>
                        <Button type="primary" htmlType="submit" loading={loading} block style={{ height: 56, borderRadius: 10, fontSize: 18, fontWeight: 600, background: 'linear-gradient(135deg, #0D47A1 0%, #1677ff 100%)', border: 'none', boxShadow: '0 2px 8px rgba(22,119,255,0.25)' }}>{t.loginByEmailCode}</Button>
                      </Form.Item>
                    </Form>
                  )}
                  <div style={{ textAlign: 'center', marginTop: 8 }}>
                    <a onClick={() => { setActiveTab('login'); setCountdown(0) }} style={{ color: '#1677ff', fontWeight: 500, fontSize: 16 }}>{t.usePwdLogin}</a>
                  </div>
                  <div style={{ textAlign: 'center', marginTop: 16 }}>
                    <span style={{ color: '#475569', fontSize: 17 }}>{t.noAccount}</span>
                    <a onClick={() => { setActiveTab('register'); setCountryCode('cn'); setCountdown(0); setError(null) }} style={{ color: '#1677ff', marginLeft: 4, fontWeight: 500, fontSize: 17 }}>{t.goRegister}</a>
                  </div>
                </div>
              )}

              {/* 注册视图：国家/地区分流，中国大陆→手机号注册，海外→邮箱注册 */}
              {activeTab === 'register' && (
                <div>
                  {/* 国家/地区选择：可搜索的选择器 */}
                  <div style={{ marginBottom: 16 }}>
                    <div style={{ color: '#374151', fontSize: 14, fontWeight: 500, marginBottom: 8 }}>国家 / 地区</div>
                    <Select
                      showSearch
                      placeholder="选择国家/地区"
                      value={selectedCountryCode}
                      onChange={(value) => {
                        setSelectedCountryCode(value)
                        setCountdown(0)
                      }}
                      optionFilterProp="children"
                      filterOption={(input, option) =>
                        (option?.label ?? '').toLowerCase().includes(input.toLowerCase()) ||
                        (option?.value ?? '').toLowerCase().includes(input.toLowerCase())
                      }
                      options={flattenedCountries}
                      style={{ width: '100%' }}
                    />
                  </div>

                  {/* 中国大陆：手机号 + 短信验证码 + 密码 */}
                  {selectedCountryCode === 'CN' ? (
                    <Form form={phoneRegisterForm} name="phoneRegister" onFinish={onPhoneRegister} size="large">
                      <Form.Item name="phone" rules={[
                        { required: true, message: lang === 'zh' ? '请输入手机号' : 'Phone required' },
                        { pattern: /^1[3-9]\d{9}$/, message: t.errPhoneFormat }
                      ]}>
                        <Input prefix={<PhoneOutlined style={{ color: '#94a3b8' }} />} placeholder={t.phone} style={inputStyle} />
                      </Form.Item>
                      <Form.Item>
                        <Space.Compact style={{ width: '100%' }}>
                          <Form.Item name="code" noStyle rules={[
                            { required: true, message: lang === 'zh' ? '请输入验证码' : 'Code required' }
                          ]}>
                            <Input prefix={<SafetyOutlined style={{ color: '#94a3b8' }} />} placeholder={t.code} style={{ ...inputStyle, borderRadius: '10px 0 0 10px' }} />
                          </Form.Item>
                          <CodeButton field="phone" type="register" form={phoneRegisterForm} channel="phone" />
                        </Space.Compact>
                      </Form.Item>
                      <Form.Item name="password" rules={[
                        { required: true, message: lang === 'zh' ? '请输入密码' : 'Password required' },
                        { min: 6, message: t.errPwdMin },
                        { pattern: /^(?=.*[a-zA-Z])(?=.*\d).+$/, message: t.errPwdMin }
                      ]}>
                        <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.password} style={inputStyle} />
                      </Form.Item>
                      <Form.Item name="confirm_password" dependencies={['password']}
                        rules={[
                          { required: true, message: lang === 'zh' ? '请确认密码' : 'Confirm password' },
                          ({ getFieldValue }) => ({ validator(_, value) {
                            if (!value || getFieldValue('password') === value) return Promise.resolve()
                            return Promise.reject(new Error(t.errPwdMismatch))
                          }})
                        ]}>
                        <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.confirmPassword} style={inputStyle} />
                      </Form.Item>
                      <Button type="primary" htmlType="submit" loading={loading} block style={{ height: 50, borderRadius: 10, fontSize: 16, fontWeight: 600, background: 'linear-gradient(135deg, #0D47A1 0%, #1677ff 100%)', border: 'none', boxShadow: '0 2px 8px rgba(22,119,255,0.25)' }}>
                        {t.submitRegister}
                      </Button>
                      <div style={{ textAlign: 'center', marginTop: 12 }}>
                        <span style={{ color: '#475569', fontSize: 14 }}>{t.hasAccount}</span>
                        <a onClick={() => { setActiveTab('login'); setCountdown(0) }} style={{ color: '#1677ff', marginLeft: 4, fontWeight: 500, fontSize: 14 }}>{t.goLogin}</a>
                      </div>
                    </Form>
                  ) : (
                    /* 其他国家/地区：邮箱 + 邮箱验证码 + 密码 */
                    <Form form={registerForm} name="emailRegister" onFinish={onRegister} size="large">
                      <Form.Item name="email" rules={[
                        { required: true, message: lang === 'zh' ? '请输入邮箱' : 'Email required' },
                        { type: 'email', message: t.errEmailFormat }
                      ]}>
                        <Input prefix={<MailOutlined style={{ color: '#94a3b8' }} />} placeholder={t.email} style={inputStyle} />
                      </Form.Item>
                      <Form.Item>
                        <Space.Compact style={{ width: '100%' }}>
                          <Form.Item name="code" noStyle rules={[
                            { required: true, message: lang === 'zh' ? '请输入验证码' : 'Code required' }
                          ]}>
                            <Input prefix={<MailOutlined style={{ color: '#94a3b8' }} />} placeholder={t.code} style={{ ...inputStyle, borderRadius: '10px 0 0 10px' }} />
                          </Form.Item>
                          <CodeButton field="email" type="register" form={registerForm} channel="email" />
                        </Space.Compact>
                      </Form.Item>
                      <Form.Item name="password" rules={[
                        { required: true, message: lang === 'zh' ? '请输入密码' : 'Password required' },
                        { min: 6, message: t.errPwdMin },
                        { pattern: /^(?=.*[a-zA-Z])(?=.*\d).+$/, message: t.errPwdMin }
                      ]}>
                        <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.password} style={inputStyle} />
                      </Form.Item>
                      <Form.Item name="confirm_password" dependencies={['password']}
                        rules={[
                          { required: true, message: lang === 'zh' ? '请确认密码' : 'Confirm password' },
                          ({ getFieldValue }) => ({ validator(_, value) {
                            if (!value || getFieldValue('password') === value) return Promise.resolve()
                            return Promise.reject(new Error(t.errPwdMismatch))
                          }})
                        ]}>
                        <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.confirmPassword} style={inputStyle} />
                      </Form.Item>
                      <Button type="primary" htmlType="submit" loading={loading} block style={{ height: 50, borderRadius: 10, fontSize: 16, fontWeight: 600, background: 'linear-gradient(135deg, #0D47A1 0%, #1677ff 100%)', border: 'none', boxShadow: '0 2px 8px rgba(22,119,255,0.25)' }}>
                        {t.submitRegister}
                      </Button>
                      <div style={{ textAlign: 'center', marginTop: 12 }}>
                        <span style={{ color: '#475569', fontSize: 14 }}>{t.hasAccount}</span>
                        <a onClick={() => { setActiveTab('login'); setCountdown(0) }} style={{ color: '#1677ff', marginLeft: 4, fontWeight: 500, fontSize: 14 }}>{t.goLogin}</a>
                      </div>
                    </Form>
                  )}
                </div>
              )}

              {/* 重置密码视图：支持邮箱 / 手机号两种方式 */}
              {activeTab === 'reset' && (
                <div>
                  {/* 重置方式选择 */}
                  <div style={{ marginBottom: 16 }}>
                    <Segmented
                      block
                      value={resetChannel}
                      onChange={(v) => { setResetChannel(v as 'email' | 'phone'); setCountdown(0) }}
                      options={[
                        { label: t.resetChannelEmail, value: 'email' },
                        { label: t.resetChannelPhone, value: 'phone' },
                      ]}
                    />
                  </div>

                  {resetChannel === 'email' ? (
                    <Form form={resetForm} name="reset" onFinish={onResetPassword} size="large">
                      <Form.Item name="email" rules={[{ required: true, message: lang === 'zh' ? '请输入邮箱' : 'Email required' }, { type: 'email', message: t.errEmailFormat }]}>
                        <Input prefix={<MailOutlined style={{ color: '#94a3b8' }} />} placeholder={t.emailPlaceholder} style={inputStyle} />
                      </Form.Item>
                      <Form.Item>
                        <Space.Compact style={{ width: '100%' }}>
                          <Form.Item name="code" noStyle rules={[{ required: true, message: lang === 'zh' ? '请输入验证码' : 'Code required' }]}>
                            <Input prefix={<MailOutlined style={{ color: '#94a3b8' }} />} placeholder={t.code} style={{ ...inputStyle, borderRadius: '10px 0 0 10px' }} />
                          </Form.Item>
                          <CodeButton field="email" type="reset" form={resetForm} channel="email" />
                        </Space.Compact>
                      </Form.Item>
                      <Form.Item name="new_password" rules={[{ required: true, message: lang === 'zh' ? '请输入新密码' : 'New password required' }, { min: 6, message: t.errPwdMin }, { pattern: /^(?=.*[a-zA-Z])(?=.*\d).+$/, message: t.errPwdMin }]}>
                        <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.newPassword} style={inputStyle} />
                      </Form.Item>
                      <Form.Item name="confirm_new_password" dependencies={['new_password']}
                        rules={[{ required: true, message: lang === 'zh' ? '请确认新密码' : 'Confirm new password' }, ({ getFieldValue }) => ({ validator(_, value) { if (!value || getFieldValue('new_password') === value) return Promise.resolve(); return Promise.reject(new Error(t.errPwdMismatch)) } })]}>
                        <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.confirmNewPwd} style={inputStyle} />
                      </Form.Item>
                      <Button type="primary" htmlType="submit" loading={loading} block style={{ height: 50, borderRadius: 10, fontSize: 16, fontWeight: 600, background: 'linear-gradient(135deg, #0D47A1 0%, #1677ff 100%)', border: 'none', boxShadow: '0 2px 8px rgba(22,119,255,0.25)' }}>
                        {t.submitReset}
                      </Button>
                      <div style={{ textAlign: 'center', marginTop: 12 }}>
                        <a onClick={() => { setActiveTab('login'); setCountdown(0) }} style={{ color: '#1677ff', fontWeight: 500, fontSize: 14 }}>{t.goBack}</a>
                      </div>
                    </Form>
                  ) : (
                    <Form form={phoneResetForm} name="phoneReset" onFinish={onPhoneResetPassword} size="large">
                      <Form.Item name="phone" rules={[{ required: true, message: lang === 'zh' ? '请输入手机号' : 'Phone required' }, { pattern: /^1[3-9]\d{9}$/, message: t.errPhoneFormat }]}>
                        <Input prefix={<PhoneOutlined style={{ color: '#94a3b8' }} />} placeholder={t.phone} style={inputStyle} />
                      </Form.Item>
                      <Form.Item>
                        <Space.Compact style={{ width: '100%' }}>
                          <Form.Item name="code" noStyle rules={[{ required: true, message: lang === 'zh' ? '请输入验证码' : 'Code required' }]}>
                            <Input prefix={<SafetyOutlined style={{ color: '#94a3b8' }} />} placeholder={t.code} style={{ ...inputStyle, borderRadius: '10px 0 0 10px' }} />
                          </Form.Item>
                          <CodeButton field="phone" type="reset" form={phoneResetForm} channel="phone" />
                        </Space.Compact>
                      </Form.Item>
                      <Form.Item name="new_password" rules={[{ required: true, message: lang === 'zh' ? '请输入新密码' : 'New password required' }, { min: 6, message: t.errPwdMin }, { pattern: /^(?=.*[a-zA-Z])(?=.*\d).+$/, message: t.errPwdMin }]}>
                        <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.newPassword} style={inputStyle} />
                      </Form.Item>
                      <Form.Item name="confirm_new_password" dependencies={['new_password']}
                        rules={[{ required: true, message: lang === 'zh' ? '请确认新密码' : 'Confirm new password' }, ({ getFieldValue }) => ({ validator(_, value) { if (!value || getFieldValue('new_password') === value) return Promise.resolve(); return Promise.reject(new Error(t.errPwdMismatch)) } })]}>
                        <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.confirmNewPwd} style={inputStyle} />
                      </Form.Item>
                      <Button type="primary" htmlType="submit" loading={loading} block style={{ height: 50, borderRadius: 10, fontSize: 16, fontWeight: 600, background: 'linear-gradient(135deg, #0D47A1 0%, #1677ff 100%)', border: 'none', boxShadow: '0 2px 8px rgba(22,119,255,0.25)' }}>
                        {t.submitReset}
                      </Button>
                      <div style={{ textAlign: 'center', marginTop: 12 }}>
                        <a onClick={() => { setActiveTab('login'); setCountdown(0) }} style={{ color: '#1677ff', fontWeight: 500, fontSize: 14 }}>{t.goBack}</a>
                      </div>
                    </Form>
                  )}
                </div>
              )}

              <div style={{ textAlign: 'center', marginTop: 24 }}>
                <span style={{ color: '#1f2937', fontSize: 12 }}>{t.footer}</span>
              </div>
            </div>
          </div>
        </div>
        
        {/* 滑块验证码弹窗 */}
        <SliderCaptchaModal
          open={captchaOpen}
          onCancel={onCaptchaCancel}
          onSuccess={onCaptchaSuccess}
        />
      </div>

    </div>
  )
}

export default LoginPage
