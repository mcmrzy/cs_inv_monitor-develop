import React, { useState } from 'react'
import { Row, Col, Select, InputNumber, App, Typography, Space, Tooltip, Switch } from 'antd'
import { QuestionCircleOutlined } from '@ant-design/icons'
import { FieldRow, SwitchField, SettingButton, SubGroupTitle, SubGroupHelp, PRIMARY, labelStyle, fieldRowStyle } from './shared-styles'

const { Text } = Typography
const { Option } = Select

interface TimeRangeFieldProps {
  label: string
  h: number
  m: number
  onHChange: (v: number | null) => void
  onMChange: (v: number | null) => void
  onSet: () => void
  tooltip?: string
}

const TimeRangeField: React.FC<TimeRangeFieldProps> = ({ label, h, m, onHChange, onMChange, onSet, tooltip }) => (
  <Col span={24}>
    <div style={fieldRowStyle}>
      <Text style={labelStyle}>
        {label}
        {tooltip && (
          <Tooltip title={tooltip} overlayStyle={{ maxWidth: 360 }}>
            <QuestionCircleOutlined style={{ marginLeft: 4, color: '#bbb', cursor: 'help', fontSize: 13 }} />
          </Tooltip>
        )}
      </Text>
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
  const [acInputRange, setAcInputRange] = useState<number>(0)
  const [pvOffGrid, setPvOffGrid] = useState(false)
  const [nPeConnection, setNPeConnection] = useState(false)
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

  // 混合设置
  const [pvAcLoad, setPvAcLoad] = useState(false)
  const [feedToGrid, setFeedToGrid] = useState(false)
  const [outputPowerPercent, setOutputPowerPercent] = useState<number>(0)

  // 并联设置
  const [systemType, setSystemType] = useState<number>(0)
  const [sharedBattery, setSharedBattery] = useState(false)
  const [composedPhase, setComposedPhase] = useState<number>(1)

  // 无市电输入
  const [noGridInput, setNoGridInput] = useState(false)

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 指令已下发`)
  }

  return (
    <Row gutter={[16, 8]}>
      <FieldRow label="离网输出电压设置(V)" tooltip="设置电压以适应额定电网电压。">
        <Select value={outputVoltage} onChange={setOutputVoltage} style={{ width: 140 }} showSearch>
          <Option value="220">220</Option>
          <Option value="230">230</Option>
          <Option value="240">240</Option>
        </Select>
        <SettingButton onClick={() => handleSet('离网输出电压设置')} />
      </FieldRow>

      <FieldRow label="离网输出频率设置(Hz)" tooltip="选择电网频率。">
        <Select value={outputFreq} onChange={setOutputFreq} style={{ width: 140 }} showSearch>
          <Option value="50">50</Option>
          <Option value="60">60</Option>
        </Select>
        <SettingButton onClick={() => handleSet('离网输出频率设置')} />
      </FieldRow>

      <FieldRow label="交流输入范围" tooltip="APL：电网电压范围 90~280Vac，逆变器切换时间超过 20ms；UPS：电网电压范围 170~280Vac，在单个逆变器使用时逆变器切换时间在 20ms以内。">
        <Select value={acInputRange} onChange={setAcInputRange} style={{ width: 280 }} showSearch>
          <Option value={0}>APL(公用电范围90-280V 20毫秒)</Option>
          <Option value={1}>UPS(公用电范围170-280V 10毫秒)</Option>
        </Select>
        <SettingButton onClick={() => handleSet('交流输入范围')} />
      </FieldRow>

      <SwitchField label="PV离网" checked={pvOffGrid} onChange={(v) => { setPvOffGrid(v); handleSet('PV离网') }} enableText="启用" disableText="禁用" tooltip="在没有电池且仅有太阳能输入时允许访问离网模式。" />
      <SwitchField label="N-PE连接" checked={nPeConnection} onChange={(v) => { setNPeConnection(v); handleSet('N-PE连接') }} enableText="启用" disableText="禁用" tooltip="启用EPS中性线(N)和交流接地(PE)连接。" />
      <SubGroupHelp title="先使用交流电" color="#3b82f6" helpItems={[{ label: '说明', value: '逆变器将在交流首次时间帧内始终优先承载负载' }]} />
      <SwitchField label="先使用交流电" checked={acFirst} onChange={(v) => { setAcFirst(v); handleSet('先使用交流电') }} enableText="启用" disableText="禁用" tooltip="逆变器将在交流首次时间帧内始终优先承载负载。" />

      {/* AC优先时间段 - 仅 acFirst 开启时显示 */}
      {acFirst ? (
        <>
          <TimeRangeField label="交流电优先启动时间 1" h={acStart1H} m={acStart1M} onHChange={(v) => setAcStart1H(v ?? 0)} onMChange={(v) => setAcStart1M(v ?? 0)} onSet={() => handleSet('交流电优先启动时间1')} tooltip="设置范围为 00:00~23:59" />
          <TimeRangeField label="交流电优先结束时间 1" h={acEnd1H} m={acEnd1M} onHChange={(v) => setAcEnd1H(v ?? 0)} onMChange={(v) => setAcEnd1M(v ?? 0)} onSet={() => handleSet('交流电优先结束时间1')} tooltip="设置范围为 00:00~23:59" />
          <TimeRangeField label="交流电优先启动时间 2" h={acStart2H} m={acStart2M} onHChange={(v) => setAcStart2H(v ?? 0)} onMChange={(v) => setAcStart2M(v ?? 0)} onSet={() => handleSet('交流电优先启动时间2')} tooltip="设置范围为 00:00~23:59" />
          <TimeRangeField label="交流电优先结束时间 2" h={acEnd2H} m={acEnd2M} onHChange={(v) => setAcEnd2H(v ?? 0)} onMChange={(v) => setAcEnd2M(v ?? 0)} onSet={() => handleSet('交流电优先结束时间2')} tooltip="设置范围为 00:00~23:59" />
          <TimeRangeField label="交流电优先启动时间 3" h={acStart3H} m={acStart3M} onHChange={(v) => setAcStart3H(v ?? 0)} onMChange={(v) => setAcStart3M(v ?? 0)} onSet={() => handleSet('交流电优先启动时间3')} tooltip="设置范围为 00:00~23:59" />
          <TimeRangeField label="交流电优先结束时间 3" h={acEnd3H} m={acEnd3M} onHChange={(v) => setAcEnd3H(v ?? 0)} onMChange={(v) => setAcEnd3M(v ?? 0)} onSet={() => handleSet('交流电优先结束时间3')} tooltip="设置范围为 00:00~23:59" />
        </>
      ) : (
        <Col span={24}>
          <div style={{ padding: '12px 0', color: '#bbb', fontSize: 13 }}>
            启用"先使用交流电"后可配置优先时间段
          </div>
        </Col>
      )}

      {/* 混合设置 */}
      <SubGroupHelp title="混合设置" color="#3b82f6" />
      <SwitchField label="光伏与交流共同负荷" checked={pvAcLoad} onChange={(v) => { setPvAcLoad(v); handleSet('光伏与交流共同负荷') }} enableText="启用" disableText="禁用" tooltip="PV与交流共同负载启用：在交流首次时间帧或交流充电条件下（根据时间/电压/SOC），如果有多余的能量，光伏将首先给电池充电并承担负载，交流将提供其余所需的能量。在交流首次时间帧或交流充电条件之外，光伏将承担负载并给电池充电，或者光伏和电池共同承担负载。" />
      <FieldRow label="送电至电网" tooltip="当启用'光伏与交流共同负载'时，逆变器可以在满足所有负载和电池充电需求后，将多余的光伏电力馈送到电网中。">
        <Switch checked={feedToGrid} onChange={(v) => { setFeedToGrid(v); handleSet('送电至电网') }} />
      </FieldRow>

      <FieldRow label="输出功率百分比(%)" tooltip="逆变器可以设置馈入功率百分比从 0% 到 100%。">
        <InputNumber min={0} max={100} value={outputPowerPercent} onChange={(v) => setOutputPowerPercent(v ?? 0)} style={{ width: 120 }} />
        <SettingButton onClick={() => handleSet('输出功率百分比')} />
      </FieldRow>

      {/* 并联设置 */}
      <SubGroupTitle title="并联设置" />

      <FieldRow label="系统类型" tooltip="用于并联逆变器时。只能在待机模式或故障状态下设置。">
        <Select value={systemType} onChange={setSystemType} style={{ width: 140 }} showSearch>
          <Option value={0}>单机</Option>
          <Option value={1}>单相并机</Option>
          <Option value={3}>三相并机</Option>
        </Select>
        <SettingButton onClick={() => handleSet('系统类型')} />
      </FieldRow>

      <SwitchField label="共用电池" checked={sharedBattery} onChange={(v) => { setSharedBattery(v); handleSet('共用电池') }} enableText="启用" disableText="禁用" tooltip="当逆变器在并联逆变器系统中共享一个电池组时，启用电池共享。" />

      <FieldRow label="设置组网相位" tooltip="用于设置EPS相位（如果未自动设置）。只能在待机模式或故障状态下设置。">
        <Select value={composedPhase} onChange={setComposedPhase} style={{ width: 140 }} showSearch>
          <Option value={1}>R 相</Option>
          <Option value={2}>S 相</Option>
          <Option value={3}>T 相</Option>
        </Select>
        <SettingButton onClick={() => handleSet('设置组网相位')} />
      </FieldRow>

      {/* 无市电输入 */}
      <SwitchField label="无市电输入" checked={noGridInput} onChange={(v) => { setNoGridInput(v); handleSet('无市电输入') }} enableText="启用" disableText="禁用" />
    </Row>
  )
}

export default ApplicationSection
