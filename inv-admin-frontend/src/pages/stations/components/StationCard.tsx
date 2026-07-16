/**
 * StationCard - 电站卡片组件
 *
 * 用于电站列表页的卡片视图，展示电站基本信息与发电数据。
 */
import React from 'react'
import { Card, Tag, Statistic, Divider, Badge } from 'antd'
import { SunOutlined, ThunderboltOutlined } from '@ant-design/icons'
import { safeNum } from '@/utils/format'
import useTranslation from '@/hooks/useTranslation'

interface StationCardProps {
  station: {
    id: number
    name: string
    province?: string
    city?: string
    district?: string
    address?: string
    status: number
    device_count?: number
    online_count?: number
    fault_count?: number
    today_generation?: number
    total_generation?: number
    [key: string]: any
  }
  onClick: () => void
}

/** 根据电站数据计算状态标签 */
function getStatusTag(station: StationCardProps['station'], t: (k: string, fallback?: string) => string) {
  const { fault_count = 0, device_count = 0, online_count = 0, status } = station
  if (fault_count > 0) {
    return <Tag color="#ef4444">{t('station.fault', '故障')}</Tag>
  }
  if (device_count > 0 && online_count === 0) {
    return <Tag color="default">{t('station.offline', '离线')}</Tag>
  }
  if (status === 1) {
    return <Tag color="#22c55e">{t('station.normal', '正常')}</Tag>
  }
  return <Tag color="default">{t('station.stopped', '停止')}</Tag>
}

const StationCard: React.FC<StationCardProps> = ({ station, onClick }) => {
  const { t } = useTranslation()

  const address = [station.province, station.city, station.district]
    .filter(Boolean)
    .join(' ') || station.address || '--'

  return (
    <Card
      bordered={false}
      hoverable
      style={{ borderRadius: 16, cursor: 'pointer' }}
      onClick={onClick}
    >
      {/* 顶部：电站名称 + 状态 */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
        <span style={{ fontSize: 16, fontWeight: 600, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {station.name}
        </span>
        {getStatusTag(station, t)}
      </div>

      {/* 地址 */}
      <div style={{ color: '#999', fontSize: 12, marginBottom: 12, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
        {address}
      </div>

      {/* 右上角设备在线 Badge */}
      <div style={{ position: 'absolute', top: 16, right: 16 }}>
        <Badge
          count={`${safeNum(station.online_count)}/${safeNum(station.device_count)}`}
          style={{ backgroundColor: '#4f6ef7', fontSize: 11 }}
        />
      </div>

      <Divider style={{ margin: '8px 0' }} />

      {/* 底部：今日发电 + 累计发电 */}
      <div style={{ display: 'flex', gap: 16 }}>
        <div style={{ flex: 1 }}>
          <Statistic
            title={t('station.todayGeneration', '今日发电')}
            value={safeNum(station.today_generation)}
            precision={1}
            suffix="kWh"
            prefix={<SunOutlined style={{ color: '#f59e0b' }} />}
            valueStyle={{ color: '#f59e0b', fontSize: 20 }}
          />
        </div>
        <div style={{ flex: 1 }}>
          <Statistic
            title={t('station.totalGeneration', '累计发电')}
            value={safeNum(station.total_generation)}
            precision={1}
            suffix="kWh"
            prefix={<ThunderboltOutlined style={{ color: '#4f6ef7' }} />}
            valueStyle={{ color: '#4f6ef7', fontSize: 20 }}
          />
        </div>
      </div>
    </Card>
  )
}

export default StationCard
