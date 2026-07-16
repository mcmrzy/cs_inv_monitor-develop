import React from 'react'
import { Card, Tag, Typography, Space, Progress } from 'antd'
import {
  CheckCircleOutlined, WarningOutlined, DesktopOutlined,
  ThunderboltOutlined, SunOutlined,
} from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'

const { Text, Title } = Typography

interface StationCardProps {
  station: {
    id: number
    name: string
    province?: string
    city?: string
    district?: string
    address?: string
    capacity?: number
    device_count?: number
    online_count?: number
    fault_count?: number
    today_generation?: number
    total_generation?: number
    status: number
    [key: string]: any
  }
  onClick?: () => void
}

const StationCard: React.FC<StationCardProps> = ({ station, onClick }) => {
  const { t } = useTranslation()

  const faultCount = station.fault_count ?? 0
  const deviceCount = station.device_count ?? 0
  const onlineCount = station.online_count ?? 0
  const isOffline = deviceCount > 0 && onlineCount === 0
  const hasFault = faultCount > 0

  const statusColor = hasFault ? '#ff4d4f' : isOffline ? '#8c8c8c' : '#52c41a'
  const statusLabel = hasFault
    ? t('station.fault')
    : isOffline
      ? t('station.offline')
      : station.status === 1
        ? t('station.normal')
        : t('station.stopped')

  const location = [station.province, station.city, station.district].filter(Boolean).join(' ') || station.address || '-'

  const onlinePercent = deviceCount > 0 ? Math.round((onlineCount / deviceCount) * 100) : 0

  return (
    <Card
      hoverable
      onClick={onClick}
      style={{ borderRadius: 12, height: '100%' }}
      styles={{ body: { padding: '16px 20px' } }}
    >
      {/* Header: name + status */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 8 }}>
        <Title level={5} style={{ margin: 0, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} ellipsis={{ tooltip: station.name }}>
          {station.name}
        </Title>
        <Tag
          color={statusColor}
          icon={hasFault ? <WarningOutlined /> : isOffline ? <DesktopOutlined /> : <CheckCircleOutlined />}
          style={{ marginLeft: 8, flexShrink: 0 }}
        >
          {statusLabel}
        </Tag>
      </div>

      {/* Location */}
      <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 12 }} ellipsis={{ tooltip: location }}>
        {location}
      </Text>

      {/* Stats row */}
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontSize: 18, fontWeight: 600, color: '#1677ff' }}>{deviceCount}</div>
          <Text type="secondary" style={{ fontSize: 11 }}>{t('station.deviceCount')}</Text>
        </div>
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontSize: 18, fontWeight: 600, color: '#52c41a' }}>{onlineCount}</div>
          <Text type="secondary" style={{ fontSize: 11 }}>{t('station.onlineCount')}</Text>
        </div>
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontSize: 18, fontWeight: 600, color: faultCount > 0 ? '#ff4d4f' : undefined }}>{faultCount}</div>
          <Text type="secondary" style={{ fontSize: 11 }}>{t('station.faultCount')}</Text>
        </div>
      </div>

      {/* Online rate progress */}
      <Progress
        percent={onlinePercent}
        size="small"
        strokeColor={onlinePercent === 100 ? '#52c41a' : onlinePercent > 0 ? '#1677ff' : '#d9d9d9'}
        format={(p) => `${p}%`}
        style={{ marginBottom: 12 }}
      />

      {/* Generation info */}
      <Space style={{ width: '100%', justifyContent: 'space-between' }}>
        <Space size={4}>
          <SunOutlined style={{ color: '#fa8c16' }} />
          <Text style={{ fontSize: 12 }}>
            {t('station.todayGeneration')}: {station.today_generation != null ? `${station.today_generation.toFixed(1)} kWh` : '-'}
          </Text>
        </Space>
        {station.capacity && (
          <Text type="secondary" style={{ fontSize: 12 }}>
            {station.capacity} kW
          </Text>
        )}
      </Space>
    </Card>
  )
}

export default StationCard
