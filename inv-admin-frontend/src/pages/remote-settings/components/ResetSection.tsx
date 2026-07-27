import React from 'react'
import { Button, Modal, App, Typography } from 'antd'
import { ExclamationCircleOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'

const { Text } = Typography

const ResetSection: React.FC = () => {
  const { message, modal } = App.useApp()
  const { t } = useTranslation()

  return (
    <div>
      <Text type="secondary" style={{ display: 'block', marginBottom: 12 }}>
        {t('remote.resetDescription')}
      </Text>
      <Button
        danger
        size="large"
        onClick={() => {
          modal.confirm({
            title: t('remote.resetConfirmTitle'),
            icon: <ExclamationCircleOutlined />,
            content: t('remote.resetConfirmContent'),
            okText: t('remote.confirmExecute'),
            okType: 'danger',
            cancelText: t('remote.cancel'),
            onOk: () => message.success(t('remote.resetCommandSent')),
          })
        }}
      >
        {t('remote.resetToDefault')}
      </Button>
    </div>
  )
}

export default ResetSection
