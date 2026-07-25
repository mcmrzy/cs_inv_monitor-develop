import React, { useState } from 'react'
import { Row, Col, Select, InputNumber, App, Typography, Space, Tooltip } from 'antd'
import { QuestionCircleOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
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

const TimeRangeField: React.FC<TimeRangeFieldProps> = ({ label, h, m, onHChange, onMChange, onSet, tooltip, disabled }) => {
  const { t } = useTranslation()
  return (
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
          <InputNumber min={0} max={23} value={h} onChange={onHChange} style={{ width: 70, ...(disabled ? disabledInputStyle : {}) }} addonAfter={t('remote.hour')} disabled={disabled} />
          <Text>:</Text>
          <InputNumber min={0} max={59} value={m} onChange={onMChange} style={{ width: 70, ...(disabled ? disabledInputStyle : {}) }} addonAfter={t('remote.minute')} disabled={disabled} />
          <SettingButton onClick={onSet} disabled={disabled} />
        </Space>
      </div>
    </Col>
  )
}

const DischargeSection: React.FC = () => {
  const { message } = App.useApp()
  const { t } = useTranslation()

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
    message.success(t('remote.executeSuccess', { title: fieldName }))
  }

  const sectionColor = SECTION_COLORS.discharge

  return (
    <Row gutter={[16, 8]}>
      {/* 放电控制 */}
      <FieldRow
        label={t('remote.dischargeControl')}
        tooltip={t('remote.dischargeControlTooltip')}
      >
        <Select value={dischargeControl} onChange={setDischargeControl} style={{ width: 140 }}>
          <Option value={0}>{t('remote.voltageBased')}</Option>
          <Option value={1}>{t('remote.socBased')}</Option>
        </Select>
        <SettingButton onClick={() => handleSet(t('remote.dischargeControl'))} />
      </FieldRow>

      {/* 放电电流限制 - 始终启用 */}
      <FieldRow
        label={`${t('remote.dischargeCurrentLimitLabel')}(Adc)`}
        range="[1, 110 (single) / 4480 (parallel)]"
        tooltip={t('remote.dischargeCurrentLimitTooltip')}
      >
        <InputNumber min={0} max={110} step={0.1} value={dischargeCurrent} onChange={(v) => setDischargeCurrent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.dischargeCurrentLimitLabel'))} />
      </FieldRow>

      {/* 电压模式字段 */}
      <FieldRow
        label={`${t('remote.batteryWarningVoltage')}(V)`}
        range="[40, 50]"
        tooltip={t('remote.batteryWarningVoltageTooltip')}
      >
        <InputNumber disabled={!voltageEnabled} min={40} max={50} step={0.1} value={batteryWarnVoltage} onChange={(v) => setBatteryWarnVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled} onClick={() => handleSet(t('remote.batteryWarningVoltage'))} />
      </FieldRow>

      <FieldRow
        label={`${t('remote.leadAcidCutoffVoltage')}(V)`}
        range="[40, 50]"
        tooltip={t('remote.leadAcidCutoffVoltageTooltip')}
      >
        <InputNumber disabled={!voltageEnabled} min={40} max={50} step={0.1} value={leadAcidCutoffVoltage} onChange={(v) => setLeadAcidCutoffVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled} onClick={() => handleSet(t('remote.leadAcidCutoffVoltage'))} />
      </FieldRow>

      <FieldRow
        label={`${t('remote.gridEodVoltage')}(V)`}
        range="[40, 56]"
        tooltip={t('remote.gridEodVoltageTooltip')}
      >
        <InputNumber disabled={!voltageEnabled} min={40} max={56} step={0.1} value={gridEodVoltage} onChange={(v) => setGridEodVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled} onClick={() => handleSet(t('remote.gridEodVoltage'))} />
      </FieldRow>

      {/* SOC模式字段 */}
      <FieldRow
        label={`${t('remote.batteryWarningSoc')}(%)`}
        range="[0, 90]"
        tooltip={t('remote.batteryWarningSocTooltip')}
      >
        <InputNumber disabled={!socEnabled} min={0} max={90} value={batteryWarnSoc} onChange={(v) => setBatteryWarnSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled} onClick={() => handleSet(t('remote.batteryWarningSoc'))} />
      </FieldRow>

      <FieldRow
        label={`${t('remote.cutoffSoc')}(%)`}
        range="[0, 90]"
        tooltip={t('remote.cutoffSocTooltip')}
      >
        <InputNumber disabled={!socEnabled} min={0} max={90} value={cutoffSoc} onChange={(v) => setCutoffSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled} onClick={() => handleSet(t('remote.cutoffSoc'))} />
      </FieldRow>

      <FieldRow
        label={`${t('remote.gridCutoffSoc')}(%)`}
        range="[0, 90]"
        tooltip={t('remote.gridCutoffSocTooltip')}
      >
        <InputNumber disabled={!socEnabled} min={0} max={90} value={gridCutoffSoc} onChange={(v) => setGridCutoffSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled} onClick={() => handleSet(t('remote.gridCutoffSoc'))} />
      </FieldRow>

      {/* 独立字段 */}
      <FieldRow
        label={`${t('remote.dischargePowerPct')}(%)`}
        range="[0, 100]"
        tooltip={t('remote.dischargePowerPctTooltip')}
      >
        <InputNumber min={0} max={100} value={dischargePowerPercent} onChange={(v) => setDischargePowerPercent(v ?? 100)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.dischargePowerPct'))} />
      </FieldRow>

      <FieldRow
        label={`${t('remote.gridDischargeCutoffSocLimit')}(%)`}
        range="[0, 100]"
        tooltip={t('remote.gridDischargeCutoffSocLimitTooltip')}
      >
        <InputNumber min={0} max={100} value={gridDischargeCutoffSoc} onChange={(v) => setGridDischargeCutoffSoc(v ?? 10)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridDischargeCutoffSocLimit'))} />
      </FieldRow>

      <FieldRow
        label={`${t('remote.offgridDischargeCutoffSocLimit')}(%)`}
        range="[0, 100]"
        tooltip={t('remote.offgridDischargeCutoffSocLimitTooltip')}
      >
        <InputNumber min={0} max={100} value={offgridDischargeCutoffSoc} onChange={(v) => setOffgridDischargeCutoffSoc(v ?? 10)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.offgridDischargeCutoffSocLimit'))} />
      </FieldRow>

      <FieldRow
        label={`${t('remote.dischargeStartPower')}(W)`}
        range="[0, 65535]"
        tooltip={t('remote.dischargeStartPowerTooltip')}
      >
        <InputNumber min={0} max={65535} value={dischargeStartPower} onChange={(v) => setDischargeStartPower(v ?? 100)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.dischargeStartPower'))} />
      </FieldRow>

      {/* 交流耦合子分组 */}
      <SubGroupTitle title={t('remote.acCoupling')} color={sectionColor} />

      <SwitchField
        label={t('remote.acCoupling')}
        checked={acCoupleEnabled}
        onChange={setAcCoupleEnabled}
        tooltip={t('remote.acCouplingTooltip')}
      />

      {/* AC Couple 电压字段 */}
      <FieldRow label={`${t('remote.acCoupleStartVoltage')}(V)`} range="[40, 59.5]">
        <InputNumber disabled={!voltageEnabled || acCoupleFieldDisabled} min={40} max={59.5} step={0.1} value={acCoupleStartVoltage} onChange={(v) => setAcCoupleStartVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled || acCoupleFieldDisabled} onClick={() => handleSet(t('remote.acCoupleStartVoltage'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.acCoupleCutoffVoltage')}(V)`} range="[42, 80]">
        <InputNumber disabled={!voltageEnabled || acCoupleFieldDisabled} min={42} max={80} value={acCoupleCutoffVoltage} onChange={(v) => setAcCoupleCutoffVoltage(v ?? 42)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled || acCoupleFieldDisabled} onClick={() => handleSet(t('remote.acCoupleCutoffVoltage'))} />
      </FieldRow>

      {/* AC Couple SOC字段 */}
      <FieldRow label={`${t('remote.acCoupleStartSoc')}(%)`} range="[0, 80]">
        <InputNumber disabled={!socEnabled || acCoupleFieldDisabled} min={0} max={80} value={acCoupleStartSoc} onChange={(v) => setAcCoupleStartSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled || acCoupleFieldDisabled} onClick={() => handleSet(t('remote.acCoupleStartSoc'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.acCoupleCutoffSoc')}(%)`} range="[0, 100]">
        <InputNumber disabled={!socEnabled || acCoupleFieldDisabled} min={0} max={100} value={acCoupleCutoffSoc} onChange={(v) => setAcCoupleCutoffSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled || acCoupleFieldDisabled} onClick={() => handleSet(t('remote.acCoupleCutoffSoc'))} />
      </FieldRow>

      {/* 智能负载子分组 */}
      <SubGroupTitle title={t('remote.smartLoad')} color={sectionColor} />

      <SwitchField
        label={t('remote.smartLoad')}
        checked={smartLoadEnabled}
        onChange={setSmartLoadEnabled}
        tooltip={t('remote.smartLoadTooltip')}
      />

      <FieldRow
        label={`${t('remote.startPvPower')}(kW)`}
        range="[0, 25.5]"
        tooltip={t('remote.startPvPowerTooltip')}
      >
        <InputNumber disabled={smartLoadFieldDisabled} min={0} max={25.5} step={0.1} value={smartLoadStartPv} onChange={(v) => setSmartLoadStartPv(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={smartLoadFieldDisabled} onClick={() => handleSet(t('remote.startPvPower'))} />
      </FieldRow>

      <SwitchField
        label={t('remote.gridAlwaysOn')}
        checked={smartLoadGridAlwaysOn}
        onChange={setSmartLoadGridAlwaysOn}
        disabled={smartLoadFieldDisabled}
        tooltip={t('remote.gridAlwaysOnTooltip')}
      />

      {/* Smart Load 电压字段 */}
      <FieldRow label={`${t('remote.smartLoadStartVoltage')}(V)`} range="[40, 59]">
        <InputNumber disabled={!voltageEnabled || smartLoadFieldDisabled} min={40} max={59} value={smartLoadStartVoltage} onChange={(v) => setSmartLoadStartVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled || smartLoadFieldDisabled} onClick={() => handleSet(t('remote.smartLoadStartVoltage'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.smartLoadCutoffVoltage')}(V)`} range="[40, 59]">
        <InputNumber disabled={!voltageEnabled || smartLoadFieldDisabled} min={40} max={59} value={smartLoadCutoffVoltage} onChange={(v) => setSmartLoadCutoffVoltage(v ?? 40)} style={{ width: 140 }} />
        <SettingButton disabled={!voltageEnabled || smartLoadFieldDisabled} onClick={() => handleSet(t('remote.smartLoadCutoffVoltage'))} />
      </FieldRow>

      {/* Smart Load SOC字段 */}
      <FieldRow label={`${t('remote.smartLoadStartSoc')}(%)`} range="[0, 100]">
        <InputNumber disabled={!socEnabled || smartLoadFieldDisabled} min={0} max={100} value={smartLoadStartSoc} onChange={(v) => setSmartLoadStartSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled || smartLoadFieldDisabled} onClick={() => handleSet(t('remote.smartLoadStartSoc'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.smartLoadCutoffSoc')}(%)`} range="[0, 100]">
        <InputNumber disabled={!socEnabled || smartLoadFieldDisabled} min={0} max={100} value={smartLoadCutoffSoc} onChange={(v) => setSmartLoadCutoffSoc(v ?? 0)} style={{ width: 140 }} />
        <SettingButton disabled={!socEnabled || smartLoadFieldDisabled} onClick={() => handleSet(t('remote.smartLoadCutoffSoc'))} />
      </FieldRow>

      {/* 强制放电子分组 */}
      <SubGroupTitle title={t('remote.forcedDischarge')} color={sectionColor} />

      <SwitchField
        label={t('remote.forcedDischargeEnable')}
        checked={forceDischargeEnable}
        onChange={setForceDischargeEnable}
        tooltip={t('remote.forcedDischargeEnableTooltip')}
      />

      <FieldRow
        label={`${t('remote.forcedDischargePowerPct')}(%)`}
        range="[0, 100]"
        tooltip={t('remote.forcedDischargePowerPctTooltip')}
      >
        <InputNumber disabled={forceDischargeDisabled} min={0} max={100} value={forceDischargePowerPercent} onChange={(v) => setForceDischargePowerPercent(v ?? 10)} style={{ width: 140 }} />
        <SettingButton disabled={forceDischargeDisabled} onClick={() => handleSet(t('remote.forcedDischargePowerPct'))} />
      </FieldRow>

      <FieldRow
        label={`${t('remote.forcedDischargeCutoffSoc')}(%)`}
        range="[0, 100]"
        tooltip={t('remote.forcedDischargeCutoffSocTooltip')}
      >
        <InputNumber disabled={forceDischargeDisabled} min={0} max={100} value={forceDischargeCutoffSoc} onChange={(v) => setForceDischargeCutoffSoc(v ?? 20)} style={{ width: 140 }} />
        <SettingButton disabled={forceDischargeDisabled} onClick={() => handleSet(t('remote.forcedDischargeCutoffSoc'))} />
      </FieldRow>

      <TimeRangeField label={`${t('remote.forcedDischargeStartTime')} 0`} h={forceStart0H} m={forceStart0M} onHChange={(v) => setForceStart0H(v ?? 0)} onMChange={(v) => setForceStart0M(v ?? 0)} onSet={() => handleSet(`${t('remote.forcedDischargeStartTime')} 0`)} disabled={forceDischargeDisabled} />
      <TimeRangeField label={`${t('remote.forcedDischargeEndTime')} 0`} h={forceEnd0H} m={forceEnd0M} onHChange={(v) => setForceEnd0H(v ?? 0)} onMChange={(v) => setForceEnd0M(v ?? 0)} onSet={() => handleSet(`${t('remote.forcedDischargeEndTime')} 0`)} disabled={forceDischargeDisabled} />
      <TimeRangeField label={`${t('remote.forcedDischargeStartTime')} 1`} h={forceStart1H} m={forceStart1M} onHChange={(v) => setForceStart1H(v ?? 0)} onMChange={(v) => setForceStart1M(v ?? 0)} onSet={() => handleSet(`${t('remote.forcedDischargeStartTime')} 1`)} disabled={forceDischargeDisabled} />
      <TimeRangeField label={`${t('remote.forcedDischargeEndTime')} 1`} h={forceEnd1H} m={forceEnd1M} onHChange={(v) => setForceEnd1H(v ?? 0)} onMChange={(v) => setForceEnd1M(v ?? 0)} onSet={() => handleSet(`${t('remote.forcedDischargeEndTime')} 1`)} disabled={forceDischargeDisabled} />
      <TimeRangeField label={`${t('remote.forcedDischargeStartTime')} 2`} h={forceStart2H} m={forceStart2M} onHChange={(v) => setForceStart2H(v ?? 0)} onMChange={(v) => setForceStart2M(v ?? 0)} onSet={() => handleSet(`${t('remote.forcedDischargeStartTime')} 2`)} disabled={forceDischargeDisabled} />
      <TimeRangeField label={`${t('remote.forcedDischargeEndTime')} 2`} h={forceEnd2H} m={forceEnd2M} onHChange={(v) => setForceEnd2H(v ?? 0)} onMChange={(v) => setForceEnd2M(v ?? 0)} onSet={() => handleSet(`${t('remote.forcedDischargeEndTime')} 2`)} disabled={forceDischargeDisabled} />
    </Row>
  )
}

export default DischargeSection
