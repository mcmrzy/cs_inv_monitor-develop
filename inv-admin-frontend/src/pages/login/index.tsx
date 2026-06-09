import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Form, Input, Button, Card, Typography, Checkbox, App, Tabs, Space } from 'antd'
import { UserOutlined, LockOutlined, MailOutlined, PhoneOutlined } from '@ant-design/icons'
import useAuthStore from '@/stores/authStore'
import api from '@/services/api'
import type { User } from '@/types'
import { Role } from '@/types'

const { Title, Text } = Typography

type ActiveTab = 'login' | 'register' | 'reset'

const LoginPage: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [activeTab, setActiveTab] = useState<ActiveTab>('login')
  const navigate = useNavigate()
  const { login } = useAuthStore()
  const { message } = App.useApp()

  const onLogin = async (values: { account: string; password: string }) => {
    setLoading(true)
    try {
      const res = await api.post('/auth/login', {
        account: values.account,
        password: values.password,
      })
      const responseData = res.data as Record<string, unknown>
      
      if (responseData?.code !== undefined && responseData.code !== 0) {
        message.error((responseData.message as string) || '登录失败，请检查用户名和密码')
        return
      }
      
      const data = (responseData?.data ?? responseData) as {
        token?: string
        accessToken?: string
        access_token?: string
        refresh_token?: string
        refreshToken?: string
        permissions?: string[]
        user: User
      }
      
      if (!data.user) {
        message.error('登录失败，请检查用户名和密码')
        return
      }
      
      const token = data.token ?? data.accessToken ?? data.access_token ?? ''
      const refreshToken = data.refresh_token ?? data.refreshToken ?? ''
      const perms = data.permissions ?? []
      
      login(token, refreshToken, data.user, perms)
      message.success('登录成功')
      navigate('/dashboard', { replace: true })
    } catch (error) {
      message.error('登录失败，请检查用户名和密码')
    } finally {
      setLoading(false)
    }
  }

  const onRegister = async (values: { phone: string; email: string; password: string; nickname: string; code: string }) => {
    setLoading(true)
    try {
      const res = await api.post('/auth/email-register', {
        phone: values.phone,
        email: values.email,
        password: values.password,
        nickname: values.nickname,
        code: values.code,
      })
      const responseData = res.data as Record<string, unknown>
      
      if (responseData?.code !== undefined && responseData.code !== 0) {
        message.error((responseData.message as string) || '注册失败')
        return
      }
      
      message.success('注册成功，请登录')
      setActiveTab('login')
    } catch (error) {
      message.error('注册失败，请稍后重试')
    } finally {
      setLoading(false)
    }
  }

  const onResetPassword = async (values: { email: string; code: string; new_password: string }) => {
    setLoading(true)
    try {
      const res = await api.post('/auth/reset-password', {
        email: values.email,
        code: values.code,
        new_password: values.new_password,
      })
      const responseData = res.data as Record<string, unknown>
      
      if (responseData?.code !== undefined && responseData.code !== 0) {
        message.error((responseData.message as string) || '重置密码失败')
        return
      }
      
      message.success('密码重置成功，请登录')
      setActiveTab('login')
    } catch (error) {
      message.error('重置密码失败，请稍后重试')
    } finally {
      setLoading(false)
    }
  }

  const sendEmailCode = async (email: string, type: 'register' | 'reset') => {
    try {
      const res = await api.post('/auth/send-email-code', { email, type })
      const responseData = res.data as Record<string, unknown>
      if (responseData?.code !== undefined && responseData.code !== 0) {
        message.error((responseData.message as string) || '发送验证码失败')
        return
      }
      message.success('验证码已发送到邮箱')
    } catch (error) {
      message.error('发送验证码失败')
    }
  }

  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: '#f0f2f5',
      }}
    >
      <Card
        style={{
          width: 420,
          boxShadow: '0 4px 24px rgba(0,0,0,0.1)',
          borderRadius: 8,
        }}
        styles={{ body: { padding: '40px 32px' } }}
      >
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <Title level={3} style={{ marginBottom: 0 }}>
            逆变器物联网管理平台
          </Title>
          <Text type="secondary" style={{ display: 'block', marginTop: 8 }}>
            智能运维 · 高效管理
          </Text>
        </div>

        <Tabs
          activeKey={activeTab}
          onChange={(key) => setActiveTab(key as ActiveTab)}
          centered
          items={[
            {
              key: 'login',
              label: '登录',
              children: (
                <Form name="login" onFinish={onLogin} size="large">
                  <Form.Item
                    name="account"
                    rules={[{ required: true, message: '请输入手机号或邮箱' }]}
                  >
                    <Input prefix={<UserOutlined />} placeholder="手机号 / 邮箱" />
                  </Form.Item>
                  <Form.Item
                    name="password"
                    rules={[{ required: true, message: '请输入密码' }]}
                  >
                    <Input.Password prefix={<LockOutlined />} placeholder="密码" />
                  </Form.Item>
                  <Form.Item>
                    <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                      <Form.Item name="remember" valuePropName="checked" noStyle>
                        <Checkbox>记住我</Checkbox>
                      </Form.Item>
                      <a onClick={() => setActiveTab('reset')}>忘记密码？</a>
                    </div>
                  </Form.Item>
                  <Form.Item>
                    <Button type="primary" htmlType="submit" loading={loading} block>
                      登 录
                    </Button>
                  </Form.Item>
                  <div style={{ textAlign: 'center' }}>
                    <Text type="secondary">还没有账号？</Text>
                    <a onClick={() => setActiveTab('register')}> 立即注册</a>
                  </div>
                </Form>
              ),
            },
            {
              key: 'register',
              label: '注册',
              children: (
                <Form name="register" onFinish={onRegister} size="large">
                  <Form.Item
                    name="phone"
                    rules={[
                      { required: true, message: '请输入手机号' },
                      { pattern: /^1[3-9]\d{9}$/, message: '手机号格式不正确' },
                    ]}
                  >
                    <Input prefix={<PhoneOutlined />} placeholder="手机号" />
                  </Form.Item>
                  <Form.Item
                    name="email"
                    rules={[
                      { required: true, message: '请输入邮箱' },
                      { type: 'email', message: '邮箱格式不正确' },
                    ]}
                  >
                    <Input prefix={<MailOutlined />} placeholder="邮箱" />
                  </Form.Item>
                  <Form.Item
                    name="code"
                    rules={[{ required: true, message: '请输入验证码' }]}
                  >
                    <Space.Compact style={{ width: '100%' }}>
                      <Input prefix={<MailOutlined />} placeholder="邮箱验证码" />
                      <Button onClick={() => {
                        const email = (document.querySelector('[name="register"] input[name="email"]') as HTMLInputElement)?.value
                        if (email) sendEmailCode(email, 'register')
                        else message.warning('请先输入邮箱')
                      }}>
                        发送验证码
                      </Button>
                    </Space.Compact>
                  </Form.Item>
                  <Form.Item
                    name="nickname"
                    rules={[{ required: true, message: '请输入昵称' }]}
                  >
                    <Input prefix={<UserOutlined />} placeholder="昵称" />
                  </Form.Item>
                  <Form.Item
                    name="password"
                    rules={[
                      { required: true, message: '请输入密码' },
                      { min: 6, message: '密码至少6位' },
                    ]}
                  >
                    <Input.Password prefix={<LockOutlined />} placeholder="密码" />
                  </Form.Item>
                  <Form.Item
                    name="confirm_password"
                    dependencies={['password']}
                    rules={[
                      { required: true, message: '请确认密码' },
                      ({ getFieldValue }) => ({
                        validator(_, value) {
                          if (!value || getFieldValue('password') === value) {
                            return Promise.resolve()
                          }
                          return Promise.reject(new Error('两次输入的密码不一致'))
                        },
                      }),
                    ]}
                  >
                    <Input.Password prefix={<LockOutlined />} placeholder="确认密码" />
                  </Form.Item>
                  <Form.Item>
                    <Button type="primary" htmlType="submit" loading={loading} block>
                      注 册
                    </Button>
                  </Form.Item>
                  <div style={{ textAlign: 'center' }}>
                    <Text type="secondary">已有账号？</Text>
                    <a onClick={() => setActiveTab('login')}> 立即登录</a>
                  </div>
                </Form>
              ),
            },
            {
              key: 'reset',
              label: '重置密码',
              children: (
                <Form name="reset" onFinish={onResetPassword} size="large">
                  <Form.Item
                    name="email"
                    rules={[
                      { required: true, message: '请输入邮箱' },
                      { type: 'email', message: '邮箱格式不正确' },
                    ]}
                  >
                    <Input prefix={<MailOutlined />} placeholder="邮箱" />
                  </Form.Item>
                  <Form.Item
                    name="code"
                    rules={[{ required: true, message: '请输入验证码' }]}
                  >
                    <Space.Compact style={{ width: '100%' }}>
                      <Input prefix={<MailOutlined />} placeholder="邮箱验证码" />
                      <Button onClick={() => {
                        const email = (document.querySelector('[name="reset"] input[name="email"]') as HTMLInputElement)?.value
                        if (email) sendEmailCode(email, 'reset')
                        else message.warning('请先输入邮箱')
                      }}>
                        发送验证码
                      </Button>
                    </Space.Compact>
                  </Form.Item>
                  <Form.Item
                    name="new_password"
                    rules={[
                      { required: true, message: '请输入新密码' },
                      { min: 6, message: '密码至少6位' },
                    ]}
                  >
                    <Input.Password prefix={<LockOutlined />} placeholder="新密码" />
                  </Form.Item>
                  <Form.Item>
                    <Button type="primary" htmlType="submit" loading={loading} block>
                      重置密码
                    </Button>
                  </Form.Item>
                  <div style={{ textAlign: 'center' }}>
                    <a onClick={() => setActiveTab('login')}>返回登录</a>
                  </div>
                </Form>
              ),
            },
          ]}
        />
      </Card>
    </div>
  )
}

export default LoginPage
