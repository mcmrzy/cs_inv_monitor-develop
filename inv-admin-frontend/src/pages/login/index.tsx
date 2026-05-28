import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Form, Input, Button, Card, Typography, Checkbox, App } from 'antd'
import { UserOutlined, LockOutlined } from '@ant-design/icons'
import useAuthStore from '@/stores/authStore'
import api from '@/services/api'
import type { User } from '@/types'
import { Role } from '@/types'

const { Title, Text } = Typography

const LoginPage: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const navigate = useNavigate()
  const { login } = useAuthStore()
  const { message } = App.useApp()

  const onFinish = async (values: { account: string; password: string }) => {
    setLoading(true)
    try {
      const res = await api.post('/auth/login', {
        account: values.account,
        password: values.password,
      })
      const responseData = res.data as Record<string, unknown>
      const data = (responseData?.data ?? responseData) as {
        token?: string
        accessToken?: string
        refresh_token?: string
        refreshToken?: string
        permissions?: string[]
        user: User
      }
      const token = data.token ?? data.accessToken ?? ''
      const refreshToken = data.refresh_token ?? data.refreshToken ?? ''
      const perms = data.permissions ?? []
      login(token, refreshToken, data.user, perms)
      message.success('登录成功')
      const isAdmin = data.user.role === Role.SUPER_ADMIN || data.user.role === Role.AGENT
      navigate(isAdmin ? '/dashboard' : '/portal', { replace: true })
    } catch {
      message.error('登录失败，请检查用户名和密码')
    } finally {
      setLoading(false)
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
          width: 400,
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

        <Form
          name="login"
          initialValues={{ remember: true }}
          onFinish={onFinish}
          size="large"
        >
          <Form.Item
            name="account"
            rules={[{ required: true, message: '请输入手机号或邮箱' }]}
          >
            <Input
              prefix={<UserOutlined />}
              placeholder="手机号 / 邮箱"
            />
          </Form.Item>

          <Form.Item
            name="password"
            rules={[{ required: true, message: '请输入密码' }]}
          >
            <Input.Password
              prefix={<LockOutlined />}
              placeholder="密码"
            />
          </Form.Item>

          <Form.Item>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <Form.Item name="remember" valuePropName="checked" noStyle>
                <Checkbox>记住我</Checkbox>
              </Form.Item>
              <a href="#">忘记密码？</a>
            </div>
          </Form.Item>

          <Form.Item>
            <Button type="primary" htmlType="submit" loading={loading} block>
              登 录
            </Button>
          </Form.Item>
        </Form>
      </Card>
    </div>
  )
}

export default LoginPage
