import React, { useState } from 'react'
import { Row, Select, InputNumber, App } from 'antd'
import { FieldRow, SwitchField, SettingButton } from './shared-styles'

const { Option } = Select

interface Props {
  deviceInfo: any
}

const PowerControlSection: React.FC<Props> = ({ deviceInfo }) => {
  const { message } = App.useApp()

  const [freqDeratingEnable, setFreqDeratingEnable] = useState(false)
  const [reactivePowerMode, setReactivePowerMode] = useState('fixed_pf')
  const [reactivePowerPercent, setReactivePowerPercent] = useState<number>(0)
  const [pfValue, setPfValue] = useState<number>(1000)
  const [activePowerPercent, setActivePowerPercent] = useState<number>(100)
  const [gridSoftStart, setGridSoftStart] = useState(false)
  const [gridProtectionLevel, setGridProtectionLevel] = useState('level1')
  const [v1UnderVoltage, setV1UnderVoltage] = useState<number>(176)
  const [v1OverVoltage, setV1OverVoltage] = useState<number>(264)
  const [f1UnderFreq, setF1UnderFreq] = useState<number>(45)
  const [f1OverFreq, setF1OverFreq] = useState<number>(55)
  const [vMovingAvgOverVoltage, setVMovingAvgOverVoltage] = useState<number>(264)
  const [v2UnderVoltage, setV2UnderVoltage] = useState<number>(176)
  const [v2OverVoltage, setV2OverVoltage] = useState<number>(264)
  const [f2UnderFreq, setF2UnderFreq] = useState<number>(45)
  const [f2OverFreq, setF2OverFreq] = useState<number>(55)
  const [rampRate, setRampRate] = useState<number>(50)
  const [v3UnderVoltage, setV3UnderVoltage] = useState<number>(176)
  const [v3OverVoltage, setV3OverVoltage] = useState<number>(264)
  const [f3UnderFreq, setF3UnderFreq] = useState<number>(45)
  const [f3OverFreq, setF3OverFreq] = useState<number>(55)

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 指令已下发`)
  }

  return (
    <Row gutter={[16, 8]}>
      <SwitchField label="过频降载使能" checked={freqDeratingEnable} onChange={(v) => { setFreqDeratingEnable(v); handleSet('过频降载使能') }} />

      <FieldRow label="无功输出模式">
        <Select value={reactivePowerMode} onChange={setReactivePowerMode} style={{ width: 140 }}>
          <Option value="fixed_pf">固定功率因数</Option>
          <Option value="fixed_q">固定无功功率</Option>
          <Option value="volt_var">电压-无功曲线</Option>
          <Option value="pf_p">功率因数-有功曲线</Option>
        </Select>
        <SettingButton onClick={() => handleSet('无功输出模式')} />
      </FieldRow>

      <FieldRow label="无功百分比设定值(%)" range="0~60">
        <InputNumber min={0} max={60} value={reactivePowerPercent} onChange={(v) => setReactivePowerPercent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('无功百分比设定值')} />
      </FieldRow>

      <FieldRow label="PF设定值" range="750~2000">
        <InputNumber min={750} max={2000} value={pfValue} onChange={(v) => setPfValue(v ?? 750)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('PF设定值')} />
      </FieldRow>

      <FieldRow label="有功百分比设定值(%)" range="0~100">
        <InputNumber min={0} max={100} value={activePowerPercent} onChange={(v) => setActivePowerPercent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('有功百分比设定值')} />
      </FieldRow>

      <SwitchField label="电网软启动" checked={gridSoftStart} onChange={(v) => { setGridSoftStart(v); handleSet('电网软启动') }} />

      <FieldRow label="市电保护等级">
        <Select value={gridProtectionLevel} onChange={setGridProtectionLevel} style={{ width: 140 }}>
          <Option value="level1">1级保护</Option>
          <Option value="level2">2级保护</Option>
          <Option value="level3">3级保护</Option>
        </Select>
        <SettingButton onClick={() => handleSet('市电保护等级')} />
      </FieldRow>

      <FieldRow label="电网电压1级欠压保护点(V)">
        <InputNumber value={v1UnderVoltage} onChange={(v) => setV1UnderVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网电压1级欠压保护点')} />
      </FieldRow>

      <FieldRow label="电网电压1级过压保护点(V)">
        <InputNumber value={v1OverVoltage} onChange={(v) => setV1OverVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网电压1级过压保护点')} />
      </FieldRow>

      <FieldRow label="电网频率1级欠频保护点(Hz)">
        <InputNumber value={f1UnderFreq} onChange={(v) => setF1UnderFreq(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网频率1级欠频保护点')} />
      </FieldRow>

      <FieldRow label="电网频率1级过频保护点(Hz)">
        <InputNumber value={f1OverFreq} onChange={(v) => setF1OverFreq(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网频率1级过频保护点')} />
      </FieldRow>

      <FieldRow label="电网电压滑动平均过压保护点(V)">
        <InputNumber value={vMovingAvgOverVoltage} onChange={(v) => setVMovingAvgOverVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网电压滑动平均过压保护点')} />
      </FieldRow>

      <FieldRow label="电网电压2级欠压保护点(V)">
        <InputNumber value={v2UnderVoltage} onChange={(v) => setV2UnderVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网电压2级欠压保护点')} />
      </FieldRow>

      <FieldRow label="电网电压2级过压保护点(V)">
        <InputNumber value={v2OverVoltage} onChange={(v) => setV2OverVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网电压2级过压保护点')} />
      </FieldRow>

      <FieldRow label="电网频率2级欠频保护点(Hz)">
        <InputNumber value={f2UnderFreq} onChange={(v) => setF2UnderFreq(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网频率2级欠频保护点')} />
      </FieldRow>

      <FieldRow label="电网频率2级过频保护点(Hz)">
        <InputNumber value={f2OverFreq} onChange={(v) => setF2OverFreq(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网频率2级过频保护点')} />
      </FieldRow>

      <FieldRow label="加载速率(%/min)" range="1~100">
        <InputNumber min={1} max={100} value={rampRate} onChange={(v) => setRampRate(v ?? 1)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('加载速率')} />
      </FieldRow>

      <FieldRow label="电网电压3级欠压保护点(V)">
        <InputNumber value={v3UnderVoltage} onChange={(v) => setV3UnderVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网电压3级欠压保护点')} />
      </FieldRow>

      <FieldRow label="电网电压3级过压保护点(V)">
        <InputNumber value={v3OverVoltage} onChange={(v) => setV3OverVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网电压3级过压保护点')} />
      </FieldRow>

      <FieldRow label="电网频率3级欠频保护点(Hz)">
        <InputNumber value={f3UnderFreq} onChange={(v) => setF3UnderFreq(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网频率3级欠频保护点')} />
      </FieldRow>

      <FieldRow label="电网频率3级过频保护点(Hz)">
        <InputNumber value={f3OverFreq} onChange={(v) => setF3OverFreq(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('电网频率3级过频保护点')} />
      </FieldRow>
    </Row>
  )
}

export default PowerControlSection
