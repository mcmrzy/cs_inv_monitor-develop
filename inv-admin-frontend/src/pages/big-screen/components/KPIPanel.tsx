import React from 'react'
import {
  ThunderboltOutlined,
  DashboardOutlined,
  WifiOutlined,
  AlertOutlined,
} from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'

interface KPIPanelProps {
  todayEnergy: number
  totalCapacity: number
  onlineRate: number
  alarmCount: number
  deviceStats: {
    total: number
    online: number
    offline: number
    fault: number
  }
}

const KPIPanel: React.FC<KPIPanelProps> = ({
  todayEnergy = 0,
  totalCapacity = 0,
  onlineRate = 0,
  alarmCount = 0,
  deviceStats = { total: 0, online: 0, offline: 0, fault: 0 },
}) => {
  const { t } = useTranslation()

  const total = deviceStats.total || 1
  const onlineWidth = ((deviceStats.online / total) * 100).toFixed(1)
  const offlineWidth = ((deviceStats.offline / total) * 100).toFixed(1)
  const faultWidth = ((deviceStats.fault / total) * 100).toFixed(1)

  return (
    <div className="bs-left">
      <div className="bs-panel">
        <div className="bs-panel-title">{t('bigScreen.systemOverview')}</div>
        <div className="bs-corner-tr"></div>
        <div className="bs-corner-bl"></div>
        <div className="bs-kpi-grid">
          <div className="bs-kpi-card">
            <div className="bs-kpi-icon" style={{ color: '#00d4ff' }}><ThunderboltOutlined /></div>
            <div className="bs-kpi-value" style={{ color: '#00d4ff' }}>{todayEnergy.toLocaleString()}</div>
            <div className="bs-kpi-label">{t('bigScreen.todayEnergy')} (kWh)</div>
          </div>
          <div className="bs-kpi-card">
            <div className="bs-kpi-icon" style={{ color: '#4facfe' }}><DashboardOutlined /></div>
            <div className="bs-kpi-value" style={{ color: '#4facfe' }}>{totalCapacity.toLocaleString()}</div>
            <div className="bs-kpi-label">{t('bigScreen.totalCapacity')} (kW)</div>
          </div>
          <div className="bs-kpi-card">
            <div className="bs-kpi-icon" style={{ color: '#00ff88' }}><WifiOutlined /></div>
            <div className="bs-kpi-value" style={{ color: '#00ff88' }}>{onlineRate.toFixed(1)}%</div>
            <div className="bs-kpi-label">{t('bigScreen.onlineRate')}</div>
          </div>
          <div className="bs-kpi-card">
            <div className="bs-kpi-icon" style={{ color: '#ffa502' }}><AlertOutlined /></div>
            <div className="bs-kpi-value" style={{ color: '#ffa502' }}>{alarmCount.toLocaleString()}</div>
            <div className="bs-kpi-label">{t('bigScreen.alarmCount')}</div>
          </div>
        </div>
        <div className="bs-device-status">
          <div className="bs-status-bar">
            <div className="bs-status-online" style={{ width: `${onlineWidth}%` }}></div>
            <div className="bs-status-offline" style={{ width: `${offlineWidth}%` }}></div>
            <div className="bs-status-fault" style={{ width: `${faultWidth}%` }}></div>
          </div>
          <div className="bs-status-legend">
            <span>{t('bigScreen.online')} {deviceStats.online}</span>
            <span>{t('bigScreen.offline')} {deviceStats.offline}</span>
            <span>{t('bigScreen.fault')} {deviceStats.fault}</span>
          </div>
        </div>
      </div>
    </div>
  )
}

export default React.memo(KPIPanel)
