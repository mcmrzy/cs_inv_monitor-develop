/**
 * PowerMetricCards - 功率指标卡片组
 *
 * 用于电站详情页概览 Tab，展示当前总功率与今日发电量。
 * 使用渐变背景 + 白色文字的英雄卡片风格。
 */
import React from 'react'
import { Row, Col } from 'antd'
import { ThunderboltOutlined, SunOutlined } from '@ant-design/icons'
import { safeNum } from '@/utils/format'
import useTranslation from '@/hooks/useTranslation'

interface PowerMetricCardsProps {
  totalPower: number   // 当前总功率 W
  todayEnergy: number  // 今日发电 kWh
}

const cardBase: React.CSSProperties = {
  borderRadius: 12,
  padding: '20px 16px',
  color: '#fff',
  minHeight: 100,
}

const PowerMetricCards: React.FC<PowerMetricCardsProps> = ({ totalPower, todayEnergy }) => {
  const { t } = useTranslation()

  return (
    <Row gutter={[16, 16]}>
      <Col xs={12}>
        <div style={{ ...cardBase, background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)' }}>
          <div style={{ fontSize: 13, opacity: 0.85, marginBottom: 8 }}>
            <ThunderboltOutlined style={{ marginRight: 6 }} />
            {t('station.totalPower', '当前总功率')}
          </div>
          <div>
            <span style={{ fontSize: 28, fontWeight: 700 }}>{safeNum(totalPower).toLocaleString()}</span>
            <span style={{ fontSize: 14, marginLeft: 4, opacity: 0.8 }}>W</span>
          </div>
        </div>
      </Col>
      <Col xs={12}>
        <div style={{ ...cardBase, background: 'linear-gradient(135deg, #f59e0b 0%, #ef4444 100%)' }}>
          <div style={{ fontSize: 13, opacity: 0.85, marginBottom: 8 }}>
            <SunOutlined style={{ marginRight: 6 }} />
            {t('station.todayEnergy', '今日发电')}
          </div>
          <div>
            <span style={{ fontSize: 28, fontWeight: 700 }}>{safeNum(todayEnergy).toFixed(1)}</span>
            <span style={{ fontSize: 14, marginLeft: 4, opacity: 0.8 }}>kWh</span>
          </div>
        </div>
      </Col>
    </Row>
  )
}

export default PowerMetricCards
