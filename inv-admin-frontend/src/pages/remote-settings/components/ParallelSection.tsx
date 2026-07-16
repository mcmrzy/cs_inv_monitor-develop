import React, { useState } from 'react'
import { Card, Button, Space, Select, Switch, App, Typography } from 'antd'
import { ToolOutlined } from '@ant-design/icons'

const { Text } = Typography
const { Option } = Select

const cardStyle = { borderRadius: 12, marginBottom: 16, boxShadow: '0 1px 3px rgba(0,0,0,0.08)' }
const labelStyle: React.CSSProperties = { fontSize: 13, color: '#666', marginBottom: 4, display: 'block' }
const fieldRowStyle = { marginBottom: 12 }
const settingBtnStyle = { background: '#4f6ef7', borderColor: '#4f6ef7' }

const ParallelSection: React.FC = () => {
  const { message } = App.useApp()

  const [systemType, setSystemType] = useState('single')
  const [sharedBattery, setSharedBattery] = useState(false)
  const [gridPhase, setGridPhase] = useState('L1')
  const [noGridInput, setNoGridInput] = useState(false)

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 设置已发送`)
  }

  return (
    <Card
      bordered={false}
      style={cardStyle}
      title={
        <Space>
          <ToolOutlined />
          <span style={{ fontSize: 16, fontWeight: 'bold' }}>并联设置</span>
        </Space>
      }
    >
      <div style={fieldRowStyle}>
        <Text style={labelStyle}>系统类型</Text>
        <Space>
          <Select value={systemType} onChange={setSystemType} style={{ width: 150 }}>
            <Option value="single">单机</Option>
            <Option value="single_phase_parallel">单相并联</Option>
            <Option value="three_phase_parallel">三相并联</Option>
          </Select>
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('系统类型')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>共用电池</Text>
        <Switch checked={sharedBattery} onChange={(v) => { setSharedBattery(v); handleSet('共用电池') }} />
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>设置组网相位</Text>
        <Space>
          <Select value={gridPhase} onChange={setGridPhase} style={{ width: 150 }}>
            <Option value="L1">L1</Option>
            <Option value="L2">L2</Option>
            <Option value="L3">L3</Option>
          </Select>
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('设置组网相位')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>无市电输入</Text>
        <Switch checked={noGridInput} onChange={(v) => { setNoGridInput(v); handleSet('无市电输入') }} />
      </div>
    </Card>
  )
}

export default ParallelSection
