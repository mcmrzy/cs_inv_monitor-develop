/**
 * SocialContribution - 社会贡献面板
 *
 * 基于累计发电量计算环保贡献：节约标准煤、减少CO₂排放、等效种植树木。
 */
import React from 'react'
import { Card, Row, Col, Statistic } from 'antd'
import { CloudOutlined, ExperimentOutlined, GlobalOutlined } from '@ant-design/icons'
import { safeNum } from '@/utils/format'
import useTranslation from '@/hooks/useTranslation'

interface SocialContributionProps {
  totalEnergy: number  // 累计发电 kWh
}

/** 环保换算系数 */
const FACTORS = {
  /** 每 kWh 节约标准煤 kg */
  COAL_PER_KWH: 0.328,
  /** 每 kWh 减少 CO₂ 排放 kg */
  CO2_PER_KWH: 0.785,
  /** 每棵树年均吸收 CO₂ kg */
  CO2_PER_TREE: 22,
}

const SocialContribution: React.FC<SocialContributionProps> = ({ totalEnergy }) => {
  const { t } = useTranslation()
  const energy = safeNum(totalEnergy)

  const coalSaved = energy * FACTORS.COAL_PER_KWH
  const co2Reduced = energy * FACTORS.CO2_PER_KWH
  const treesEquivalent = co2Reduced / FACTORS.CO2_PER_TREE

  const items = [
    {
      title: t('station.coalSaved', '节约标准煤'),
      value: coalSaved,
      suffix: 'kg',
      icon: <CloudOutlined style={{ color: '#1677ff' }} />,
    },
    {
      title: t('station.co2Reduced', '减少CO₂排放'),
      value: co2Reduced,
      suffix: 'kg',
      icon: <ExperimentOutlined style={{ color: '#52c41a' }} />,
    },
    {
      title: t('station.treesEquivalent', '等效种植树木'),
      value: treesEquivalent,
      suffix: t('station.treeUnit', '棵'),
      icon: <GlobalOutlined style={{ color: '#722ed1' }} />,
    },
  ]

  return (
    <Card
      bordered={false}
      style={{ borderRadius: 12 }}
      title={`🌍 ${t('station.socialContribution', '社会贡献')}`}
    >
      <Row gutter={[16, 16]}>
        {items.map((item) => (
          <Col xs={8} key={item.title}>
            <Statistic
              title={item.title}
              value={item.value}
              precision={1}
              suffix={item.suffix}
              prefix={item.icon}
            />
          </Col>
        ))}
      </Row>
    </Card>
  )
}

export default SocialContribution
