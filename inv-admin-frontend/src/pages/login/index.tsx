import { useState, useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { Form, Input, Button, Typography, Checkbox, App, Space, Alert, Dropdown } from 'antd'
import { UserOutlined, LockOutlined, MailOutlined, PhoneOutlined, SafetyOutlined, CloudOutlined, LineChartOutlined, GlobalOutlined } from '@ant-design/icons'
import useAuthStore from '@/stores/authStore'
import useLocaleStore from '@/stores/localeStore'
import api from '@/services/api'
import type { User } from '@/types'
import SliderCaptchaModal from '@/components/SliderCaptcha/SliderCaptchaModal'

// 导入登录背景图片
import loginBg1 from '@/assets/images/login/login-bg-1.jpg'
import loginBg2 from '@/assets/images/login/login-bg-2.jpg'
import loginBg3 from '@/assets/images/login/login-bg-3.jpg'
import loginBg4 from '@/assets/images/login/login-bg-4.jpg'
import loginBg5 from '@/assets/images/login/login-bg-5.jpg'
import loginBg6 from '@/assets/images/login/login-bg-6.png'
import loginBg7 from '@/assets/images/login/login-bg-7.png'
import loginBg8 from '@/assets/images/login/login-bg-8.jpg'
import loginBg9 from '@/assets/images/login/login-bg-9.jpg'

const loginBackgrounds = [loginBg1, loginBg2, loginBg3, loginBg4, loginBg5, loginBg6, loginBg7, loginBg8, loginBg9]
const getRandomBg = () => loginBackgrounds[Math.floor(Math.random() * loginBackgrounds.length)]

type ActiveTab = 'login' | 'loginByCode' | 'register' | 'reset'
type Lang = 'zh' | 'en'

const i18n: Record<Lang, Record<string, string>> = {
  zh: {
    brand: '辰烁科技', brandSub: 'CSERGY', title: '光伏逆变器\n智能运维平台',
    subtitle: '集中监控 · 智能告警 · 远程运维 · 数据分析\n一站式管理您的光伏逆变器设备',
    f1Title: '云端集中监控', f1Desc: '实时采集设备数据，多电站统一管理',
    f2Title: '智能告警引擎', f2Desc: '自定义阈值规则，故障秒级推送通知',
    f3Title: '深度数据分析', f3Desc: '发电效率统计，设备性能对比分析',
    stat1: '接入设备', stat2: '平台可用率', stat3: '实时监控',
    welcome: '欢迎回来', createAcc: '创建账号', resetPwd: '重置密码',
    welcomeSub: '登录您的账户以继续', createSub: '注册新账户开始使用', resetSub: '通过邮箱重置密码',
    login: '密码登录', loginByCode: '验证码登录', register: '注册', reset: '重置密码',
    account: '手机号 / 邮箱', password: '密码', remember: '记住我', forgot: '忘记密码？',
    submitLogin: '登 录', noAccount: '还没有账号？', goRegister: '立即注册',
    phone: '手机号', email: '邮箱', code: '验证码', sendCode: '发送验证码', resendCode: 's 后重发',
    phoneCodeLogin: '手机号验证码登录', emailCodeLogin: '邮箱验证码登录',
    loginByPhoneCode: '手机号登录', loginByEmailCode: '邮箱登录',
    nickname: '昵称', confirmPassword: '确认密码', newPassword: '新密码', confirmNewPwd: '确认新密码',
    submitRegister: '注 册', hasAccount: '已有账号？', goLogin: '立即登录',
    submitReset: '重置密码', goBack: '返回登录', emailPlaceholder: '注册时使用的邮箱',
    footer: '© 2026 辰烁科技 · 光伏逆变器智能运维平台',
    errLogin: '登录失败，请检查手机号/邮箱和密码是否正确',
    errRegister: '注册失败，请检查信息后重试',
    errReset: '重置失败，请检查邮箱和验证码是否正确',
    errSendCode: '验证码发送失败，请稍后重试',
    errEmailFirst: '请先输入邮箱',
    errPwdMismatch: '两次输入的密码不一致',
    successLogin: '登录成功', successRegister: '注册成功，请登录', successReset: '密码重置成功，请登录', successCodeSent: '验证码已发送到邮箱',
    errEmailFormat: '邮箱格式不正确', errPhoneFormat: '手机号格式不正确', errPwdMin: '密码至少6位，需包含字母和数字',
  },
  en: {
    brand: 'CHENSHUO', brandSub: 'TECHNOLOGY', title: 'Solar Inverter\nSmart O&M Platform',
    subtitle: 'Monitoring · Alerting · Remote Ops · Analytics\nAll-in-one inverter management',
    f1Title: 'Cloud Monitoring', f1Desc: 'Real-time data, multi-station management',
    f2Title: 'Smart Alerts', f2Desc: 'Custom thresholds, instant fault notifications',
    f3Title: 'Data Analytics', f3Desc: 'Generation stats, device performance comparison',
    stat1: 'Devices', stat2: 'Uptime', stat3: 'Monitoring',
    welcome: 'Welcome Back', createAcc: 'Create Account', resetPwd: 'Reset Password',
    welcomeSub: 'Sign in to your account', createSub: 'Register a new account', resetSub: 'Reset via email',
    login: 'Password Login', loginByCode: 'Code Login', register: 'Register', reset: 'Reset',
    account: 'Phone / Email', password: 'Password', remember: 'Remember me', forgot: 'Forgot password?',
    submitLogin: 'Sign In', noAccount: "Don't have an account? ", goRegister: 'Register',
    phone: 'Phone', email: 'Email', code: 'Verification Code', sendCode: 'Send Code', resendCode: 's',
    phoneCodeLogin: 'Phone Code Login', emailCodeLogin: 'Email Code Login',
    loginByPhoneCode: 'Phone Login', loginByEmailCode: 'Email Login',
    nickname: 'Nickname', confirmPassword: 'Confirm Password', newPassword: 'New Password', confirmNewPwd: 'Confirm New Password',
    submitRegister: 'Sign Up', hasAccount: 'Already have an account? ', goLogin: 'Sign In',
    submitReset: 'Reset Password', goBack: 'Back to Login', emailPlaceholder: 'Your registered email',
    footer: '© 2026 CSERGY · Solar Inverter Smart O&M Platform',
    errLogin: 'Login failed. Please check your phone/email and password.',
    errRegister: 'Registration failed. Please check your info and try again.',
    errReset: 'Reset failed. Please check your email and verification code.',
    errSendCode: 'Failed to send code. Please try again later.',
    errEmailFirst: 'Please enter your email first',
    errPwdMismatch: 'Passwords do not match',
    successLogin: 'Login successful', successRegister: 'Registered! Please sign in.', successReset: 'Password reset! Please sign in.', successCodeSent: 'Code sent to your email',
    errEmailFormat: 'Invalid email format', errPhoneFormat: 'Invalid phone number', errPwdMin: 'At least 6 chars with letters and numbers',
  },
}

const LoginPage: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [activeTab, setActiveTab] = useState<ActiveTab>('login')
  const [countdown, setCountdown] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const [captchaOpen, setCaptchaOpen] = useState(false)
  const [bgImage] = useState(() => getRandomBg())
  const captchaResolveRef = useRef<((token: string) => void) | null>(null)
  const captchaRejectRef = useRef<((reason?: any) => void) | null>(null)
  const { lang, setLang } = useLocaleStore()
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const navigate = useNavigate()
  const { login } = useAuthStore()
  const { message } = App.useApp()
  const [registerForm] = Form.useForm()
  const [resetForm] = Form.useForm()

  const t = i18n[lang]

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
            showError('请完成验证后重试')
            return
          }
        }
        showError((d.message as string) || t.errLogin)
        return
      }
      const data = (d?.data ?? d) as { token?: string; accessToken?: string; access_token?: string; refresh_token?: string; refreshToken?: string; permissions?: string[]; user: User }
      if (!data.user) { showError(t.errLogin); return }
      login(data.token ?? data.accessToken ?? data.access_token ?? '', data.refresh_token ?? data.refreshToken ?? '', data.user, data.permissions ?? [])
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
          showError('请完成验证后重试')
          return
        }
      }
      showError(errData?.message || t.errLogin)
    }
    finally { setLoading(false) }
  }

  // 登录按钮点击
  const onLogin = async (values: { account: string; password: string }) => {
    await performLogin(values)
  }

  const onRegister = async (values: { phone: string; email: string; password: string; nickname: string; code: string }) => {
    setLoading(true); setError(null)
    try {
      const res = await api.post('/auth/email-register', values)
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) { showError((d.message as string) || t.errRegister); return }
      message.success(t.successRegister); setActiveTab('login')
    } catch (err: any) { showError(err?.response?.data?.message || t.errRegister) }
    finally { setLoading(false) }
  }

  const onResetPassword = async (values: { email: string; code: string; new_password: string }) => {
    setLoading(true); setError(null)
    try {
      const res = await api.post('/auth/email-reset-password', values)
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) { showError((d.message as string) || t.errReset); return }
      message.success(t.successReset); setActiveTab('login')
    } catch (err: any) { showError(err?.response?.data?.message || t.errReset) }
    finally { setLoading(false) }
  }

  // 手机号验证码登录
  const onPhoneCodeLogin = async (values: { phone: string; code: string }) => {
    setLoading(true); setError(null)
    try {
      const res = await api.post('/auth/phone-code-login', values)
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) { showError((d.message as string) || t.errLogin); return }
      const data = (d?.data ?? d) as { token?: string; accessToken?: string; access_token?: string; refresh_token?: string; refreshToken?: string; permissions?: string[]; user: User }
      if (!data.user) { showError(t.errLogin); return }
      login(data.token ?? data.accessToken ?? data.access_token ?? '', data.refresh_token ?? data.refreshToken ?? '', data.user, data.permissions ?? [])
      message.success(t.successLogin)
      navigate('/dashboard', { replace: true })
    } catch (err: any) { showError(err?.response?.data?.message || t.errLogin) }
    finally { setLoading(false) }
  }

  // 邮箱验证码登录
  const onEmailCodeLogin = async (values: { email: string; code: string }) => {
    setLoading(true); setError(null)
    try {
      const res = await api.post('/auth/email-code-login', values)
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) { showError((d.message as string) || t.errLogin); return }
      const data = (d?.data ?? d) as { token?: string; accessToken?: string; access_token?: string; refresh_token?: string; refreshToken?: string; permissions?: string[]; user: User }
      if (!data.user) { showError(t.errLogin); return }
      login(data.token ?? data.accessToken ?? data.access_token ?? '', data.refresh_token ?? data.refreshToken ?? '', data.user, data.permissions ?? [])
      message.success(t.successLogin)
      navigate('/dashboard', { replace: true })
    } catch (err: any) { showError(err?.response?.data?.message || t.errLogin) }
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
      if (d?.code !== undefined && d.code !== 0) { showError((d.message as string) || t.errSendCode); return }
      message.success(t.successCodeSent); setCountdown(60)
    } catch (err: any) {
      if (err?.message === '用户取消验证') return
      showError(err?.response?.data?.message || t.errSendCode)
    }
  }

  const inputStyle = { borderRadius: 10, height: 56, fontSize: 17 }

  const CodeButton = ({ emailField, type, form }: { emailField: string; type: 'register' | 'reset'; form: any }) => (
    <Button disabled={countdown > 0}
      onClick={() => { const val = form.getFieldValue(emailField); if (val) sendEmailCode(val, type); else showError(t.errEmailFirst) }}
      style={{ height: 56, borderRadius: '0 10px 10px 0', borderColor: '#d9d9d9', minWidth: 110, fontSize: 15, color: countdown > 0 ? '#6b7280' : '#4f6ef7' }}>
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
                { icon: <SafetyOutlined />, title: t.f2Title, desc: t.f2Desc, color: '#86efac' },
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
                {lang === 'zh' ? '中文' : 'English'}
              </Button>
            </Dropdown>
          </div>

          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '0 36px 40px' }}>
            <div style={{ width: '100%', maxWidth: 360, animation: 'fadeInUp 0.4s ease-out' }}>
              {/* Header */}
              <div style={{ marginBottom: 24 }}>
                <div style={{ fontSize: 30, fontWeight: 700, color: '#0f172a', marginBottom: 6 }}>
                  {activeTab === 'login' || activeTab === 'loginByCode' ? t.welcome : activeTab === 'register' ? t.createAcc : t.resetPwd}
                </div>
                <div style={{ color: '#475569', fontSize: 17 }}>
                  {activeTab === 'login' || activeTab === 'loginByCode' ? t.welcomeSub : activeTab === 'register' ? t.createSub : t.resetSub}
                </div>
              </div>

              {/* Error */}
              {error && (
                <Alert message={error} type="error" showIcon closable onClose={() => setError(null)}
                  style={{ marginBottom: 16, borderRadius: 10, animation: 'fadeInUp 0.2s ease-out' }} />
              )}

              {/* Tab switcher */}
              <div style={{ display: 'flex', background: '#f1f5f9', borderRadius: 10, padding: 3, marginBottom: 24 }}>
                {([['login', t.login], ['loginByCode', t.loginByCode], ['register', t.register], ['reset', t.reset]] as const).map(([tab, label]) => (
                  <button key={tab} onClick={() => { setActiveTab(tab as ActiveTab); setCountdown(0); setError(null) }} style={{
                    flex: 1, padding: '10px 0', border: 'none', borderRadius: 8, cursor: 'pointer',
                    fontSize: 14, fontWeight: 500, transition: 'all 0.2s ease',
                    background: activeTab === tab ? '#fff' : 'transparent',
                    color: activeTab === tab ? '#4f6ef7' : '#475569',
                    boxShadow: activeTab === tab ? '0 1px 3px rgba(0,0,0,0.06)' : 'none',
                  }}>{label}</button>
                ))}
              </div>

              {/* Login */}
              {activeTab === 'login' && (
                <Form name="login" onFinish={onLogin} size="large">
                  <Form.Item name="account" rules={[{ required: true, message: lang === 'zh' ? '请输入手机号或邮箱' : 'Phone or email required' }]}>
                    <Input prefix={<UserOutlined style={{ color: '#94a3b8' }} />} placeholder={t.account} style={inputStyle} />
                  </Form.Item>
                  <Form.Item name="password" rules={[{ required: true, message: lang === 'zh' ? '请输入密码' : 'Password required' }]}>
                    <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.password} style={inputStyle} />
                  </Form.Item>
                  <Form.Item>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                      <Form.Item name="remember" valuePropName="checked" noStyle><Checkbox>{t.remember}</Checkbox></Form.Item>
                      <a onClick={() => setActiveTab('reset')} style={{ color: '#4f6ef7', fontSize: 16, fontWeight: 500 }}>{t.forgot}</a>
                    </div>
                  </Form.Item>
                  <Form.Item>
                    <Button type="primary" htmlType="submit" loading={loading} block style={{ height: 56, borderRadius: 10, fontSize: 18, fontWeight: 600, background: 'linear-gradient(135deg, #4f6ef7 0%, #6366f1 100%)', border: 'none', boxShadow: '0 2px 8px rgba(79,110,247,0.25)' }}>{t.submitLogin}</Button>
                  </Form.Item>
                  <div style={{ textAlign: 'center' }}>
                    <span style={{ color: '#475569', fontSize: 17 }}>{t.noAccount}</span>
                    <a onClick={() => setActiveTab('register')} style={{ color: '#4f6ef7', marginLeft: 4, fontWeight: 500, fontSize: 17 }}>{t.goRegister}</a>
                  </div>
                </Form>
              )}

              {/* LoginByCode */}
              {activeTab === 'loginByCode' && (
                <div>
                  <Form name="phoneCodeLogin" onFinish={onPhoneCodeLogin} size="large">
                    <Form.Item name="phone" rules={[{ required: true, message: lang === 'zh' ? '请输入手机号' : 'Phone required' }, { pattern: /^1[3-9]\d{9}$/, message: t.errPhoneFormat }]}>
                      <Input prefix={<PhoneOutlined style={{ color: '#94a3b8' }} />} placeholder={t.phone} style={inputStyle} />
                    </Form.Item>
                    <Form.Item>
                      <Button type="primary" htmlType="submit" loading={loading} block style={{ height: 56, borderRadius: 10, fontSize: 18, fontWeight: 600, background: 'linear-gradient(135deg, #4f6ef7 0%, #6366f1 100%)', border: 'none', boxShadow: '0 2px 8px rgba(79,110,247,0.25)' }}>{t.loginByPhoneCode}</Button>
                    </Form.Item>
                  </Form>
                  <div style={{ textAlign: 'center', margin: '16px 0', color: '#94a3b8' }}>───────── 或 ─────────</div>
                  <Form name="emailCodeLogin" onFinish={onEmailCodeLogin} size="large">
                    <Form.Item name="email" rules={[{ required: true, message: lang === 'zh' ? '请输入邮箱' : 'Email required' }, { type: 'email', message: t.errEmailFormat }]}>
                      <Input prefix={<MailOutlined style={{ color: '#94a3b8' }} />} placeholder={t.email} style={inputStyle} />
                    </Form.Item>
                    <Form.Item name="code" rules={[{ required: true, message: lang === 'zh' ? '请输入验证码' : 'Code required' }]}>
                      <Space.Compact style={{ width: '100%' }}>
                        <Input prefix={<MailOutlined style={{ color: '#94a3b8' }} />} placeholder={t.code} style={{ ...inputStyle, borderRadius: '10px 0 0 10px' }} />
                        <CodeButton emailField="email" type="login" form={registerForm} />
                      </Space.Compact>
                    </Form.Item>
                    <Form.Item>
                      <Button type="primary" htmlType="submit" loading={loading} block style={{ height: 56, borderRadius: 10, fontSize: 18, fontWeight: 600, background: 'linear-gradient(135deg, #4f6ef7 0%, #6366f1 100%)', border: 'none', boxShadow: '0 2px 8px rgba(79,110,247,0.25)' }}>{t.loginByEmailCode}</Button>
                    </Form.Item>
                  </Form>
                  <div style={{ textAlign: 'center' }}>
                    <span style={{ color: '#475569', fontSize: 17 }}>{t.noAccount}</span>
                    <a onClick={() => setActiveTab('register')} style={{ color: '#4f6ef7', marginLeft: 4, fontWeight: 500, fontSize: 17 }}>{t.goRegister}</a>
                  </div>
                </div>
              )}

              {/* Register */}
              {activeTab === 'register' && (
                <Form form={registerForm} name="register" onFinish={onRegister} size="large">
                  <Form.Item name="phone" rules={[{ required: true, message: lang === 'zh' ? '请输入手机号' : 'Phone required' }, { pattern: /^1[3-9]\d{9}$/, message: t.errPhoneFormat }]}>
                    <Input prefix={<PhoneOutlined style={{ color: '#94a3b8' }} />} placeholder={t.phone} style={inputStyle} />
                  </Form.Item>
                  <Form.Item name="email" rules={[{ required: true, message: lang === 'zh' ? '请输入邮箱' : 'Email required' }, { type: 'email', message: t.errEmailFormat }]}>
                    <Input prefix={<MailOutlined style={{ color: '#94a3b8' }} />} placeholder={t.email} style={inputStyle} />
                  </Form.Item>
                  <Form.Item name="code" rules={[{ required: true, message: lang === 'zh' ? '请输入验证码' : 'Code required' }]}>
                    <Space.Compact style={{ width: '100%' }}>
                      <Input prefix={<MailOutlined style={{ color: '#94a3b8' }} />} placeholder={t.code} style={{ ...inputStyle, borderRadius: '10px 0 0 10px' }} />
                      <CodeButton emailField="email" type="register" form={registerForm} />
                    </Space.Compact>
                  </Form.Item>
                  <Form.Item name="nickname" rules={[{ required: true, message: lang === 'zh' ? '请输入昵称' : 'Nickname required' }]}>
                    <Input prefix={<UserOutlined style={{ color: '#94a3b8' }} />} placeholder={t.nickname} style={inputStyle} />
                  </Form.Item>
                  <Form.Item name="password" rules={[{ required: true, message: lang === 'zh' ? '请输入密码' : 'Password required' }, { min: 6, message: t.errPwdMin }, { pattern: /^(?=.*[a-zA-Z])(?=.*\d).+$/, message: t.errPwdMin }]}>
                    <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.password} style={inputStyle} />
                  </Form.Item>
                  <Form.Item name="confirm_password" dependencies={['password']}
                    rules={[{ required: true, message: lang === 'zh' ? '请确认密码' : 'Confirm password' }, ({ getFieldValue }) => ({ validator(_, value) { if (!value || getFieldValue('password') === value) return Promise.resolve(); return Promise.reject(new Error(t.errPwdMismatch)) } })]}>
                    <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.confirmPassword} style={inputStyle} />
                  </Form.Item>
                  <Form.Item>
                    <Button type="primary" htmlType="submit" loading={loading} block style={{ height: 56, borderRadius: 10, fontSize: 18, fontWeight: 600, background: 'linear-gradient(135deg, #4f6ef7 0%, #6366f1 100%)', border: 'none', boxShadow: '0 2px 8px rgba(79,110,247,0.25)' }}>{t.submitRegister}</Button>
                  </Form.Item>
                  <div style={{ textAlign: 'center' }}>
                    <span style={{ color: '#475569', fontSize: 17 }}>{t.hasAccount}</span>
                    <a onClick={() => setActiveTab('login')} style={{ color: '#4f6ef7', marginLeft: 4, fontWeight: 500, fontSize: 17 }}>{t.goLogin}</a>
                  </div>
                </Form>
              )}

              {/* Reset */}
              {activeTab === 'reset' && (
                <Form name="reset" form={resetForm} onFinish={onResetPassword} size="large">
                  <Form.Item name="email" rules={[{ required: true, message: lang === 'zh' ? '请输入邮箱' : 'Email required' }, { type: 'email', message: t.errEmailFormat }]}>
                    <Input prefix={<MailOutlined style={{ color: '#94a3b8' }} />} placeholder={t.emailPlaceholder} style={inputStyle} />
                  </Form.Item>
                  <Form.Item name="code" rules={[{ required: true, message: lang === 'zh' ? '请输入验证码' : 'Code required' }]}>
                    <Space.Compact style={{ width: '100%' }}>
                      <Input prefix={<MailOutlined style={{ color: '#94a3b8' }} />} placeholder={t.code} style={{ ...inputStyle, borderRadius: '10px 0 0 10px' }} />
                      <CodeButton emailField="email" type="reset" form={resetForm} />
                    </Space.Compact>
                  </Form.Item>
                  <Form.Item name="new_password" rules={[{ required: true, message: lang === 'zh' ? '请输入新密码' : 'New password required' }, { min: 6, message: t.errPwdMin }, { pattern: /^(?=.*[a-zA-Z])(?=.*\d).+$/, message: t.errPwdMin }]}>
                    <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.newPassword} style={inputStyle} />
                  </Form.Item>
                  <Form.Item name="confirm_new_password" dependencies={['new_password']}
                    rules={[{ required: true, message: lang === 'zh' ? '请确认新密码' : 'Confirm new password' }, ({ getFieldValue }) => ({ validator(_, value) { if (!value || getFieldValue('new_password') === value) return Promise.resolve(); return Promise.reject(new Error(t.errPwdMismatch)) } })]}>
                    <Input.Password prefix={<LockOutlined style={{ color: '#94a3b8' }} />} placeholder={t.confirmNewPwd} style={inputStyle} />
                  </Form.Item>
                  <Form.Item>
                    <Button type="primary" htmlType="submit" loading={loading} block style={{ height: 56, borderRadius: 10, fontSize: 18, fontWeight: 600, background: 'linear-gradient(135deg, #4f6ef7 0%, #6366f1 100%)', border: 'none', boxShadow: '0 2px 8px rgba(79,110,247,0.25)' }}>{t.submitReset}</Button>
                  </Form.Item>
                  <div style={{ textAlign: 'center' }}>
                    <a onClick={() => setActiveTab('login')} style={{ color: '#4f6ef7', fontWeight: 500, fontSize: 17 }}>{t.goBack}</a>
                  </div>
                </Form>
              )}

              <div style={{ textAlign: 'center', marginTop: 24 }}>
                <span style={{ color: '#1f2937', fontSize: 12 }}>{t.footer}</span>
              </div>
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
  )
}

export default LoginPage
