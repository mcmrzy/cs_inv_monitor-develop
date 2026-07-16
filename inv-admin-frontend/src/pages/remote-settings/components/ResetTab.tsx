import React from 'react'
import { Spin, Button, Modal, Typography } from 'antd'
import { ReloadOutlined, ExclamationCircleOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { useControlState } from '../hooks/useControlState'
import SettingSection from './SettingSection'

const { Paragraph } = Typography

interface ResetTabProps {
  sn: string
}

const ResetTab: React.FC<ResetTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { isOnline, isLoading, error, refetch, sendCommand, isSending } = useControlState(sn)

  const handleReset = () => {
    Modal.confirm({
      title: t('remote.resetConfirmTitle'),
      icon: <ExclamationCircleOutlined />,
      content: t('remote.resetConfirmContent'),
      okText: t('remote.confirmExecute'),
      okType: 'danger',
      cancelText: t('remote.cancel'),
      onOk: () => sendCommand('reset'),
    })
  }

  return (
    <Spin spinning={isLoading}>
      {error && (
        <QueryErrorAlert
          error={error}
          onRetry={() => { void refetch() }}
          style={{ marginBottom: 16 }}
        />
      )}

      <SettingSection title={t('remote.resetOps')} icon={<ReloadOutlined />}>
        <Paragraph type="secondary" style={{ marginBottom: 16 }}>
          {t('remote.resetConfirmContent')}
        </Paragraph>
        <Button
          danger
          size="large"
          loading={isSending}
          disabled={!isOnline}
          onClick={handleReset}
        >
          {t('remote.resetToDefault')}
        </Button>
      </SettingSection>
    </Spin>
  )
}

export default ResetTab
