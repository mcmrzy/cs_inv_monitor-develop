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
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <SafetyOutlined style={{ color: '#4f6ef7' }} />
          <span>{t('captcha.title')}</span>
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
          {t('captcha.drag')}
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
