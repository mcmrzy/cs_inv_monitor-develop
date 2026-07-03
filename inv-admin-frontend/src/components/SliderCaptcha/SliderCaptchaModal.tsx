import React, { useRef } from 'react'
import SliderCaptcha from 'rc-slider-captcha'
import { Modal, App } from 'antd'
import {
  LoadingOutlined,
  SmileOutlined,
  MehOutlined,
  RedoOutlined,
  SafetyOutlined,
} from '@ant-design/icons'

interface SliderCaptchaModalProps {
  open: boolean
  onCancel: () => void
  onSuccess: (token: string) => void
  apiUrl?: string
}

const SliderCaptchaModal: React.FC<SliderCaptchaModalProps> = ({
  open,
  onCancel,
  onSuccess,
  apiUrl = '/api/v1',
}) => {
  const { message } = App.useApp()
  const captchaKeyRef = useRef<string>('')

  // 请求验证码数据（从后端获取）
  const request = async () => {
    try {
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
  const onVerify = async (data: { x: number; y: number; duration: number; trail: [number, number][] }) => {
    try {
      console.log('验证参数:', { x: data.x, captchaKey: captchaKeyRef.current })

      const response = await fetch(`${apiUrl}/captcha/verify`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          captchaKey: captchaKeyRef.current,
          x: data.x,
          y: data.y,
          duration: data.duration,
          trail: data.trail,
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
          request={request}
          onVerify={onVerify}
          bgSize={{ width: 320, height: 160 }}
          puzzleSize={{ width: 60 }}
          showRefreshIcon
          autoRefreshOnError
          errorHoldDuration={1000}
          limitErrorCount={3}
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
            '--rcsc-primary': '#4f6ef7',
            '--rcsc-primary-light': '#e0e7ff',
            '--rcsc-success': '#52c41a',
            '--rcsc-error': '#ff4d4f',
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
