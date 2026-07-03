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

// 本地背景图片
const BG_IMAGE = '/captcha-bg.jpg'

const SliderCaptchaModal: React.FC<SliderCaptchaModalProps> = ({
  open,
  onCancel,
  onSuccess,
  apiUrl = '/api/v1',
}) => {
  const { message } = App.useApp()
  const xRef = useRef(0)

  // 请求拼图数据
  const request = async () => {
    try {
      // 使用 create-puzzle 生成拼图
      const result = await createPuzzle(BG_IMAGE, {
        width: 60,
        height: 60,   // 拼图块高度应该是正方形
        bgWidth: 320,
        bgHeight: 160,
      })

      // 保存 x 位置用于验证
      xRef.current = result.x

      console.log('拼图生成结果:', { x: result.x, y: result.y })

      return {
        bgUrl: result.bgUrl,
        puzzleUrl: result.puzzleUrl,
      }
    } catch (error) {
      console.error('生成拼图失败:', error)
      message.error('生成验证码失败，请重试')
      throw error
    }
  }

  // 验证滑块位置
  const onVerify = async (data: { x: number; y: number; duration: number; trail: [number, number][] }) => {
    try {
      const tolerance = 8
      const diff = Math.abs(data.x - xRef.current)

      console.log('验证参数:', {
        userX: data.x,
        expectedX: xRef.current,
        diff,
        duration: data.duration,
      })

      // 前端验证位置
      if (diff <= tolerance) {
        // 前端验证通过，发送到后端存储 token
        const response = await fetch(`${apiUrl}/captcha/verify`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            x: data.x,
            duration: data.duration,
            verified: true,
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
      }

      message.error('验证失败，请重试')
      return Promise.reject(new Error('位置不正确'))
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
      width={400}
      centered
      destroyOnClose
      styles={{
        body: { padding: '16px 24px' },
      }}
    >
      <div>
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
