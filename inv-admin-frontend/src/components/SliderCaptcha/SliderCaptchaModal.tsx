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
import useTranslation from '@/hooks/useTranslation'

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
  const { t } = useTranslation()
  const challengeRef = useRef('')

  // 请求拼图数据
  const request = async () => {
    try {
      const response = await fetch(`${apiUrl}/captcha/generate`)
      const result = await response.json()
      if (!response.ok || result.code !== 0 || !result.data?.challengeId) {
        throw new Error(result.message || t('captcha.generateFailed'))
      }
      challengeRef.current = result.data.challengeId

      return {
        bgUrl: result.data.bgUrl,
        puzzleUrl: result.data.puzzleUrl,
      }
    } catch (error) {
      message.error(t('captcha.generateFailed'))
      throw error
    }
  }

  // 验证滑块位置
  const onVerify = async (data: { x: number; y: number; duration: number; trail: [number, number][] }) => {
    try {
      if (!challengeRef.current) {
        throw new Error(t('captcha.retry'))
      }
      const response = await fetch(`${apiUrl}/captcha/verify`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          challengeId: challengeRef.current,
          x: data.x,
          duration: data.duration,
        }),
      })
      challengeRef.current = ''

      const result = await response.json()

      if (response.ok && result.code === 0 && result.data?.verified) {
        onSuccess(result.data.verifyToken)
        message.success(t('captcha.success'))
        return Promise.resolve()
      }

      message.error(result.message || t('captcha.retry'))
      return Promise.reject(new Error(result.message || t('captcha.failed')))
    } catch (error) {
      message.error(t('captcha.retry'))
      return Promise.reject(error)
    }
  }

  return (
    <Modal
      title={
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ 
            width: 32, 
            height: 32, 
            borderRadius: 8, 
            background: 'linear-gradient(135deg, #4f6ef7 0%, #6366f1 100%)', 
            display: 'flex', 
            alignItems: 'center', 
            justifyContent: 'center',
            boxShadow: '0 2px 8px rgba(79,110,247,0.3)'
          }}>
            <SafetyOutlined style={{ color: '#fff', fontSize: 16 }} />
          </div>
          <span style={{ fontSize: 18, fontWeight: 600 }}>{t('captcha.title')}</span>
        </div>
      }
      open={open}
      onCancel={onCancel}
      footer={null}
      width={420}
      centered
      destroyOnClose
      styles={{
        body: { padding: 0 },
        header: { 
          marginBottom: 0,
          padding: '20px 24px 24px',
          borderBottom: '1px solid #e2e8f0',
        },
      }}
      className="slider-captcha-modal"
    >
      <div style={{ padding: '24px' }}>
        {/* Tip Text */}
        <p style={{ 
          color: '#475569', 
          marginBottom: 20, 
          fontSize: 14,
          textAlign: 'center',
          fontWeight: 500
        }}>
          {t('captcha.drag')}
        </p>

        {/* Slider Captcha Container with Custom Styles */}
        <div style={{
          position: 'relative',
          borderRadius: 16,
          overflow: 'hidden',
          boxShadow: '0 4px 16px rgba(0, 0, 0, 0.08)',
          border: '1px solid #e2e8f0',
          background: '#fff',
        }}>
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
              default: t('captcha.drag'),
              loading: t('captcha.loading'),
              moving: t('captcha.moving'),
              verifying: t('captcha.verifying'),
              success: t('captcha.success'),
              error: t('captcha.failed'),
              errors: t('captcha.tooFrequent'),
              loadFailed: t('captcha.loadFailed'),
            }}
            tipIcon={{
              default: <SafetyOutlined style={{ fontSize: 18 }} />,
              loading: <LoadingOutlined style={{ fontSize: 18 }} />,
              success: <SmileOutlined style={{ fontSize: 18, color: '#059669' }} />,
              error: <MehOutlined style={{ fontSize: 18, color: '#dc2626' }} />,
              refresh: <RedoOutlined style={{ fontSize: 18 }} />,
            }}
            style={{
              '--rcsc-primary': '#4f6ef7',
              '--rcsc-primary-light': '#e0e7ff',
              '--rcsc-success': '#059669',
              '--rcsc-error': '#dc2626',
              '--rcsc-border-color': '#e2e8f0',
              '--rcsc-track-height': '42px',
              '--rcsc-handle-size': '42px',
              borderRadius: 12,
              overflow: 'hidden',
            } as React.CSSProperties}
          />
        </div>
      </div>
    </Modal>
  )
}

export default SliderCaptchaModal
