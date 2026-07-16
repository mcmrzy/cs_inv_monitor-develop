/**
 * EnergySummaryCards - 发电量汇总卡片组
 *
 * 用于电站详情页概览 Tab，展示月/年/累计发电量。
 * 使用统一 StatisticCard 组件保持一致视觉风格。
 */
import React from 'react'
import { Row, Col } from 'antd'
import { ThunderboltOutlined, ArrowUpOutlined, FireOutlined } from '@ant-design/icons'
import StatisticCard from '@/components/StatisticCard'
import { safeNum } from '@/utils/format'
import useTranslation from '@/hooks/useTranslation'

interface EnergySummaryCardsProps {
  monthEnergy: number  // 月发电 kWh
  yearEnergy: number   // 年发电 kWh
  totalEnergy: number  // 累计发电 kWh
}

const EnergySummaryCards: React.FC<EnergySummaryCardsProps> = ({ monthEnergy, yearEnergy, totalEnergy }) => {
  const { t } = useTranslation()

  const items = [
    {
      title: t('station.monthEnergy', '月发电'),
      value: safeNum(monthEnergy),
      precision: 1,
      icon: <ThunderboltOutlined style={{ color: '#1677ff', fontSize: 24 }} />,
      color: '#1677ff',
    },
    {
      title: t('station.yearEnergy', '年发电'),
      value: safeNum(yearEnergy),
      precision: 1,
      icon: <ArrowUpOutlined style={{ color: '#52c41a', fontSize: 24 }} />,
      color: '#52c41a',
    },
    {
      title: t('station.totalEnergy', '累计发电'),
      value: safeNum(totalEnergy),
      precision: 0,
      icon: <FireOutlined style={{ color: '#722ed1', fontSize: 24 }} />,
      color: '#722ed1',
    },
  ]

  return (
    <Row gutter={[16, 16]}>
      {items.map((item) => (
        <Col xs={8} key={item.title}>
          <StatisticCard
            title={item.title}
            value={item.value}
            precision={item.precision}
            suffix="kWh"
            prefix={item.icon}
            valueStyle={{ color: item.color }}
          />
        </Col>
      ))}
    </Row>
  )
}

export default EnergySummaryCards
