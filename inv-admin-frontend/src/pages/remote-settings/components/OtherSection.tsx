import React, { useState } from 'react'
import { Row, Col, InputNumber, App, Typography, Space, Button, Select } from 'antd'
import { FieldRow, SettingButton, PRIMARY, labelStyle, fieldRowStyle } from './shared-styles'

const { Text } = Typography
const { Option } = Select

const OtherSection: React.FC = () => {
  const { message } = App.useApp()

  const [ctCompensation, setCtCompensation] = useState<number>(0)
  const [batteryVoltageSample, setBatteryVoltageSample] = useState<number>(0)
  const [fan1MaxSpeed, setFan1MaxSpeed] = useState<number>(100)
  const [fan1SlopeMode, setFan1SlopeMode] = useState<'default' | 'custom'>('default')
  const [fan1Slope, setFan1Slope] = useState<number>(50)
  const [fan2MaxSpeed, setFan2MaxSpeed] = useState<number>(100)
  const [fan2SlopeMode, setFan2SlopeMode] = useState<'default' | 'custom'>('default')
  const [fan2Slope, setFan2Slope] = useState<number>(50)

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 指令已下发`)
  }

  return (
    <Row gutter={[16, 8]}>
      <FieldRow label="CT功率补偿(W)" range="[-199, 199]">
        <InputNumber min={-199} max={199} value={ctCompensation} onChange={(v) => setCtCompensation(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('CT功率补偿')} />
      </FieldRow>

      <FieldRow label="电池电压采样" tooltip="设置为内部、外部或两者可用。">
        <Select<number> value={batteryVoltageSample} onChange={setBatteryVoltageSample} style={{ width: 160 }}>
          <Option value={1}>禁止外部采样</Option>
          <Option value={2}>禁止内部采样</Option>
          <Option value={0}>两个采样使能</Option>
        </Select>
        <SettingButton onClick={() => handleSet('电池电压采样')} />
      </FieldRow>

      <FieldRow label="风扇 1 最大速度(%)" range="[10, 100]" tooltip="这设置了冷却风扇1的最大速度。范围是10-100%。">
        <InputNumber min={10} max={100} value={fan1MaxSpeed} onChange={(v) => setFan1MaxSpeed(v ?? 10)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('风扇1最大速度')} />
      </FieldRow>

      {/* 转速斜率控制1 - 两个按钮 */}
      <Col span={24}>
        <div style={{ ...fieldRowStyle, display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap' }}>
          <Text style={{ ...labelStyle, marginBottom: 0, flexShrink: 0, marginRight: 12 }}>转速斜率控制1</Text>
          <Space size={4}>
            <Button
              type={fan1SlopeMode === 'default' ? 'primary' : 'default'}
              size="small"
              onClick={() => { setFan1SlopeMode('default'); handleSet('转速斜率控制1-默认') }}
              style={fan1SlopeMode === 'default' ? { background: '#10b981', borderColor: '#10b981' } : {}}
            >
              默认
            </Button>
            <Button
              type={fan1SlopeMode === 'custom' ? 'primary' : 'default'}
              size="small"
              onClick={() => setFan1SlopeMode('custom')}
              style={fan1SlopeMode === 'custom' ? { background: PRIMARY, borderColor: PRIMARY } : {}}
            >
              新坡度
            </Button>
          </Space>
          {fan1SlopeMode === 'custom' && (
            <div style={{ marginTop: 6, width: '100%' }}>
              <Space>
                <InputNumber min={1} max={100} value={fan1Slope} onChange={(v) => setFan1Slope(v ?? 1)} style={{ width: 100 }} />
                <SettingButton onClick={() => handleSet('转速斜率控制1')} />
              </Space>
            </div>
          )}
        </div>
      </Col>

      <FieldRow label="风扇 2 最大速度(%)" range="[10, 100]" tooltip="这设置了冷却风扇2的最大速度。范围是10-100%。">
        <InputNumber min={10} max={100} value={fan2MaxSpeed} onChange={(v) => setFan2MaxSpeed(v ?? 10)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('风扇2最大速度')} />
      </FieldRow>

      {/* 转速斜率控制2 - 两个按钮 */}
      <Col span={24}>
        <div style={{ ...fieldRowStyle, display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap' }}>
          <Text style={{ ...labelStyle, marginBottom: 0, flexShrink: 0, marginRight: 12 }}>转速斜率控制2</Text>
          <Space size={4}>
            <Button
              type={fan2SlopeMode === 'default' ? 'primary' : 'default'}
              size="small"
              onClick={() => { setFan2SlopeMode('default'); handleSet('转速斜率控制2-默认') }}
              style={fan2SlopeMode === 'default' ? { background: '#10b981', borderColor: '#10b981' } : {}}
            >
              默认
            </Button>
            <Button
              type={fan2SlopeMode === 'custom' ? 'primary' : 'default'}
              size="small"
              onClick={() => setFan2SlopeMode('custom')}
              style={fan2SlopeMode === 'custom' ? { background: PRIMARY, borderColor: PRIMARY } : {}}
            >
              新坡度
            </Button>
          </Space>
          {fan2SlopeMode === 'custom' && (
            <div style={{ marginTop: 6, width: '100%' }}>
              <Space>
                <InputNumber min={1} max={100} value={fan2Slope} onChange={(v) => setFan2Slope(v ?? 1)} style={{ width: 100 }} />
                <SettingButton onClick={() => handleSet('转速斜率控制2')} />
              </Space>
            </div>
          )}
        </div>
      </Col>
    </Row>
  )
}

export default OtherSection
