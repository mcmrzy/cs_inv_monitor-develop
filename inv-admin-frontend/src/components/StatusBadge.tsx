import { Tag } from 'antd'
import { DEVICE_STATUS_MAP } from '@/utils/constants'

interface StatusBadgeProps {
  status: number | string
}

const STATUS_LABEL_MAP: Record<number, { label: string; color: string }> = {
  0: { label: '离线', color: '#d9d9d9' },
  1: { label: '在线', color: '#52c41a' },
  2: { label: '故障', color: '#ff4d4f' },
}

const StatusBadge: React.FC<StatusBadgeProps> = ({ status }) => {
  const key = typeof status === 'number' ? String(status) : status
  const config = DEVICE_STATUS_MAP[key] || STATUS_LABEL_MAP[status as number] || { label: String(status), color: '#d9d9d9' }
  return <Tag color={config.color}>{config.label}</Tag>
}

export default StatusBadge
