import React from 'react'
import { Card, Space } from 'antd'

interface SettingSectionProps {
  title: string
  icon?: React.ReactNode
  children: React.ReactNode
  extra?: React.ReactNode
}

const SettingSection: React.FC<SettingSectionProps> = ({ title, icon, children, extra }) => (
  <Card
    title={
      <Space>
        {icon && <span style={{ color: '#4f6ef7' }}>{icon}</span>}
        {title}
      </Space>
    }
    bordered={false}
    style={{ borderRadius: 12 }}
    extra={extra}
  >
    {children}
  </Card>
)

export default SettingSection
