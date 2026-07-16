import React from 'react'
import { Row, Col, Card, Statistic } from 'antd'
import { safeNum } from '@/utils/format'
import useTranslation from '@/hooks/useTranslation'

interface SocialContributionProps {
  totalEnergy: number // kWh
}

/**
 * 社会贡献卡片 — 根据累计发电量换算环保指标
 * - 节煤: 1 kWh ≈ 0.328 kg 标准煤
 * - 减碳: 1 kWh ≈ 0.997 kg CO₂
 * - 等效树木: 1棵树/年吸收约 22 kg CO₂
 */
const SocialContribution: React.FC<SocialContributionProps> = ({ totalEnergy }) => {
  const { t } = useTranslation()
  const kwh = safeNum(totalEnergy)

  const coalKg = kwh * 0.328
  const co2Kg = kwh * 0.997
  const trees = co2Kg / 22

  const cards = [
    {
      title: t('station.saveCoal'),
      value: coalKg >= 1000 ? coalKg / 1000 : coalKg,
      suffix: coalKg >= 1000 ? 't' : 'kg',
      icon: '⛏️',
      color: '#64748b',
      bg: '#f8fafc',
    },
    {
      title: t('station.reduceCO2'),
      value: co2Kg >= 1000 ? co2Kg / 1000 : co2Kg,
      suffix: co2Kg >= 1000 ? 't' : 'kg',
      icon: '🌍',
      color: '#22c55e',
      bg: '#f0fdf4',
    },
    {
      title: t('station.equivTrees'),
      value: trees,
      suffix: t('station.treeUnit'),
      icon: '🌳',
      color: '#16a34a',
      bg: '#f0fdf4',
    },
  ]

  return (
    <Row gutter={[16, 16]}>
      {cards.map((card) => (
        <Col xs={24} sm={8} key={card.title}>
          <Card bordered={false} style={{ borderRadius: 12, background: card.bg }} styles={{ body: { padding: '16px' } }}>
            <Statistic
              title={<span style={{ fontSize: 13 }}>{card.icon} {card.title}</span>}
              value={card.value}
              suffix={card.suffix}
              precision={card.value >= 100 ? 0 : 1}
              valueStyle={{ color: card.color, fontWeight: 700, fontSize: 22 }}
            />
          </Card>
        </Col>
      ))}
    </Row>
  )
}

export default SocialContribution
