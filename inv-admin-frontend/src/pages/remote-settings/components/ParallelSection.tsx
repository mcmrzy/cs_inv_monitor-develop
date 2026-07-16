import React, { useState } from 'react'
import { Row, Select, App } from 'antd'
import { FieldRow, SwitchField, SettingButton } from './shared-styles'

const { Option } = Select

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
    <Row gutter={[16, 8]}>
      <FieldRow label="系统类型">
        <Select value={systemType} onChange={setSystemType} style={{ width: 140 }}>
          <Option value="single">单机</Option>
          <Option value="single_phase_parallel">单相并联</Option>
          <Option value="three_phase_parallel">三相并联</Option>
        </Select>
        <SettingButton onClick={() => handleSet('系统类型')} />
      </FieldRow>

      <FieldRow label="设置组网相位">
        <Select value={gridPhase} onChange={setGridPhase} style={{ width: 140 }}>
          <Option value="L1">L1</Option>
          <Option value="L2">L2</Option>
          <Option value="L3">L3</Option>
        </Select>
        <SettingButton onClick={() => handleSet('设置组网相位')} />
      </FieldRow>

      <SwitchField label="共用电池" checked={sharedBattery} onChange={(v) => { setSharedBattery(v); handleSet('共用电池') }} />
      <SwitchField label="无市电输入" checked={noGridInput} onChange={(v) => { setNoGridInput(v); handleSet('无市电输入') }} />
    </Row>
  )
}

export default ParallelSection
