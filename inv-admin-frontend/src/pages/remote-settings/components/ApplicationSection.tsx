import React, { useState } from 'react'
import { Row, Col, Select, InputNumber, App, Typography, Space } from 'antd'
import { FieldRow, SwitchField, SettingButton, PRIMARY, labelStyle, fieldRowStyle } from './shared-styles'

const { Text } = Typography
const { Option } = Select

interface TimeRangeFieldProps {
  label: string
  h: number
  m: number
  onHChange: (v: number | null) => void
  onMChange: (v: number | null) => void
  onSet: () => void
}

const TimeRangeField: React.FC<TimeRangeFieldProps> = ({ label, h, m, onHChange, onMChange, onSet }) => (
  <Col span={24}>
    <div style={fieldRowStyle}>
      <Text style={labelStyle}>{label}</Text>
      <Space>
        <InputNumber min={0} max={23} value={h} onChange={onHChange} style={{ width: 70 }} addonAfter="时" />
        <Text>:</Text>
        <InputNumber min={0} max={59} value={m} onChange={onMChange} style={{ width: 70 }} addonAfter="分" />
        <SettingButton onClick={onSet} />
      </Space>
    </div>
  </Col>
)

const ApplicationSection: React.FC = () => {
  const { message } = App.useApp()

  const [outputVoltage, setOutputVoltage] = useState('220')
  const [outputFreq, setOutputFreq] = useState('50')
  const [acInputRange, setAcInputRange] = useState('wide')
  const [pvOffGrid, setPvOffGrid] = useState(false)
  const [acFirst, setAcFirst] = useState(false)

  const [acStart1H, setAcStart1H] = useState(0)
  const [acStart1M, setAcStart1M] = useState(0)
  const [acEnd1H, setAcEnd1H] = useState(0)
  const [acEnd1M, setAcEnd1M] = useState(0)
  const [acStart2H, setAcStart2H] = useState(0)
  const [acStart2M, setAcStart2M] = useState(0)
  const [acEnd2H, setAcEnd2H] = useState(0)
  const [acEnd2M, setAcEnd2M] = useState(0)
  const [acStart3H, setAcStart3H] = useState(0)
  const [acStart3M, setAcStart3M] = useState(0)
  const [acEnd3H, setAcEnd3H] = useState(0)
  const [acEnd3M, setAcEnd3M] = useState(0)

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 指令已下发`)
  }

  return (
    <Row gutter={[16, 8]}>
      <FieldRow label="离网输出电压设置(V)">
        <Select value={outputVoltage} onChange={setOutputVoltage} style={{ width: 140 }}>
          <Option value="220">220</Option>
          <Option value="230">230</Option>
          <Option value="240">240</Option>
        </Select>
        <SettingButton onClick={() => handleSet('离网输出电压设置')} />
      </FieldRow>

      <FieldRow label="离网输出频率设置(Hz)">
        <Select value={outputFreq} onChange={setOutputFreq} style={{ width: 140 }}>
          <Option value="50">50</Option>
          <Option value="60">60</Option>
        </Select>
        <SettingButton onClick={() => handleSet('离网输出频率设置')} />
      </FieldRow>

      <FieldRow label="交流输入范围">
        <Select value={acInputRange} onChange={setAcInputRange} style={{ width: 140 }}>
          <Option value="wide">宽范围</Option>
          <Option value="narrow">窄范围</Option>
        </Select>
        <SettingButton onClick={() => handleSet('交流输入范围')} />
      </FieldRow>

      <SwitchField label="PV离网" checked={pvOffGrid} onChange={(v) => { setPvOffGrid(v); handleSet('PV离网') }} enableText="启用" disableText="禁用" />
      <SwitchField label="先使用交流电" checked={acFirst} onChange={(v) => { setAcFirst(v); handleSet('先使用交流电') }} enableText="启用" disableText="禁用" />

      {/* AC优先时间段 - 仅 acFirst 开启时显示 */}
      {acFirst ? (
        <>
          <TimeRangeField label="交流电优先启动时间 1" h={acStart1H} m={acStart1M} onHChange={(v) => setAcStart1H(v ?? 0)} onMChange={(v) => setAcStart1M(v ?? 0)} onSet={() => handleSet('交流电优先启动时间1')} />
          <TimeRangeField label="交流电优先结束时间 1" h={acEnd1H} m={acEnd1M} onHChange={(v) => setAcEnd1H(v ?? 0)} onMChange={(v) => setAcEnd1M(v ?? 0)} onSet={() => handleSet('交流电优先结束时间1')} />
          <TimeRangeField label="交流电优先启动时间 2" h={acStart2H} m={acStart2M} onHChange={(v) => setAcStart2H(v ?? 0)} onMChange={(v) => setAcStart2M(v ?? 0)} onSet={() => handleSet('交流电优先启动时间2')} />
          <TimeRangeField label="交流电优先结束时间 2" h={acEnd2H} m={acEnd2M} onHChange={(v) => setAcEnd2H(v ?? 0)} onMChange={(v) => setAcEnd2M(v ?? 0)} onSet={() => handleSet('交流电优先结束时间2')} />
          <TimeRangeField label="交流电优先启动时间 3" h={acStart3H} m={acStart3M} onHChange={(v) => setAcStart3H(v ?? 0)} onMChange={(v) => setAcStart3M(v ?? 0)} onSet={() => handleSet('交流电优先启动时间3')} />
          <TimeRangeField label="交流电优先结束时间 3" h={acEnd3H} m={acEnd3M} onHChange={(v) => setAcEnd3H(v ?? 0)} onMChange={(v) => setAcEnd3M(v ?? 0)} onSet={() => handleSet('交流电优先结束时间3')} />
        </>
      ) : (
        <Col span={24}>
          <div style={{ padding: '12px 0', color: '#bbb', fontSize: 13 }}>
            启用"先使用交流电"后可配置优先时间段
          </div>
        </Col>
      )}
    </Row>
  )
}

export default ApplicationSection
