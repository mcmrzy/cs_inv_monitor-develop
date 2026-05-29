import React from 'react'
import { Descriptions, Tag, Space, Typography, Empty, Spin } from 'antd'
import type { DeviceModelFieldItem } from '@/services/modelApi'

const { Text } = Typography

interface DynamicFieldRendererProps {
  fields: DeviceModelFieldItem[]
  data: Record<string, any>
  column?: number
  size?: 'small' | 'middle' | 'default'
  bordered?: boolean
  emptyText?: string
}

const DynamicFieldRenderer: React.FC<DynamicFieldRendererProps> = ({
  fields,
  data,
  column = 2,
  size = 'small',
  bordered = true,
  emptyText = '-',
}) => {
  if (!fields || fields.length === 0) {
    return <Empty description="无字段配置" image={Empty.PRESENTED_IMAGE_SIMPLE} />
  }

  const formatValue = (field: DeviceModelFieldItem, value: any): React.ReactNode => {
    if (value === null || value === undefined || value === '') {
      return <Text type="secondary">{emptyText}</Text>
    }

    const unit = field.unit ? ` ${field.unit}` : ''

    switch (field.field_type) {
      case 'bool':
        return value ? <Tag color="green">是</Tag> : <Tag color="default">否</Tag>
      case 'float': {
        const num = Number(value)
        return isNaN(num) ? <Text type="secondary">{emptyText}</Text> : <Text>{num.toFixed(2)}{unit}</Text>
      }
      case 'int': {
        const num = Number(value)
        return isNaN(num) ? <Text type="secondary">{emptyText}</Text> : <Text>{Math.round(num)}{unit}</Text>
      }
      default:
        return <Text>{String(value)}{unit}</Text>
    }
  }

  return (
    <Descriptions column={column} size={size} bordered={bordered}>
      {fields.map((field) => (
        <Descriptions.Item key={field.id} label={field.field_name}>
          {formatValue(field, data[field.field_key])}
        </Descriptions.Item>
      ))}
    </Descriptions>
  )
}

export default DynamicFieldRenderer
