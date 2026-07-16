import { Tag } from 'antd'
import { DEVICE_STATUS_MAP } from '@/utils/constants'
import useTranslation from '@/hooks/useTranslation'

interface StatusBadgeProps {
  status: number | string
}

const StatusBadge: React.FC<StatusBadgeProps> = ({ status }) => {
  const { t } = useTranslation()
  const key = typeof status === 'number' ? String(status) : status
  const config = DEVICE_STATUS_MAP[key] || { color: '#d9d9d9' }
  return <Tag color={config.color}>{config.i18nKey ? t(config.i18nKey) : String(status)}</Tag>
}

export default StatusBadge
