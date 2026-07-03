import React, { useRef, useState } from 'react'
import SliderCaptcha from 'rc-slider-captcha'
import { Modal, App } from 'antd'
import {
  LoadingOutlined,
  SmileOutlined,
  MehOutlined,
  RedoOutlined,
  SafetyOutlined,
} from '@ant-design/icons'

interface CaptchaResult {
  verified: boolean
  verifyToken: string
}

interface SliderCaptchaModalProps {
  open: boolean
  onCancel: () => void
  onSuccess: (token: string) => void
  request?: () => Promise<{ bgUrl: string; puzzleUrl: string; captchaKey: string }>
  apiUrl?: string
}

const SliderCaptchaModal: React.FC<SliderCaptchaModalProps> = ({
  open,
  onCancel,
  onSuccess,
  request,
  apiUrl = '/api/v1',
}) => {
  const { message } = App.useApp()
  const [loading, setLoading] = useState(false)
  const captchaKeyRef = useRef<string>('')

  // 请求验证码数据
  const fetchCaptcha = async () => {
    try {
      if (request) {
        const data = await request()
        captchaKeyRef.current = data.captchaKey
        return {
          bgUrl: data.bgUrl,
          puzzleUrl: data.puzzleUrl,
        }
      }

      const response = await fetch(`${apiUrl}/captcha/generate`)
      const result = await response.json()

      if (result.code === 0 && result.data) {
        captchaKeyRef.current = result.data.captchaKey
        return {
          bgUrl: result.data.bgUrl,
          puzzleUrl: result.data.puzzleUrl,
        }
      }

      throw new Error('获取验证码失败')
    } catch (error) {
      console.error('获取验证码失败:', error)
      message.error('获取验证码失败，请重试')
      throw error
    }
  }

  // 验证滑块位置
  const verifyCaptcha = async (data: { x: number; y: number }) => {
    try {
      setLoading(true)

      if (request) {
        // 使用自定义验证逻辑
        const result = await verifyWithCustomLogic(data)
        if (result.verified) {
          onSuccess(result.verifyToken)
          return Promise.resolve()
        }
        return Promise.reject(new Error('验证失败'))
      }

      const response = await fetch(`${apiUrl}/captcha/verify`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          captchaKey: captchaKeyRef.current,
          x: data.x,
          y: data.y,
        }),
      })

      const result = await response.json()

      if (result.code === 0 && result.data?.verified) {
        onSuccess(result.data.verifyToken)
        message.success('验证成功')
        return Promise.resolve()
      }

      message.error(result.message || '验证失败，请重试')
      return Promise.reject(new Error(result.message || '验证失败'))
    } catch (error) {
      console.error('验证失败:', error)
      message.error('验证失败，请重试')
      return Promise.reject(error)
    } finally {
      setLoading(false)
    }
  }

  // 自定义验证逻辑（用于支持自定义 request）
  const verifyWithCustomLogic = async (data: {
    x: number
    y: number
  }): Promise<CaptchaResult> => {
    // 这里可以实现自定义的验证逻辑
    // 例如：直接调用后端验证接口
    const response = await fetch(`${apiUrl}/captcha/verify`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        captchaKey: captchaKeyRef.current,
        x: data.x,
        y: data.y,
      }),
    })

    const result = await response.json()

    if (result.code === 0 && result.data?.verified) {
      return {
        verified: true,
        verifyToken: result.data.verifyToken,
      }
    }

    return {
      verified: false,
      verifyToken: '',
    }
  }

  return (
    <Modal
      title={
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <SafetyOutlined style={{ color: '#4f6ef7' }} />
          <span>安全验证</span>
        </div>
      }
      open={open}
      onCancel={onCancel}
      footer={null}
      width={380}
      centered
      destroyOnClose
      styles={{
        body: { padding: '24px 16px' },
      }}
    >
      <div style={{ textAlign: 'center' }}>
        <p style={{ color: '#666', marginBottom: 16, fontSize: 14 }}>
          请拖动滑块完成验证
        </p>
        <SliderCaptcha
          mode="embed"
          request={fetchCaptcha}
          onVerify={verifyCaptcha}
          bgSize={{ width: 340, height: 170 }}
          puzzleSize={{ width: 60 }}
          showRefreshIcon
          autoRefreshOnError
          errorHoldDuration={1000}
          tipText={{
            default: '请拖动滑块完成验证',
            loading: '加载中...',
            moving: '请拖动滑块',
            verifying: '验证中...',
            success: '验证成功',
            error: '验证失败',
            errors: '操作过于频繁',
            loadFailed: '加载失败',
          }}
          tipIcon={{
            default: <SafetyOutlined style={{ fontSize: 18 }} />,
            loading: <LoadingOutlined style={{ fontSize: 18 }} />,
            success: <SmileOutlined style={{ fontSize: 18, color: '#52c41a' }} />,
            error: <MehOutlined style={{ fontSize: 18, color: '#ff4d4f' }} />,
            refresh: <RedoOutlined style={{ fontSize: 18 }} />,
          }}
          style={{
            '--rcsc-primary-color': '#4f6ef7',
            '--rcsc-primary-color-hover': '#6366f1',
            '--rcsc-success-color': '#52c41a',
            '--rcsc-error-color': '#ff4d4f',
            borderRadius: 8,
            overflow: 'hidden',
            boxShadow: '0 2px 12px rgba(0, 0, 0, 0.08)',
          } as React.CSSProperties}
        />
      </div>
    </Modal>
  )
}

export default SliderCaptchaModal
