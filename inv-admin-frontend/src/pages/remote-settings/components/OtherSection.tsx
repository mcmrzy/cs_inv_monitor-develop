import React, { useState } from 'react'
import { Card, Button, Space, Switch, InputNumber, App, Typography } from 'antd'
import { ToolOutlined } from '@ant-design/icons'

const { Text } = Typography

const cardStyle = { borderRadius: 12, marginBottom: 16, boxShadow: '0 1px 3px rgba(0,0,0,0.08)' }
const labelStyle: React.CSSProperties = { fontSize: 13, color: '#666', marginBottom: 4, display: 'block' }
const fieldRowStyle = { marginBottom: 12 }
const settingBtnStyle = { background: '#4f6ef7', borderColor: '#4f6ef7' }

const OtherSection: React.FC = () => {
  const { message } = App.useApp()

  const [ctCompensation, setCtCompensation] = useState<number>(0)
  const [batteryVoltageSample, setBatteryVoltageSample] = useState(false)
  const [disableExternalSample, setDisableExternalSample] = useState(false)
  const [fan1MaxSpeed, setFan1MaxSpeed] = useState<number>(100)
  const [fan1Slope, setFan1Slope] = useState<number>(50)
  const [fan2MaxSpeed, setFan2MaxSpeed] = useState<number>(100)
  const [fan2Slope, setFan2Slope] = useState<number>(50)

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
          <span style={{ fontSize: 16, fontWeight: 'bold' }}>其他设置</span>
        </Space>
      }
    >
      <div style={fieldRowStyle}>
        <Text style={labelStyle}>CT功率补偿(W)</Text>
        <Space>
          <InputNumber min={-199} max={199} value={ctCompensation} onChange={(v) => setCtCompensation(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('CT功率补偿')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>电池电压采样</Text>
        <Switch checked={batteryVoltageSample} onChange={(v) => { setBatteryVoltageSample(v); handleSet('电池电压采样') }} />
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>禁止外部采样</Text>
        <Switch checked={disableExternalSample} onChange={(v) => { setDisableExternalSample(v); handleSet('禁止外部采样') }} />
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>风扇 1 最大速度(%)</Text>
        <Space>
          <InputNumber min={10} max={100} value={fan1MaxSpeed} onChange={(v) => setFan1MaxSpeed(v ?? 10)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('风扇1最大速度')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>转速斜率控制1</Text>
        <Space>
          <InputNumber min={1} max={100} value={fan1Slope} onChange={(v) => setFan1Slope(v ?? 1)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('转速斜率控制1')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>风扇 2 最大速度(%)</Text>
        <Space>
          <InputNumber min={10} max={100} value={fan2MaxSpeed} onChange={(v) => setFan2MaxSpeed(v ?? 10)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('风扇2最大速度')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>转速斜率控制2</Text>
        <Space>
          <InputNumber min={1} max={100} value={fan2Slope} onChange={(v) => setFan2Slope(v ?? 1)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('转速斜率控制2')}>设置</Button>
        </Space>
      </div>
    </Card>
  )
}

export default OtherSection
