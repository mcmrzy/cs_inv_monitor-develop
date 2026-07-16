import React, { useState } from 'react'
import { Row, Col, Select, InputNumber, Divider, App, Typography, Space } from 'antd'
import { FieldRow, SwitchField, SettingButton, labelStyle, fieldRowStyle } from './shared-styles'

const { Text } = Typography
const { Option } = Select

const subTitleStyle: React.CSSProperties = { fontSize: 13, fontWeight: 600, color: '#555', marginBottom: 8 }

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

const ChargeSection: React.FC = () => {
  const { message } = App.useApp()

  // 主充电参数
  const [chargeCurrent, setChargeCurrent] = useState<number>(60)

  // 铅酸充电参数
  const [chargeVoltage, setChargeVoltage] = useState<number>(54)
  const [floatVoltage, setFloatVoltage] = useState<number>(54)
  const [equalVoltage, setEqualVoltage] = useState<number>(56)
  const [equalCycle, setEqualCycle] = useState<number>(30)
  const [equalTime, setEqualTime] = useState<number>(2)

  // 交流充电
  const [acChargeControl, setAcChargeControl] = useState('voltage')
  const [acChargeCurrent, setAcChargeCurrent] = useState<number>(60)
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
  const [acChargeStartVoltage, setAcChargeStartVoltage] = useState<number>(46)
  const [acChargeEndVoltage, setAcChargeEndVoltage] = useState<number>(54)
  const [acChargeStartSoc, setAcChargeStartSoc] = useState<number>(20)
  const [acChargeEndSoc, setAcChargeEndSoc] = useState<number>(90)

  // 发电机充电
  const [genChargeType, setGenChargeType] = useState('manual')
  const [genChargeCurrent, setGenChargeCurrent] = useState<number>(60)
  const [genChargeStartVoltage, setGenChargeStartVoltage] = useState<number>(46)
  const [genChargeEndVoltage, setGenChargeEndVoltage] = useState<number>(54)
  const [genChargeStartSoc, setGenChargeStartSoc] = useState<number>(20)
  const [genChargeEndSoc, setGenChargeEndSoc] = useState<number>(90)
  const [genRatedPower, setGenRatedPower] = useState<number>(3000)
  const [genBoost, setGenBoost] = useState(false)

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 指令已下发`)
  }

  const showVoltage = acChargeControl === 'voltage' || acChargeControl === 'voltage_soc'
  const showSoc = acChargeControl === 'soc' || acChargeControl === 'voltage_soc'

  return (
    <Row gutter={[16, 8]}>
      {/* 主充电参数 */}
      <Col span={24}><Text style={subTitleStyle}>主充电参数</Text></Col>

      <FieldRow label="充电电流限制(A)" range="[0, 110]">
        <InputNumber min={0} max={110} step={0.1} value={chargeCurrent} onChange={(v) => setChargeCurrent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('充电电流限制')} />
      </FieldRow>

      <Col span={24}><Divider style={{ margin: '8px 0' }} /></Col>

      {/* 铅酸充电参数 */}
      <Col span={24}><Text style={subTitleStyle}>铅酸</Text></Col>

      <FieldRow label="充电电压(V)" range="[50, 58]">
        <InputNumber min={50} max={58} step={0.1} value={chargeVoltage} onChange={(v) => setChargeVoltage(v ?? 50)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('充电电压')} />
      </FieldRow>

      <FieldRow label="浮动电压(V)" range="[50, 58]">
        <InputNumber min={50} max={58} step={0.1} value={floatVoltage} onChange={(v) => setFloatVoltage(v ?? 50)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('浮动电压')} />
      </FieldRow>

      <FieldRow label="均衡电压(V)" range="[50, 59]">
        <InputNumber min={50} max={59} step={0.1} value={equalVoltage} onChange={(v) => setEqualVoltage(v ?? 50)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('均衡电压')} />
      </FieldRow>

      <FieldRow label="均衡周期(天)" range="[0, 365]">
        <InputNumber min={0} max={365} value={equalCycle} onChange={(v) => setEqualCycle(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('均衡周期')} />
      </FieldRow>

      <FieldRow label="均衡时间(小时)" range="[0, 24]">
        <InputNumber min={0} max={24} value={equalTime} onChange={(v) => setEqualTime(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('均衡时间')} />
      </FieldRow>

      <Col span={24}><Divider style={{ margin: '8px 0' }} /></Col>

      {/* 交流充电 */}
      <Col span={24}><Text style={subTitleStyle}>交流充电</Text></Col>

      <FieldRow label="AC充电控制依据">
        <Select value={acChargeControl} onChange={setAcChargeControl} style={{ width: 140 }}>
          <Option value="voltage">电池电压</Option>
          <Option value="soc">SOC</Option>
          <Option value="voltage_soc">电压+SOC</Option>
        </Select>
        <SettingButton onClick={() => handleSet('AC充电控制依据')} />
      </FieldRow>

      <FieldRow label="交流充电电池电流(A)" range="[0, 150]">
        <InputNumber min={0} max={150} step={0.1} value={acChargeCurrent} onChange={(v) => setAcChargeCurrent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('交流充电电池电流')} />
      </FieldRow>

      {/* 电压字段 - 依据为 voltage 或 voltage_soc 时显示 */}
      {showVoltage && (
        <>
          <FieldRow label="交流充电开始电池电压(V)" range="[38.4, 52]">
            <InputNumber min={38.4} max={52} step={0.1} value={acChargeStartVoltage} onChange={(v) => setAcChargeStartVoltage(v ?? 38.4)} style={{ width: 140 }} />
            <SettingButton onClick={() => handleSet('交流充电开始电池电压')} />
          </FieldRow>
          <FieldRow label="交流充电结束电池电压(V)" range="[48, 59]">
            <InputNumber min={48} max={59} step={0.1} value={acChargeEndVoltage} onChange={(v) => setAcChargeEndVoltage(v ?? 48)} style={{ width: 140 }} />
            <SettingButton onClick={() => handleSet('交流充电结束电池电压')} />
          </FieldRow>
        </>
      )}

      {/* SOC字段 - 依据为 soc 或 voltage_soc 时显示 */}
      {showSoc && (
        <>
          <FieldRow label="交流充电开始电池SOC(%)" range="[0, 90]">
            <InputNumber min={0} max={90} value={acChargeStartSoc} onChange={(v) => setAcChargeStartSoc(v ?? 0)} style={{ width: 140 }} />
            <SettingButton onClick={() => handleSet('交流充电开始电池SOC')} />
          </FieldRow>
          <FieldRow label="交流充电结束电池SOC(%)" range="[20, 100]">
            <InputNumber min={20} max={100} value={acChargeEndSoc} onChange={(v) => setAcChargeEndSoc(v ?? 20)} style={{ width: 140 }} />
            <SettingButton onClick={() => handleSet('交流充电结束电池SOC')} />
          </FieldRow>
        </>
      )}

      <TimeRangeField label="AC充电起始时间1" h={acStart1H} m={acStart1M} onHChange={(v) => setAcStart1H(v ?? 0)} onMChange={(v) => setAcStart1M(v ?? 0)} onSet={() => handleSet('AC充电起始时间1')} />
      <TimeRangeField label="AC充电结束时间1" h={acEnd1H} m={acEnd1M} onHChange={(v) => setAcEnd1H(v ?? 0)} onMChange={(v) => setAcEnd1M(v ?? 0)} onSet={() => handleSet('AC充电结束时间1')} />
      <TimeRangeField label="AC充电起始时间2" h={acStart2H} m={acStart2M} onHChange={(v) => setAcStart2H(v ?? 0)} onMChange={(v) => setAcStart2M(v ?? 0)} onSet={() => handleSet('AC充电起始时间2')} />
      <TimeRangeField label="AC充电结束时间2" h={acEnd2H} m={acEnd2M} onHChange={(v) => setAcEnd2H(v ?? 0)} onMChange={(v) => setAcEnd2M(v ?? 0)} onSet={() => handleSet('AC充电结束时间2')} />
      <TimeRangeField label="AC充电起始时间3" h={acStart3H} m={acStart3M} onHChange={(v) => setAcStart3H(v ?? 0)} onMChange={(v) => setAcStart3M(v ?? 0)} onSet={() => handleSet('AC充电起始时间3')} />
      <TimeRangeField label="AC充电结束时间3" h={acEnd3H} m={acEnd3M} onHChange={(v) => setAcEnd3H(v ?? 0)} onMChange={(v) => setAcEnd3M(v ?? 0)} onSet={() => handleSet('AC充电结束时间3')} />

      <Col span={24}><Divider style={{ margin: '8px 0' }} /></Col>

      {/* 发电机充电 */}
      <Col span={24}><Text style={subTitleStyle}>发电机充电</Text></Col>

      <FieldRow label="发电机充电类型">
        <Select value={genChargeType} onChange={setGenChargeType} style={{ width: 140 }}>
          <Option value="manual">手动</Option>
          <Option value="auto">自动</Option>
        </Select>
        <SettingButton onClick={() => handleSet('发电机充电类型')} />
      </FieldRow>

      <FieldRow label="发电机充电电池电流(A)" range="[0, 110]">
        <InputNumber min={0} max={110} step={0.1} value={genChargeCurrent} onChange={(v) => setGenChargeCurrent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('发电机充电电池电流')} />
      </FieldRow>

      <FieldRow label="发电机充电开始电池电压(V)" range="[38.4, 52]">
        <InputNumber min={38.4} max={52} step={0.1} value={genChargeStartVoltage} onChange={(v) => setGenChargeStartVoltage(v ?? 38.4)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('发电机充电开始电池电压')} />
      </FieldRow>

      <FieldRow label="发电机充电结束电池电压(V)" range="[48, 59]">
        <InputNumber min={48} max={59} step={0.1} value={genChargeEndVoltage} onChange={(v) => setGenChargeEndVoltage(v ?? 48)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('发电机充电结束电池电压')} />
      </FieldRow>

      <FieldRow label="发电机充电开始电池SOC(%)" range="[0, 90]">
        <InputNumber min={0} max={90} value={genChargeStartSoc} onChange={(v) => setGenChargeStartSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('发电机充电开始电池SOC')} />
      </FieldRow>

      <FieldRow label="发电机充电结束电池SOC(%)" range="[20, 100]">
        <InputNumber min={20} max={100} value={genChargeEndSoc} onChange={(v) => setGenChargeEndSoc(v ?? 20)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('发电机充电结束电池SOC')} />
      </FieldRow>

      <FieldRow label="发电机额定功率(W)" range="[0, 7370]">
        <InputNumber min={0} max={7370} value={genRatedPower} onChange={(v) => setGenRatedPower(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('发电机额定功率')} />
      </FieldRow>

      <SwitchField label="发电机提升" checked={genBoost} onChange={(v) => { setGenBoost(v); handleSet('发电机提升') }} enableText="启用" disableText="禁用" />
    </Row>
  )
}

export default ChargeSection
