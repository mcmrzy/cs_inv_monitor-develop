import React from 'react'
import { Card, Statistic, Row, Col, Typography } from 'antd'
import type { DeviceModelFieldItem } from '@/services/modelApi'
import useTranslation from '@/hooks/useTranslation'

const { Text } = Typography

interface DynamicStatCardsProps {
  fields: DeviceModelFieldItem[]
  data: Record<string, any>
  maxCards?: number
  colors?: string[]
}

const defaultColors = ['#1677ff', '#fa8c16', '#52c41a', '#eb2f96', '#722ed1', '#13c2c2', '#faad14', '#f5222d']

const DynamicStatCards: React.FC<DynamicStatCardsProps> = ({
  fields,
  data,
  maxCards = 4,
  colors = defaultColors,
}) => {
  const { t } = useTranslation()
  if (!fields || fields.length === 0) {
    return (
      <div style={{ textAlign: 'center', padding: 24 }}>
        <Text type="secondary">{t('common.noStatFields')}</Text>
      </div>
    )
  }

  const displayFields = fields.slice(0, maxCards)

  return (
    <Row gutter={[12, 12]} style={{ marginBottom: 16 }}>
      {displayFields.map((field, idx) => {
        const value = data[field.field_key]
        const numValue = value != null ? Number(value) : 0
        const displayValue = isNaN(numValue) ? (value ?? 0) : numValue

        return (
          <Col span={Math.floor(24 / Math.min(displayFields.length, 3))} key={field.id}>
            <Card size="small">
              <Statistic
                title={field.field_name && t(field.field_name) !== field.field_name ? t(field.field_name) : (field.field_name || field.field_key)}
                value={displayValue}
                suffix={field.unit || ''}
                valueStyle={{
                  color: colors[idx % colors.length],
                  fontSize: 20,
                }}
                precision={field.field_type === 'float' ? 1 : 0}
              />
            </Card>
          </Col>
        )
      })}
    </Row>
  )
}

export default DynamicStatCards
