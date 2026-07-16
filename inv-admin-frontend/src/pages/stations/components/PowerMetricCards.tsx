import React from 'react'
import { Row, Col, Card, Statistic } from 'antd'
import { ThunderboltOutlined, SunOutlined } from '@ant-design/icons'
import { safeNum } from '@/utils/format'
import useTranslation from '@/hooks/useTranslation'

interface PowerMetricCardsProps {
  totalPower: number
  todayEnergy: number
}

const PowerMetricCards: React.FC<PowerMetricCardsProps> = ({ totalPower, todayEnergy }) => {
  const { t } = useTranslation()
  const power = safeNum(totalPower)
  const energy = safeNum(todayEnergy)

  return (
    <Row gutter={[16, 16]}>
      <Col xs={12} sm={12}>
        <Card bordered={false} style={{ borderRadius: 12, background: 'linear-gradient(135deg, #fef3c7 0%, #fffbeb 100%)' }} styles={{ body: { padding: '20px' } }}>
          <Statistic
            title={<span style={{ fontSize: 13 }}><ThunderboltOutlined style={{ marginRight: 6, color: '#f59e0b' }} />{t('station.realtimePower_W')}</span>}
            value={power}
            suffix="W"
            precision={0}
            valueStyle={{ color: '#f59e0b', fontWeight: 700, fontSize: 28 }}
          />
        </Card>
      </Col>
      <Col xs={12} sm={12}>
        <Card bordered={false} style={{ borderRadius: 12, background: 'linear-gradient(135deg, #dbeafe 0%, #eff6ff 100%)' }} styles={{ body: { padding: '20px' } }}>
          <Statistic
            title={<span style={{ fontSize: 13 }}><SunOutlined style={{ marginRight: 6, color: '#3b82f6' }} />{t('station.todayGen')}</span>}
            value={energy}
            suffix="kWh"
            precision={1}
            valueStyle={{ color: '#3b82f6', fontWeight: 700, fontSize: 28 }}
          />
        </Card>
      </Col>
    </Row>
  )
}

export default PowerMetricCards
