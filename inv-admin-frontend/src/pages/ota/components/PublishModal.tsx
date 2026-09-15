import React from 'react'
import { Modal, Empty } from 'antd'
import useTranslation from '@/hooks/useTranslation'
import type { UpgradePackage } from '@/types'

/**
 * 旧升级包发布弹窗已退役（legacy_package_retired）。
 * 独立模块固件改用「固件管理 → 发布」生命周期，不再提供 package 写 UI。
 */
interface PublishModalProps {
  open: boolean
  packageData: UpgradePackage | null
  onClose: () => void
  onSuccess: () => void
}

const PublishModal: React.FC<PublishModalProps> = ({ open, onClose }) => {
  const { t } = useTranslation()
  return (
    <Modal
      title={t('ota.legacyPackageRetired')}
      open={open}
      onCancel={onClose}
      footer={null}
      destroyOnClose
    >
      <Empty description={t('ota.legacyPackageRetired')} />
    </Modal>
  )
}

export default PublishModal
