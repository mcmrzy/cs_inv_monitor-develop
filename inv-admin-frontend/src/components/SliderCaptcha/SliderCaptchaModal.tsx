import React, { useRef } from 'react'
import SliderCaptcha from 'rc-slider-captcha'
import { Modal, App } from 'antd'
import {
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

  // 验证成功回调
  const handleComplete = async (trackData: any) => {
    try {
      console.log('轨迹数据:', trackData)

      // 将轨迹数据发送到后端验证
      const response = await fetch(`${apiUrl}/captcha/verify`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(trackData),
      })

      const result = await response.json()

      if (result.code === 0 && result.data?.verified) {
        onSuccess(result.data.verifyToken)
        message.success('验证成功')
      } else {
        message.error(result.message || '验证失败，请重试')
      }
    } catch (error) {
      console.error('验证失败:', error)
      message.error('验证失败，请重试')
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
          width={320}
          height={160}
          blockSize={50}
          maxWrongAttempts={3}
          onComplete={handleComplete}
        />
      </div>
    </Modal>
  )
}

export default SliderCaptchaModal
