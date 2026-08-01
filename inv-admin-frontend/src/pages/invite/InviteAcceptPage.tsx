import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Form, Input, Button, Card, Typography, App, Alert } from 'antd'
import { LockOutlined, PhoneOutlined, SmileOutlined } from '@ant-design/icons'
import useAuthStore from '@/stores/authStore'
import api from '@/services/api'
import type { User } from '@/types'
import useTranslation from '@/hooks/useTranslation'

// Maps the backend user object (snake_case is_system_admin) to the frontend User type.
function mapBackendUser(raw: Record<string, unknown>): User {
  return {
    ...(raw as unknown as User),
    isSystemAdmin: Boolean(raw.is_system_admin ?? raw.isSystemAdmin ?? (raw.role === 0)),
  }
}

interface AcceptResponse {
  invitation_id?: number
  user: User
  access_token?: string
  refresh_token?: string
  expires_in?: number
  permissions?: string[]
}

const InviteAcceptPage: React.FC = () => {
  const { t } = useTranslation()
  const { token } = useParams<{ token: string }>()
  const navigate = useNavigate()
  const { login } = useAuthStore()
  const { message } = App.useApp()
  const [loading, setLoading] = useState(false)
  const [fatalError, setFatalError] = useState<string | null>(null)

  const onFinish = async (values: { password: string; phone: string; nickname: string }) => {
    if (!token) {
      setFatalError(t('invite.accept.invalidToken'))
      return
    }
    setLoading(true)
    setFatalError(null)
    try {
      const res = await api.post('/invite/accept', {
        invitation_code: token,
        password: values.password,
        phone: values.phone,
        nickname: values.nickname,
      })
      const d = res.data as Record<string, unknown>
      if (d?.code !== undefined && d.code !== 0) {
        const msg = (d?.message as string) || t('invite.accept.invalidToken')
        if (d.code === 401) {
          setFatalError(msg)
        } else {
          message.error(t('invite.accept.failed', { message: msg }))
        }
        return
      }
      const data = (d?.data ?? d) as AcceptResponse
      if (!data.user) {
        setFatalError(t('invite.accept.invalidToken'))
        return
      }
      login(
        data.access_token ?? '',
        data.refresh_token ?? '',
        mapBackendUser(data.user as unknown as Record<string, unknown>),
        data.permissions ?? [],
      )
      message.success(t('invite.accept.success'))
      navigate('/dashboard', { replace: true })
    } catch (err: any) {
      const errData = err?.response?.data
      if (errData?.code === 401) {
        setFatalError(t('invite.accept.invalidToken'))
      } else {
        message.error(t('invite.accept.failed', { message: errData?.message || 'request failed' }))
      }
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
        background: 'linear-gradient(135deg, #1677ff11 0%, #ffffff 60%)',
        padding: 24,
      }}
    >
      <Card style={{ width: 420, boxShadow: '0 6px 16px rgba(0,0,0,0.08)' }}>
        <div style={{ textAlign: 'center', marginBottom: 24 }}>
          <Typography.Title level={3} style={{ marginBottom: 4 }}>
            {t('invite.accept.title')}
          </Typography.Title>
          <Typography.Text type="secondary">
            {t('invite.accept.subtitle')}
          </Typography.Text>
        </div>

        {fatalError && (
          <Alert
            type="error"
            showIcon
            message={fatalError}
            style={{ marginBottom: 16 }}
            action={
              <Button size="small" onClick={() => navigate('/login', { replace: true })}>
                {t('common.goLogin') || 'Login'}
              </Button>
            }
          />
        )}

        <Form layout="vertical" onFinish={onFinish} disabled={loading || !!fatalError}>
          <Form.Item
            label={t('invite.accept.nickname')}
            name="nickname"
            rules={[{ required: true, message: t('invite.accept.nicknamePlaceholder') }]}
          >
            <Input prefix={<SmileOutlined />} placeholder={t('invite.accept.nicknamePlaceholder')} />
          </Form.Item>
          <Form.Item
            label={t('invite.accept.phone')}
            name="phone"
            rules={[
              { required: true, message: t('invite.accept.phonePlaceholder') },
              { pattern: /^[0-9+\-\s]{6,20}$/, message: t('invite.accept.phonePlaceholder') },
            ]}
          >
            <Input prefix={<PhoneOutlined />} placeholder={t('invite.accept.phonePlaceholder')} />
          </Form.Item>
          <Form.Item
            label={t('invite.accept.password')}
            name="password"
            rules={[
              { required: true, message: t('invite.accept.passwordPlaceholder') },
              { min: 6, max: 20, message: t('invite.accept.passwordPlaceholder') },
            ]}
          >
            <Input.Password prefix={<LockOutlined />} placeholder={t('invite.accept.passwordPlaceholder')} />
          </Form.Item>
          <Form.Item style={{ marginBottom: 8 }}>
            <Button type="primary" htmlType="submit" block size="large" loading={loading}>
              {t('invite.accept.submit')}
            </Button>
          </Form.Item>
        </Form>
      </Card>
    </div>
  )
}

export default InviteAcceptPage
