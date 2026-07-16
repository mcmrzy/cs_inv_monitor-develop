import React, { useState } from 'react'
import { Row, Select, InputNumber, App } from 'antd'
import { FieldRow, SettingButton } from './shared-styles'

const { Option } = Select

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
    <Row gutter={[16, 8]}>
      <FieldRow label="放电控制">
        <Select value={dischargeControl} onChange={setDischargeControl} style={{ width: 140 }}>
          <Option value="allow">允许放电</Option>
          <Option value="deny">禁止放电</Option>
        </Select>
        <SettingButton onClick={() => handleSet('放电控制')} />
      </FieldRow>

      <FieldRow label="放电电流限制(A)" range="[0, 110]">
        <InputNumber min={0} max={110} step={0.1} value={dischargeCurrent} onChange={(v) => setDischargeCurrent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('放电电流限制')} />
      </FieldRow>

      <FieldRow label="电池警告电压(V)" range="[40, 50]">
        <InputNumber min={40} max={50} step={0.1} value={batteryWarnVoltage} onChange={(v) => setBatteryWarnVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电池警告电压')} />
      </FieldRow>

      <FieldRow label="电池警告SOC(%)" range="[0, 90]">
        <InputNumber min={0} max={90} value={batteryWarnSoc} onChange={(v) => setBatteryWarnSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电池警告SOC')} />
      </FieldRow>

      <FieldRow label="铅酸电池放电截止电压(V)" range="[40, 50]">
        <InputNumber min={40} max={50} step={0.1} value={leadAcidCutoffVoltage} onChange={(v) => setLeadAcidCutoffVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('铅酸电池放电截止电压')} />
      </FieldRow>

      <FieldRow label="放电截止SOC(%)" range="[0, 90]">
        <InputNumber min={0} max={90} value={cutoffSoc} onChange={(v) => setCutoffSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('放电截止SOC')} />
      </FieldRow>

      <FieldRow label="并网EOD电压(V)" range="[40, 50]">
        <InputNumber min={40} max={50} step={0.1} value={gridEodVoltage} onChange={(v) => setGridEodVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('并网EOD电压')} />
      </FieldRow>

      <FieldRow label="并网截止SOC(%)" range="[0, 90]">
        <InputNumber min={0} max={90} value={gridCutoffSoc} onChange={(v) => setGridCutoffSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('并网截止SOC')} />
      </FieldRow>
    </Row>
  )
}

export default DischargeSection
