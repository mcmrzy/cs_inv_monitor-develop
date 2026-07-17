import React, { useState } from 'react'
import { Row, Col, Select, InputNumber, App, Typography, Space, Tooltip } from 'antd'
import { QuestionCircleOutlined } from '@ant-design/icons'
import { FieldRow, SwitchField, SubGroupTitle, SettingButton, labelStyle, fieldRowStyle, SECTION_COLORS, disabledInputStyle } from './shared-styles'

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
  disabled?: boolean
}

const TimeRangeField: React.FC<TimeRangeFieldProps> = ({ label, h, m, onHChange, onMChange, onSet, tooltip, disabled }) => (
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
        <InputNumber min={0} max={23} value={h} onChange={onHChange} style={{ width: 70, ...(disabled ? disabledInputStyle : {}) }} addonAfter="时" disabled={disabled} />
        <Text>:</Text>
        <InputNumber min={0} max={59} value={m} onChange={onMChange} style={{ width: 70, ...(disabled ? disabledInputStyle : {}) }} addonAfter="分" disabled={disabled} />
        <SettingButton onClick={onSet} disabled={disabled} />
      </Space>
    </div>
  </Col>
)

const DischargeSection: React.FC = () => {
  const { message } = App.useApp()

  // 放电控制
  const [dischargeControl, setDischargeControl] = useState<number>(0)
  const [dischargeCurrent, setDischargeCurrent] = useState<number>(60)

  // 电压模式字段
  const [batteryWarnVoltage, setBatteryWarnVoltage] = useState<number>(46)
  const [leadAcidCutoffVoltage, setLeadAcidCutoffVoltage] = useState<number>(44)
  const [gridEodVoltage, setGridEodVoltage] = useState<number>(44)

  // SOC模式字段
  const [batteryWarnSoc, setBatteryWarnSoc] = useState<number>(20)
  const [cutoffSoc, setCutoffSoc] = useState<number>(10)
  const [gridCutoffSoc, setGridCutoffSoc] = useState<number>(10)

  // 交流耦合
  const [acCoupleEnabled, setAcCoupleEnabled] = useState<boolean>(false)
  const [acCoupleStartVoltage, setAcCoupleStartVoltage] = useState<number>(48)
  const [acCoupleStartSoc, setAcCoupleStartSoc] = useState<number>(30)
  const [acCoupleCutoffVoltage, setAcCoupleCutoffVoltage] = useState<number>(52)
  const [acCoupleCutoffSoc, setAcCoupleCutoffSoc] = useState<number>(50)

  // 独立字段
  const [dischargePowerPercent, setDischargePowerPercent] = useState<number>(100)
  const [gridDischargeCutoffSoc, setGridDischargeCutoffSoc] = useState<number>(10)
  const [offgridDischargeCutoffSoc, setOffgridDischargeCutoffSoc] = useState<number>(10)
  const [dischargeStartPower, setDischargeStartPower] = useState<number>(100)

  // 智能负载
  const [smartLoadEnabled, setSmartLoadEnabled] = useState<boolean>(false)
  const [smartLoadStartPv, setSmartLoadStartPv] = useState<number>(3)
  const [smartLoadGridAlwaysOn, setSmartLoadGridAlwaysOn] = useState<boolean>(false)
  const [smartLoadStartVoltage, setSmartLoadStartVoltage] = useState<number>(48)
  const [smartLoadStartSoc, setSmartLoadStartSoc] = useState<number>(30)
  const [smartLoadCutoffVoltage, setSmartLoadCutoffVoltage] = useState<number>(44)
  const [smartLoadCutoffSoc, setSmartLoadCutoffSoc] = useState<number>(10)

  // 强制放电
  const [forceDischargeEnable, setForceDischargeEnable] = useState<boolean>(false)
  const [forceDischargePowerPercent, setForceDischargePowerPercent] = useState<number>(10)
  const [forceDischargeCutoffSoc, setForceDischargeCutoffSoc] = useState<number>(20)
  const [forceStart0H, setForceStart0H] = useState<number>(0)
  const [forceStart0M, setForceStart0M] = useState<number>(0)
  const [forceEnd0H, setForceEnd0H] = useState<number>(0)
  const [forceEnd0M, setForceEnd0M] = useState<number>(0)
  const [forceStart1H, setForceStart1H] = useState<number>(0)
  const [forceStart1M, setForceStart1M] = useState<number>(0)
  const [forceEnd1H, setForceEnd1H] = useState<number>(0)
  const [forceEnd1M, setForceEnd1M] = useState<number>(0)
  const [forceStart2H, setForceStart2H] = useState<number>(0)
  const [forceStart2M, setForceStart2M] = useState<number>(0)
  const [forceEnd2H, setForceEnd2H] = useState<number>(0)
  const [forceEnd2M, setForceEnd2M] = useState<number>(0)

  // 联动控制便捷变量
  const voltageEnabled = dischargeControl === 0
  const socEnabled = dischargeControl === 1

  // 交流耦合子字段：仅在开关开启时启用
  const acCoupleFieldDisabled = !acCoupleEnabled

  // 智能负载子字段：仅在开关开启时启用
  const smartLoadFieldDisabled = !smartLoadEnabled

  // 强制放电子字段：仅在开关开启时启用
  const forceDischargeDisabled = !forceDischargeEnable

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 指令已下发`)
  }

  const sectionColor = SECTION_COLORS.discharge

  return (
    <Row gutter={[0, 8]}>
      {/* 放电控制 */}
      <FieldRow
        label="放电控制"
        tooltip="1: 在使用铅酸电池或在铅酸模式下使用锂电池时，根据电压选择。2: 在使用兼容的锂电池时，根据SOC选择。"
      >
        <Select value={dischargeControl} onChange={setDischargeControl} style={{ width: 140 }}>
          <Option value={0}>电压 (根据)</Option>
          <Option value={1}>SOC (根据)</Option>
        </Select>
        <SettingButton onClick={() => handleSet('放电控制')} />
      </FieldRow>

      {/* 放电电流限制 - 始终启用 */}
      <FieldRow
        label="放电电流限制(Adc)"
        range="[1, 110（单台）4480（并联）]"
        tooltip="根据电池要求进行设置，范围：1~110（单台）4480（并联）。"
      >
        <InputNumber min={0} max={110} step={0.1} value={dischargeCurrent} onChange={(v) => setDischargeCurrent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('放电电流限制')} />
      </FieldRow>

      {/* 电压模式字段 */}
      <FieldRow
        label="电池警告电压(V)"
        range="[40, 50]"
        tooltip="当电池电压达到您设置的值时，逆变器将显示电池低电压警告，建议范围：40~50V。"
      >
        <InputNumber disabled={!voltageEnabled} min={40} max={50} step={0.1} value={batteryWarnVoltage} onChange={(v) => setBatteryWarnVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled} onClick={() => handleSet('电池警告电压')} />
      </FieldRow>

      <FieldRow
        label="铅酸电池放电截止电压(V)"
        range="[40, 50]"
        tooltip="离网EOD电压，根据电池要求进行设置，范围：40V~50V。"
      >
        <InputNumber disabled={!voltageEnabled} min={40} max={50} step={0.1} value={leadAcidCutoffVoltage} onChange={(v) => setLeadAcidCutoffVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled} onClick={() => handleSet('铅酸电池放电截止电压')} />
      </FieldRow>

      <FieldRow
        label="并网EOD电压(V)"
        range="[40, 56]"
        tooltip="当电池达到您设置的值时，它将停止放电，交流电将介入，范围：40~56V。"
      >
        <InputNumber disabled={!voltageEnabled} min={40} max={56} step={0.1} value={gridEodVoltage} onChange={(v) => setGridEodVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled} onClick={() => handleSet('并网EOD电压')} />
      </FieldRow>

      {/* SOC模式字段 */}
      <FieldRow
        label="电池警告SOC(%)"
        range="[0, 90]"
        tooltip="当电池达到您设置的值时，逆变器将显示电池低电压警告，建议范围：0~90%。"
      >
        <InputNumber disabled={!socEnabled} min={0} max={90} value={batteryWarnSoc} onChange={(v) => setBatteryWarnSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled} onClick={() => handleSet('电池警告SOC')} />
      </FieldRow>

      <FieldRow
        label="放电截止SOC(%)"
        range="[0, 90]"
        tooltip="离网EOD SOC，根据电池要求进行设置，范围：0~90%。"
      >
        <InputNumber disabled={!socEnabled} min={0} max={90} value={cutoffSoc} onChange={(v) => setCutoffSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled} onClick={() => handleSet('放电截止SOC')} />
      </FieldRow>

      <FieldRow
        label="并网截止SOC(%)"
        range="[0, 90]"
        tooltip="当电池达到您设置的值时，它将停止放电，交流电将介入，范围：0%~90%。"
      >
        <InputNumber disabled={!socEnabled} min={0} max={90} value={gridCutoffSoc} onChange={(v) => setGridCutoffSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled} onClick={() => handleSet('并网截止SOC')} />
      </FieldRow>

      {/* 独立字段 */}
      <FieldRow
        label="放电功率百分比(%)"
        range="[0, 100]"
        tooltip="设置放电功率百分比"
      >
        <InputNumber min={0} max={100} value={dischargePowerPercent} onChange={(v) => setDischargePowerPercent(v ?? 100)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('放电功率百分比')} />
      </FieldRow>

      <FieldRow
        label="并网放电截止SOC限值(%)"
        range="[0, 100]"
        tooltip="并网模式下放电截止SOC"
      >
        <InputNumber min={0} max={100} value={gridDischargeCutoffSoc} onChange={(v) => setGridDischargeCutoffSoc(v ?? 10)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('并网放电截止SOC限值')} />
      </FieldRow>

      <FieldRow
        label="离网放电截止SOC限值(%)"
        range="[0, 100]"
        tooltip="离网模式下放电截止SOC"
      >
        <InputNumber min={0} max={100} value={offgridDischargeCutoffSoc} onChange={(v) => setOffgridDischargeCutoffSoc(v ?? 10)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('离网放电截止SOC限值')} />
      </FieldRow>

      <FieldRow
        label="放电起始功率设置(W)"
        range="[0, 65535]"
        tooltip="设置放电起始功率"
      >
        <InputNumber min={0} max={65535} value={dischargeStartPower} onChange={(v) => setDischargeStartPower(v ?? 100)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('放电起始功率设置')} />
      </FieldRow>

      {/* 交流耦合子分组 */}
      <SubGroupTitle title="交流耦合" color={sectionColor} />

      <SwitchField
        label="交流耦合"
        checked={acCoupleEnabled}
        onChange={setAcCoupleEnabled}
        tooltip="将现有的并网光伏逆变器连接到发电端口作为交流耦合系统。在并网模式下，请启用电网回售或离网模式。在离网模式下，请确保光伏逆变器已启用频率转移功能。"
      />

      {/* AC Couple 电压字段 */}
      <FieldRow label="AC Couple启动电压(V)" range="[40, 59.5]">
        <InputNumber disabled={!voltageEnabled || acCoupleFieldDisabled} min={40} max={59.5} step={0.1} value={acCoupleStartVoltage} onChange={(v) => setAcCoupleStartVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled || acCoupleFieldDisabled} onClick={() => handleSet('AC Couple启动电压')} />
      </FieldRow>

      <FieldRow label="AC Couple截止电压(V)" range="[42, 80]">
        <InputNumber disabled={!voltageEnabled || acCoupleFieldDisabled} min={42} max={80} value={acCoupleCutoffVoltage} onChange={(v) => setAcCoupleCutoffVoltage(v ?? 42)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled || acCoupleFieldDisabled} onClick={() => handleSet('AC Couple截止电压')} />
      </FieldRow>

      {/* AC Couple SOC字段 */}
      <FieldRow label="AC Couple启动SOC(%)" range="[0, 80]">
        <InputNumber disabled={!socEnabled || acCoupleFieldDisabled} min={0} max={80} value={acCoupleStartSoc} onChange={(v) => setAcCoupleStartSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled || acCoupleFieldDisabled} onClick={() => handleSet('AC Couple启动SOC')} />
      </FieldRow>

      <FieldRow label="AC Couple截止SOC(%)" range="[0, 100]">
        <InputNumber disabled={!socEnabled || acCoupleFieldDisabled} min={0} max={100} value={acCoupleCutoffSoc} onChange={(v) => setAcCoupleCutoffSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled || acCoupleFieldDisabled} onClick={() => handleSet('AC Couple截止SOC')} />
      </FieldRow>

      {/* 智能负载子分组 */}
      <SubGroupTitle title="智能负载" color={sectionColor} />

      <SwitchField
        label="智能负载"
        checked={smartLoadEnabled}
        onChange={setSmartLoadEnabled}
        tooltip="将发电端口重新用途为负载端口。逆变器将根据配置的设置为该负载提供电力。注意：如果启用了智能负载功能，禁止同时连接发电机或交流耦合系统，否则设备将会损坏！"
      />

      <FieldRow
        label="启动PV功率(kW)"
        range="[0, 25.5]"
        tooltip="这是与智能负载输出功能运作的最低光伏功率限制。"
      >
        <InputNumber disabled={smartLoadFieldDisabled} min={0} max={25.5} step={0.1} value={smartLoadStartPv} onChange={(v) => setSmartLoadStartPv(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={smartLoadFieldDisabled} onClick={() => handleSet('启动PV功率')} />
      </FieldRow>

      <SwitchField
        label="并网时常开"
        checked={smartLoadGridAlwaysOn}
        onChange={setSmartLoadGridAlwaysOn}
        disabled={smartLoadFieldDisabled}
        tooltip="在电网正常时启用发电端口的持续供电。"
      />

      {/* Smart Load 电压字段 */}
      <FieldRow label="Smart Load启动电压(V)" range="[40, 59]">
        <InputNumber disabled={!voltageEnabled || smartLoadFieldDisabled} min={40} max={59} value={smartLoadStartVoltage} onChange={(v) => setSmartLoadStartVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled || smartLoadFieldDisabled} onClick={() => handleSet('Smart Load启动电压')} />
      </FieldRow>

      <FieldRow label="Smart Load截止电压(V)" range="[40, 59]">
        <InputNumber disabled={!voltageEnabled || smartLoadFieldDisabled} min={40} max={59} value={smartLoadCutoffVoltage} onChange={(v) => setSmartLoadCutoffVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled || smartLoadFieldDisabled} onClick={() => handleSet('Smart Load截止电压')} />
      </FieldRow>

      {/* Smart Load SOC字段 */}
      <FieldRow label="Smart Load启动SOC(%)" range="[0, 100]">
        <InputNumber disabled={!socEnabled || smartLoadFieldDisabled} min={0} max={100} value={smartLoadStartSoc} onChange={(v) => setSmartLoadStartSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled || smartLoadFieldDisabled} onClick={() => handleSet('Smart Load启动SOC')} />
      </FieldRow>

      <FieldRow label="Smart Load截止SOC(%)" range="[0, 100]">
        <InputNumber disabled={!socEnabled || smartLoadFieldDisabled} min={0} max={100} value={smartLoadCutoffSoc} onChange={(v) => setSmartLoadCutoffSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled || smartLoadFieldDisabled} onClick={() => handleSet('Smart Load截止SOC')} />
      </FieldRow>

      {/* 强制放电子分组 */}
      <SubGroupTitle title="强制放电" color={sectionColor} />

      <SwitchField
        label="强制放电使能"
        checked={forceDischargeEnable}
        onChange={setForceDischargeEnable}
        tooltip="启用强制放电模式"
      />

      <FieldRow
        label="强制放电功率百分比(%)"
        range="[0, 100]"
        tooltip="强制放电功率百分比"
      >
        <InputNumber disabled={forceDischargeDisabled} min={0} max={100} value={forceDischargePowerPercent} onChange={(v) => setForceDischargePowerPercent(v ?? 10)} style={{ width: 140 }} />
        <SettingButton disabled={forceDischargeDisabled} onClick={() => handleSet('强制放电功率百分比')} />
      </FieldRow>

      <FieldRow
        label="强制放电截止SOC(%)"
        range="[0, 100]"
        tooltip="强制放电截止SOC"
      >
        <InputNumber disabled={forceDischargeDisabled} min={0} max={100} value={forceDischargeCutoffSoc} onChange={(v) => setForceDischargeCutoffSoc(v ?? 20)} style={{ width: 140 }} />
        <SettingButton disabled={forceDischargeDisabled} onClick={() => handleSet('强制放电截止SOC')} />
      </FieldRow>

      <TimeRangeField label="强制放电起始时间0" h={forceStart0H} m={forceStart0M} onHChange={(v) => setForceStart0H(v ?? 0)} onMChange={(v) => setForceStart0M(v ?? 0)} onSet={() => handleSet('强制放电起始时间0')} disabled={forceDischargeDisabled} />
      <TimeRangeField label="强制放电结束时间0" h={forceEnd0H} m={forceEnd0M} onHChange={(v) => setForceEnd0H(v ?? 0)} onMChange={(v) => setForceEnd0M(v ?? 0)} onSet={() => handleSet('强制放电结束时间0')} disabled={forceDischargeDisabled} />
      <TimeRangeField label="强制放电起始时间1" h={forceStart1H} m={forceStart1M} onHChange={(v) => setForceStart1H(v ?? 0)} onMChange={(v) => setForceStart1M(v ?? 0)} onSet={() => handleSet('强制放电起始时间1')} disabled={forceDischargeDisabled} />
      <TimeRangeField label="强制放电结束时间1" h={forceEnd1H} m={forceEnd1M} onHChange={(v) => setForceEnd1H(v ?? 0)} onMChange={(v) => setForceEnd1M(v ?? 0)} onSet={() => handleSet('强制放电结束时间1')} disabled={forceDischargeDisabled} />
      <TimeRangeField label="强制放电起始时间2" h={forceStart2H} m={forceStart2M} onHChange={(v) => setForceStart2H(v ?? 0)} onMChange={(v) => setForceStart2M(v ?? 0)} onSet={() => handleSet('强制放电起始时间2')} disabled={forceDischargeDisabled} />
      <TimeRangeField label="强制放电结束时间2" h={forceEnd2H} m={forceEnd2M} onHChange={(v) => setForceEnd2H(v ?? 0)} onMChange={(v) => setForceEnd2M(v ?? 0)} onSet={() => handleSet('强制放电结束时间2')} disabled={forceDischargeDisabled} />
    </Row>
  )
}

export default DischargeSection
