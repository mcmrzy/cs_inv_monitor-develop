import React, { useState } from 'react'
import { Row, Col, Checkbox, Button, App, Typography } from 'antd'
import { PRIMARY, fieldRowStyle } from './shared-styles'

const { Text } = Typography

const BatterySection: React.FC = () => {
  const { message } = App.useApp()
  const [selectedModules, setSelectedModules] = useState<number[]>([])

  const handleRestart = () => {
    if (selectedModules.length === 0) {
      message.warning('请至少选择一个电池模块')
      return
    }
    message.success(`正在重启电池模块: ${selectedModules.sort((a, b) => a - b).join(', ')}`)
    setSelectedModules([])
  }

  return (
    <Row gutter={[16, 8]}>
      <Col span={24}>
        <div style={fieldRowStyle}>
          <Text style={{ fontSize: 14, color: '#888', marginBottom: 8, display: 'block' }}>
            选择需要重启的电池模块
          </Text>
        </div>
      </Col>
      <Col span={24}>
        <Checkbox.Group
          value={selectedModules}
          onChange={(vals) => setSelectedModules(vals as number[])}
          style={{ width: '100%' }}
        >
          <Row gutter={[8, 8]}>
            {Array.from({ length: 32 }, (_, i) => (
              <Col key={i} span={6}>
                <Checkbox value={i}>模块 {i}</Checkbox>
              </Col>
            ))}
          </Row>
        </Checkbox.Group>
      </Col>
      <Col span={24} style={{ marginTop: 16 }}>
        <Button
          type="primary"
          danger
          onClick={handleRestart}
          disabled={selectedModules.length === 0}
          style={{ minWidth: 140 }}
        >
          重启电池模块 ({selectedModules.length})
        </Button>
      </Col>
    </Row>
  )
}

export default BatterySection
