import React from 'react'
import { Popconfirm } from 'antd'
import type { PopconfirmProps } from 'antd'
import useTranslation from '@/hooks/useTranslation'

const LocalizedPopconfirm: React.FC<PopconfirmProps> = ({ okText, cancelText, ...props }) => {
  const { t } = useTranslation()
  return (
    <Popconfirm
      okText={okText ?? t('common.confirm')}
      cancelText={cancelText ?? t('common.cancel')}
      {...props}
    />
  )
}
export default LocalizedPopconfirm
