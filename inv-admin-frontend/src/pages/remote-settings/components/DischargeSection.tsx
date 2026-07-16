import React, { useState } from 'react'
import { Card, Button, Space, Select, InputNumber, App, Typography } from 'antd'
import { ArrowDownOutlined } from '@ant-design/icons'

const { Text } = Typography
const { Option } = Select

const cardStyle = { borderRadius: 12, marginBottom: 16, boxShadow: '0 1px 3px rgba(0,0,0,0.08)' }
const labelStyle: React.CSSProperties = { fontSize: 13, color: '#666', marginBottom: 4, display: 'block' }
const fieldRowStyle = { marginBottom: 12 }
const settingBtnStyle = { background: '#4f6ef7', borderColor: '#4f6ef7' }

const DischargeSection: React.FC = () => {
  const { message } = App.useApp()

  const [dischargeControl, setDischargeControl] = useState('allow')
  const [dischargeCurrent, setDischargeCurrent] = useState<number>(60)
  const [batteryWarnVoltage, setBatteryWarnVoltage] = useState<number>(46)
  const [batteryWarnSoc, setBatteryWarnSoc] = useState<number>(20)
  const [leadAcidCutoffVoltage, setLeadAcidCutoffVoltage] = useState<number>(44)
  const [cutoffSoc, setCutoffSoc] = useState<number>(10)
  const [gridEodVoltage, setGridEodVoltage] = useState<number>(44)
  const [gridCutoffSoc, setGridCutoffSoc] = useState<number>(10)

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 设置已发送`)
  }

  return (
    <Card
      bordered={false}
      style={cardStyle}
      title={
        <Space>
          <ArrowDownOutlined />
          <span style={{ fontSize: 16, fontWeight: 'bold' }}>放电设置</span>
        </Space>
      }
    >
      <div style={fieldRowStyle}>
        <Text style={labelStyle}>放电控制</Text>
        <Space>
          <Select value={dischargeControl} onChange={setDischargeControl} style={{ width: 150 }}>
            <Option value="allow">允许放电</Option>
            <Option value="deny">禁止放电</Option>
          </Select>
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('放电控制')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>放电电流限制(A)</Text>
        <Space>
          <InputNumber min={0} max={110} step={0.1} value={dischargeCurrent} onChange={(v) => setDischargeCurrent(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('放电电流限制')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>电池警告电压(V)</Text>
        <Space>
          <InputNumber min={40} max={50} step={0.1} value={batteryWarnVoltage} onChange={(v) => setBatteryWarnVoltage(v ?? 40)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('电池警告电压')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>电池警告SOC(%)</Text>
        <Space>
          <InputNumber min={0} max={90} value={batteryWarnSoc} onChange={(v) => setBatteryWarnSoc(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('电池警告SOC')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>铅酸电池放电截止电压(V)</Text>
        <Space>
          <InputNumber min={40} max={50} step={0.1} value={leadAcidCutoffVoltage} onChange={(v) => setLeadAcidCutoffVoltage(v ?? 40)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('铅酸电池放电截止电压')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>放电截止SOC(%)</Text>
        <Space>
          <InputNumber min={0} max={90} value={cutoffSoc} onChange={(v) => setCutoffSoc(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('放电截止SOC')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>并网EOD电压(V)</Text>
        <Space>
          <InputNumber min={40} max={50} step={0.1} value={gridEodVoltage} onChange={(v) => setGridEodVoltage(v ?? 40)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('并网EOD电压')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>并网截止SOC(%)</Text>
        <Space>
          <InputNumber min={0} max={90} value={gridCutoffSoc} onChange={(v) => setGridCutoffSoc(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('并网截止SOC')}>设置</Button>
        </Space>
      </div>
    </Card>
  )
}

export default DischargeSection
