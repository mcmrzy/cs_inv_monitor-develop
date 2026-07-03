import React, { useRef } from 'react'
import SliderCaptcha from 'rc-slider-captcha'
import { createPuzzle } from 'create-puzzle'
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

// 默认背景图片（可以替换为实际的图片URL）
const DEFAULT_BG_IMAGE = 'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=640&h=360&fit=crop'

const SliderCaptchaModal: React.FC<SliderCaptchaModalProps> = ({
  open,
  onCancel,
  onSuccess,
  apiUrl = '/api/v1',
}) => {
  const { message } = App.useApp()
  const captchaKeyRef = useRef<string>('')

  // 请求验证码数据（在前端生成拼图）
  const fetchCaptcha = async () => {
    try {
      // 使用 create-puzzle 在前端生成拼图
      const result = await createPuzzle(DEFAULT_BG_IMAGE, {
        width: 60,
        height: 60,
      })

      // 保存 x 位置用于验证
      captchaKeyRef.current = String(result.x)

      return {
        bgUrl: result.bgUrl,
        puzzleUrl: result.puzzleUrl,
      }
    } catch (error) {
      console.error('生成验证码失败:', error)
      message.error('生成验证码失败，请重试')
      throw error
    }
  }

  // 验证滑块位置
  const verifyCaptcha = async (data: { x: number; y: number }) => {
    try {
      const expectedX = Number(captchaKeyRef.current)
      const tolerance = 5 // 允许 ±5 像素的误差

      console.log('验证:', { userX: data.x, expectedX, diff: Math.abs(data.x - expectedX) })

      if (Math.abs(data.x - expectedX) <= tolerance) {
        // 验证成功，生成一个简单的 token
        const verifyToken = `captcha_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`

        // 将 token 发送到后端存储
        const response = await fetch(`${apiUrl}/captcha/store-token`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ token: verifyToken }),
        })

        if (response.ok) {
          onSuccess(verifyToken)
          message.success('验证成功')
          return Promise.resolve()
        } else {
          message.error('验证失败，请重试')
          return Promise.reject(new Error('验证失败'))
        }
      } else {
        message.error('验证失败，请重试')
        return Promise.reject(new Error('位置不正确'))
      }
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
          request={fetchCaptcha}
          onVerify={verifyCaptcha}
          bgSize={{ width: 320, height: 180 }}
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
