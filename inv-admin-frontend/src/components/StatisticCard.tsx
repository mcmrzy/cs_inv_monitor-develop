/**
 * StatisticCard - 统一统计卡片组件
 *
 * 替代各页面中散乱的 Card + Statistic 组合，统一视觉风格。
 * 默认样式：无边框、圆角 12px、居中文字。
 */
import React from 'react'
import { Card, Statistic } from 'antd'
import type { StatisticProps } from 'antd'

export interface StatisticCardProps extends StatisticProps {
  /** 卡片是否可悬浮提升，默认 true */
  hoverable?: boolean
  /** 卡片内边距，默认 normal */
  size?: 'small' | 'normal'
  /** 自定义样式 */
  style?: React.CSSProperties
  /** 卡片背景色（用于渐变背景等场景） */
  background?: string
  children?: React.ReactNode
}

const StatisticCard: React.FC<StatisticCardProps> = ({
  hoverable = true,
  size = 'normal',
  style,
  background,
  children,
  ...statisticProps
}) => {
  return (
    <Card
      hoverable={hoverable}
      bordered={false}
      style={{
        borderRadius: 12,
        background,
        ...(style ?? {}),
      }}
      styles={{
        body: {
          padding: size === 'small' ? '12px 16px' : '20px 24px',
        },
      }}
    >
      <Statistic {...statisticProps} />
      {children}
    </Card>
  )
}

export default StatisticCard
