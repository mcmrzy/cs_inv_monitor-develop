import React, { useMemo } from 'react'
import ReactECharts from '@/lib/echarts'
import { AlertOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'

interface TrendPoint {
  timeLabel: string
  energy: number
  loadEnergy?: number
}

interface AlarmItem {
  id: number
  device_sn: string
  alarm_level: number
  fault_message: string
  occurred_at: string
}

interface TrendPanelProps {
  trendData: TrendPoint[]
  recentAlarms: AlarmItem[]
}

const getAlarmClass = (level: number) => {
  if (level >= 3) return 'bs-alert-item bs-alert-critical'
  if (level === 2) return 'bs-alert-item bs-alert-warning'
  return 'bs-alert-item bs-alert-info'
}

const TrendPanel: React.FC<TrendPanelProps> = ({
  trendData = [],
  recentAlarms = [],
}) => {
  const { t } = useTranslation()

  const chartOption = useMemo(() => ({
    backgroundColor: 'transparent',
    tooltip: {
      trigger: 'axis',
      backgroundColor: 'rgba(0, 20, 40, 0.9)',
      borderColor: '#00d4ff',
      textStyle: { color: '#fff' },
    },
    grid: {
      top: 30,
      right: 15,
      bottom: 25,
      left: 45,
      containLabel: false,
    },
    xAxis: {
      type: 'category',
      data: trendData.map((d) => d.timeLabel),
      axisLine: { lineStyle: { color: 'rgba(255,255,255,0.1)' } },
      axisLabel: { color: 'rgba(255,255,255,0.6)', fontSize: 10 },
      axisTick: { show: false },
    },
    yAxis: {
      type: 'value',
      splitLine: { lineStyle: { color: 'rgba(255,255,255,0.05)' } },
      axisLabel: { color: 'rgba(255,255,255,0.5)', fontSize: 10 },
      axisLine: { show: false },
    },
    series: [
      {
        name: t('bigScreen.energy'),
        type: 'bar',
        data: trendData.map((d) => d.energy),
        barWidth: '50%',
        itemStyle: {
          color: {
            type: 'linear',
            x: 0, y: 1, x2: 0, y2: 0,
            colorStops: [
              { offset: 0, color: 'transparent' },
              { offset: 1, color: '#00d4ff' },
            ],
          },
          borderRadius: [3, 3, 0, 0],
        },
      },
      {
        name: t('bigScreen.load'),
        type: 'line',
        data: trendData.map((d) => d.loadEnergy ?? 0),
        smooth: true,
        symbol: 'none',
        lineStyle: { color: '#00ff88', width: 2 },
        areaStyle: {
          color: {
            type: 'linear',
            x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: 'rgba(0,255,136,0.3)' },
              { offset: 1, color: 'transparent' },
            ],
          },
        },
      },
    ],
  }), [trendData, t])

  const displayAlarms = recentAlarms.slice(0, 5)

  return (
    <div className="bs-right">
      <div className="bs-panel" style={{ flex: 1.2 }}>
        <div className="bs-panel-title">{t('bigScreen.energyTrend')}</div>
        <div className="bs-corner-tr"></div>
        <div className="bs-corner-bl"></div>
        <div className="bs-chart-container">
          <ReactECharts
            option={chartOption}
            style={{ width: '100%', height: '100%' }}
            opts={{ renderer: 'canvas' }}
          />
        </div>
      </div>
      <div className="bs-panel" style={{ flex: 0.8 }}>
        <div className="bs-panel-title">{t('bigScreen.realtimeAlarms')}</div>
        <div className="bs-corner-tr"></div>
        <div className="bs-corner-bl"></div>
        <div className="bs-alert-list">
          {displayAlarms.length === 0 && (
            <div className="bs-alert-empty">{t('bigScreen.noAlarms')}</div>
          )}
          {displayAlarms.map((a) => (
            <div key={a.id} className={getAlarmClass(a.alarm_level)}>
              <AlertOutlined className="bs-alert-icon" />
              <div className="bs-alert-content">
                <div className="bs-alert-msg">{a.device_sn}: {a.fault_message}</div>
                <div className="bs-alert-time">{a.occurred_at}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

export default React.memo(TrendPanel)
