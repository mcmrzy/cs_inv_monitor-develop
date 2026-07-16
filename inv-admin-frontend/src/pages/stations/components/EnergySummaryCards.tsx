import React from 'react'
import { Row, Col, Card, Statistic } from 'antd'
import { CalendarOutlined, RiseOutlined, TrophyOutlined } from '@ant-design/icons'
import { safeNum } from '@/utils/format'
import useTranslation from '@/hooks/useTranslation'

interface EnergySummaryCardsProps {
  monthEnergy: number
  yearEnergy: number
  totalEnergy: number
}

const EnergySummaryCards: React.FC<EnergySummaryCardsProps> = ({
  monthEnergy, yearEnergy, totalEnergy,
}) => {
  const { t } = useTranslation()

  const cards = [
    {
      title: t('station.monthGen'),
      value: safeNum(monthEnergy),
      icon: <CalendarOutlined style={{ marginRight: 6, color: '#8b5cf6' }} />,
      color: '#8b5cf6',
      bg: 'linear-gradient(135deg, #ede9fe 0%, #f5f3ff 100%)',
    },
    {
      title: t('station.yearGen'),
      value: safeNum(yearEnergy),
      icon: <RiseOutlined style={{ marginRight: 6, color: '#22c55e' }} />,
      color: '#22c55e',
      bg: 'linear-gradient(135deg, #dcfce7 0%, #f0fdf4 100%)',
    },
    {
      title: t('station.totalGen'),
      value: safeNum(totalEnergy),
      icon: <TrophyOutlined style={{ marginRight: 6, color: '#722ed1' }} />,
      color: '#722ed1',
      bg: 'linear-gradient(135deg, #fce7f3 0%, #fdf2f8 100%)',
    },
  ]

  return (
    <Row gutter={[16, 16]}>
      {cards.map((card) => (
        <Col xs={24} sm={8} key={card.title}>
          <Card bordered={false} style={{ borderRadius: 12, background: card.bg }} styles={{ body: { padding: '16px' } }}>
            <Statistic
              title={<span style={{ fontSize: 13 }}>{card.icon}{card.title}</span>}
              value={card.value}
              suffix="kWh"
              precision={1}
              valueStyle={{ color: card.color, fontWeight: 700, fontSize: 22 }}
            />
          </Card>
        </Col>
      ))}
    </Row>
  )
}

export default EnergySummaryCards
