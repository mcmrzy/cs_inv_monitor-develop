import React, { useState, useCallback } from 'react'
import { Row, Col, Select, InputNumber, Divider, App, Typography, Space, Tooltip } from 'antd'
import { QuestionCircleOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import { FieldRow, SwitchField, SettingButton, SubGroupTitle, labelStyle, fieldRowStyle, SECTION_COLORS, disabledInputStyle } from './shared-styles'

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

const ChargeSection: React.FC = () => {
  const { message } = App.useApp()
  const { t } = useTranslation()

  // 顶层
  const [chargePowerPercent, setChargePowerPercent] = useState<number>(100)

  // 主充电参数
  const [chargeCurrent, setChargeCurrent] = useState<number>(60)

  // 铅酸充电参数
  const [chargeVoltage, setChargeVoltage] = useState<number>(54)
  const [floatVoltage, setFloatVoltage] = useState<number>(54)
  const [equalVoltage, setEqualVoltage] = useState<number>(56)
  const [equalCycle, setEqualCycle] = useState<number>(30)
  const [equalTime, setEqualTime] = useState<number>(2)

  // 交流充电
  const [acChargeEnable, setAcChargeEnable] = useState(false)
  const [acChargeControl, setAcChargeControl] = useState<number>(0)
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
  const [genChargeType, setGenChargeType] = useState<number>(0)
  const [genChargeCurrent, setGenChargeCurrent] = useState<number>(60)
  const [genChargeStartVoltage, setGenChargeStartVoltage] = useState<number>(46)
  const [genChargeEndVoltage, setGenChargeEndVoltage] = useState<number>(54)
  const [genChargeStartSoc, setGenChargeStartSoc] = useState<number>(20)
  const [genChargeEndSoc, setGenChargeEndSoc] = useState<number>(90)
  const [genRatedPower, setGenRatedPower] = useState<number>(3000)
  const [genBoost, setGenBoost] = useState(false)

  // 充电优先级
  const [batteryChargePriority, setBatteryChargePriority] = useState(false)
  const [batteryChargePriorityPercent, setBatteryChargePriorityPercent] = useState<number>(0)
  const [systemChargeSocLimit, setSystemChargeSocLimit] = useState<number>(100)
  // 系统充电优先级
  const [systemChargePriority, setSystemChargePriority] = useState(false)
  const [systemChargePriorityPercent, setSystemChargePriorityPercent] = useState<number>(0)

  const handleSet = (fieldName: string) => {
    message.success(t('remote.executeSuccess', { title: fieldName }))
  }

  // AC充电：设置时自动将不相关的值归零
  const handleAcControlSet = useCallback(() => {
    const ctrl = acChargeControl
    // 禁用时所有子字段归零
    if (ctrl === 0) {
      setAcChargeCurrent(0)
      setAcChargeStartVoltage(0)
      setAcChargeEndVoltage(0)
      setAcChargeStartSoc(0)
      setAcChargeEndSoc(0)
      setAcStart1H(0); setAcStart1M(0)
      setAcEnd1H(0); setAcEnd1M(0)
      setAcStart2H(0); setAcStart2M(0)
      setAcEnd2H(0); setAcEnd2M(0)
      setAcStart3H(0); setAcStart3M(0)
      setAcEnd3H(0); setAcEnd3M(0)
    } else {
      // 时间不相关 → 时间归零
      if (![1, 4, 5].includes(ctrl)) {
        setAcStart1H(0); setAcStart1M(0)
        setAcEnd1H(0); setAcEnd1M(0)
        setAcStart2H(0); setAcStart2M(0)
        setAcEnd2H(0); setAcEnd2M(0)
        setAcStart3H(0); setAcStart3M(0)
        setAcEnd3H(0); setAcEnd3M(0)
      }
      // 电压不相关 → 电压归零
      if (![2, 4].includes(ctrl)) {
        setAcChargeStartVoltage(0)
        setAcChargeEndVoltage(0)
      }
      // SOC不相关 → SOC归零
      if (![3, 5].includes(ctrl)) {
        setAcChargeStartSoc(0)
        setAcChargeEndSoc(0)
      }
    }
    handleSet(t('remote.acChargeControl'))
  }, [acChargeControl, t])

  // 发电机充电：设置时自动将不相关的值归零
  const handleGenTypeSet = useCallback(() => {
    if (genChargeType === 0) {
      // 电压模式 → SOC归零
      setGenChargeStartSoc(0)
      setGenChargeEndSoc(0)
    } else {
      // SOC模式 → 电压归零
      setGenChargeStartVoltage(0)
      setGenChargeEndVoltage(0)
    }
    handleSet(t('remote.genChargeType'))
  }, [genChargeType, t])

  const sectionColor = SECTION_COLORS.charge

  // AC充电联动控制
  const acShowTime = [1, 4, 5].includes(acChargeControl)
  const acShowVoltage = [2, 4].includes(acChargeControl)
  const acShowSoc = [3, 5].includes(acChargeControl)
  const acShowCurrent = acChargeControl > 0

  // 发电机充电联动控制
  const genShowVoltage = genChargeType === 0
  const genShowSoc = genChargeType === 1

  return (
    <Row gutter={[16, 8]}>
      {/* 顶层字段 */}
      <FieldRow label={`${t('remote.chargePowerPct')}(%)`} tooltip={t('remote.chargePowerPctTooltip')}>
        <InputNumber min={0} max={100} value={chargePowerPercent} onChange={(v) => setChargePowerPercent(v ?? 100)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.chargePowerPct'))} />
      </FieldRow>

      <Col span={24}><Divider style={{ margin: '8px 0' }} /></Col>

      {/* 主充电参数 */}
      <SubGroupTitle title={t('remote.mainChargeParams')} color={sectionColor} />

      <FieldRow label={`${t('remote.chargeCurrentLimitLabel')}(Adc)`} tooltip={t('remote.chargeCurrentLimitTooltip')}>
        <InputNumber min={0} max={110} step={0.1} value={chargeCurrent} onChange={(v) => setChargeCurrent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.chargeCurrentLimitLabel'))} />
      </FieldRow>

      <Col span={24}><Divider style={{ margin: '8px 0' }} /></Col>

      {/* 铅酸充电参数 */}
      <SubGroupTitle title={t('remote.leadAcid')} color={sectionColor} />

      <FieldRow label={`${t('remote.chargeVoltageLabel')}(V)`} tooltip={t('remote.chargeVoltageTooltip')}>
        <InputNumber min={50} max={59} step={0.1} value={chargeVoltage} onChange={(v) => setChargeVoltage(v ?? 50)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.chargeVoltageLabel'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.floatVoltage')}(V)`} tooltip={t('remote.floatVoltageTooltip')}>
        <InputNumber min={50} max={56} step={0.1} value={floatVoltage} onChange={(v) => setFloatVoltage(v ?? 50)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.floatVoltage'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.equalizeVoltage')}(V)`} tooltip={t('remote.equalizeVoltageTooltip')}>
        <InputNumber min={0} max={59} step={0.1} value={equalVoltage} onChange={(v) => setEqualVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.equalizeVoltage'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.equalizeCycle')}${t('remote.day')}`} tooltip={t('remote.equalizeCycleTooltip')}>
        <InputNumber min={0} max={365} value={equalCycle} onChange={(v) => setEqualCycle(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.equalizeCycle'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.equalizeTime')}${t('remote.hour')}`} tooltip={t('remote.equalizeTimeTooltip')}>
        <InputNumber min={0} max={24} value={equalTime} onChange={(v) => setEqualTime(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.equalizeTime'))} />
      </FieldRow>

      <Col span={24}><Divider style={{ margin: '8px 0' }} /></Col>

      {/* 交流充电 */}
      <SubGroupTitle title={t('remote.acCharge')} color={sectionColor} />

      <FieldRow label={t('remote.acChargeControl')} tooltip={t('remote.acChargeControlTooltip')}>
        <Select value={acChargeControl} onChange={(v: number) => setAcChargeControl(v)} style={{ width: 180 }}>
          <Option value={0}>{t('remote.disable')}</Option>
          <Option value={1}>{t('remote.time')}</Option>
          <Option value={2}>{t('remote.batteryVoltage')}</Option>
          <Option value={3}>{t('remote.batterySoc')}</Option>
          <Option value={4}>{t('remote.batteryVoltageTime')}</Option>
          <Option value={5}>{t('remote.batterySocTime')}</Option>
        </Select>
        <SettingButton onClick={handleAcControlSet} />
      </FieldRow>

      <FieldRow label={`${t('remote.acChargeCurrent')}(A)`} tooltip={t('remote.acChargeCurrentTooltip')}>
        <InputNumber min={0} max={100} step={0.1} value={acChargeCurrent} onChange={(v) => setAcChargeCurrent(v ?? 0)} style={{ width: 140, ...(!acShowCurrent ? disabledInputStyle : {}) }} disabled={!acShowCurrent} />
        <SettingButton onClick={() => handleSet(t('remote.acChargeCurrent'))} disabled={!acShowCurrent} />
      </FieldRow>

      <FieldRow label={`${t('remote.acChargeStartVoltage')}(V)`} tooltip={t('remote.acChargeStartVoltageTooltip')}>
        <InputNumber min={0} max={52} step={0.1} value={acChargeStartVoltage} onChange={(v) => setAcChargeStartVoltage(v ?? 0)} style={{ width: 140, ...(!acShowVoltage ? disabledInputStyle : {}) }} disabled={!acShowVoltage} />
        <SettingButton onClick={() => handleSet(t('remote.acChargeStartVoltage'))} disabled={!acShowVoltage} />
      </FieldRow>

      <FieldRow label={`${t('remote.acChargeEndVoltage')}(V)`} tooltip={t('remote.acChargeEndVoltageTooltip')}>
        <InputNumber min={0} max={59} step={0.1} value={acChargeEndVoltage} onChange={(v) => setAcChargeEndVoltage(v ?? 0)} style={{ width: 140, ...(!acShowVoltage ? disabledInputStyle : {}) }} disabled={!acShowVoltage} />
        <SettingButton onClick={() => handleSet(t('remote.acChargeEndVoltage'))} disabled={!acShowVoltage} />
      </FieldRow>

      <FieldRow label={`${t('remote.acChargeStartSoc')}(%)`} tooltip={t('remote.acChargeStartSocTooltip')}>
        <InputNumber min={0} max={90} value={acChargeStartSoc} onChange={(v) => setAcChargeStartSoc(v ?? 0)} style={{ width: 140, ...(!acShowSoc ? disabledInputStyle : {}) }} disabled={!acShowSoc} />
        <SettingButton onClick={() => handleSet(t('remote.acChargeStartSoc'))} disabled={!acShowSoc} />
      </FieldRow>

      <FieldRow label={`${t('remote.acChargeEndSoc')}(%)`} tooltip={t('remote.acChargeEndSocTooltip')}>
        <InputNumber min={0} max={100} value={acChargeEndSoc} onChange={(v) => setAcChargeEndSoc(v ?? 0)} style={{ width: 140, ...(!acShowSoc ? disabledInputStyle : {}) }} disabled={!acShowSoc} />
        <SettingButton onClick={() => handleSet(t('remote.acChargeEndSoc'))} disabled={!acShowSoc} />
      </FieldRow>

      <SwitchField label={t('remote.acChargeEnable')} checked={acChargeEnable} onChange={(v) => { setAcChargeEnable(v); handleSet(t('remote.acChargeEnable')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.acChargeEnableTooltip')} />

      <TimeRangeField label={t('remote.acChargeStartTime1')} h={acStart1H} m={acStart1M} onHChange={(v) => setAcStart1H(v ?? 0)} onMChange={(v) => setAcStart1M(v ?? 0)} onSet={() => handleSet(t('remote.acChargeStartTime1'))} disabled={!acShowTime} />
      <TimeRangeField label={t('remote.acChargeEndTime1')} h={acEnd1H} m={acEnd1M} onHChange={(v) => setAcEnd1H(v ?? 0)} onMChange={(v) => setAcEnd1M(v ?? 0)} onSet={() => handleSet(t('remote.acChargeEndTime1'))} disabled={!acShowTime} />
      <TimeRangeField label={t('remote.acChargeStartTime2')} h={acStart2H} m={acStart2M} onHChange={(v) => setAcStart2H(v ?? 0)} onMChange={(v) => setAcStart2M(v ?? 0)} onSet={() => handleSet(t('remote.acChargeStartTime2'))} disabled={!acShowTime} />
      <TimeRangeField label={t('remote.acChargeEndTime2')} h={acEnd2H} m={acEnd2M} onHChange={(v) => setAcEnd2H(v ?? 0)} onMChange={(v) => setAcEnd2M(v ?? 0)} onSet={() => handleSet(t('remote.acChargeEndTime2'))} disabled={!acShowTime} />
      <TimeRangeField label={t('remote.acChargeStartTime3')} h={acStart3H} m={acStart3M} onHChange={(v) => setAcStart3H(v ?? 0)} onMChange={(v) => setAcStart3M(v ?? 0)} onSet={() => handleSet(t('remote.acChargeStartTime3'))} disabled={!acShowTime} />
      <TimeRangeField label={t('remote.acChargeEndTime3')} h={acEnd3H} m={acEnd3M} onHChange={(v) => setAcEnd3H(v ?? 0)} onMChange={(v) => setAcEnd3M(v ?? 0)} onSet={() => handleSet(t('remote.acChargeEndTime3'))} disabled={!acShowTime} />

      <Col span={24}><Divider style={{ margin: '8px 0' }} /></Col>

      {/* 发电机充电 */}
      <SubGroupTitle title={t('remote.genCharge')} color={sectionColor} />

      <FieldRow label={t('remote.genChargeType')} tooltip={t('remote.genChargeTypeTooltip')}>
        <Select value={genChargeType} onChange={(v: number) => setGenChargeType(v)} style={{ width: 140 }}>
          <Option value={0}>{t('remote.batteryVoltage')}</Option>
          <Option value={1}>{t('remote.batterySoc')}</Option>
        </Select>
        <SettingButton onClick={handleGenTypeSet} />
      </FieldRow>

      <FieldRow label={`${t('remote.genChargeCurrent')}(A)`} tooltip={t('remote.genChargeCurrentTooltip')}>
        <InputNumber min={0} max={110} step={0.1} value={genChargeCurrent} onChange={(v) => setGenChargeCurrent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.genChargeCurrent'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.genChargeStartVoltage')}(V)`} tooltip={t('remote.genChargeStartVoltageTooltip')}>
        <InputNumber min={0} max={52} step={0.1} value={genChargeStartVoltage} onChange={(v) => setGenChargeStartVoltage(v ?? 0)} style={{ width: 140, ...(!genShowVoltage ? disabledInputStyle : {}) }} disabled={!genShowVoltage} />
        <SettingButton onClick={() => handleSet(t('remote.genChargeStartVoltage'))} disabled={!genShowVoltage} />
      </FieldRow>

      <FieldRow label={`${t('remote.genChargeEndVoltage')}(V)`} tooltip={t('remote.genChargeEndVoltageTooltip')}>
        <InputNumber min={0} max={59} step={0.1} value={genChargeEndVoltage} onChange={(v) => setGenChargeEndVoltage(v ?? 0)} style={{ width: 140, ...(!genShowVoltage ? disabledInputStyle : {}) }} disabled={!genShowVoltage} />
        <SettingButton onClick={() => handleSet(t('remote.genChargeEndVoltage'))} disabled={!genShowVoltage} />
      </FieldRow>

      <FieldRow label={`${t('remote.genChargeStartSoc')}(%)`} tooltip={t('remote.genChargeStartSocTooltip')}>
        <InputNumber min={0} max={90} value={genChargeStartSoc} onChange={(v) => setGenChargeStartSoc(v ?? 0)} style={{ width: 140, ...(!genShowSoc ? disabledInputStyle : {}) }} disabled={!genShowSoc} />
        <SettingButton onClick={() => handleSet(t('remote.genChargeStartSoc'))} disabled={!genShowSoc} />
      </FieldRow>

      <FieldRow label={`${t('remote.genChargeEndSoc')}(%)`} tooltip={t('remote.genChargeEndSocTooltip')}>
        <InputNumber min={0} max={100} value={genChargeEndSoc} onChange={(v) => setGenChargeEndSoc(v ?? 0)} style={{ width: 140, ...(!genShowSoc ? disabledInputStyle : {}) }} disabled={!genShowSoc} />
        <SettingButton onClick={() => handleSet(t('remote.genChargeEndSoc'))} disabled={!genShowSoc} />
      </FieldRow>

      <FieldRow label={`${t('remote.genRatedPower')}(W)`} tooltip={t('remote.genRatedPowerTooltip')}>
        <InputNumber min={0} max={7370} value={genRatedPower} onChange={(v) => setGenRatedPower(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.genRatedPower'))} />
      </FieldRow>

      <SwitchField label={t('remote.genBoost')} checked={genBoost} onChange={(v) => { setGenBoost(v); handleSet(t('remote.genBoost')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} />

      <Col span={24}><Divider style={{ margin: '8px 0' }} /></Col>

      {/* 充电优先级 */}
      <SubGroupTitle title={t('remote.chargePriority')} color={sectionColor} />

      <SwitchField label={t('remote.batteryChargePriority')} checked={batteryChargePriority} onChange={(v) => { setBatteryChargePriority(v); handleSet(t('remote.batteryChargePriority')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.batteryChargePriorityTooltip')} />

      <FieldRow label={`${t('remote.batteryChargePriorityPct')}(%)`} tooltip={t('remote.batteryChargePriorityPctTooltip')}>
        <InputNumber min={0} max={100} value={batteryChargePriorityPercent} onChange={(v) => setBatteryChargePriorityPercent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.batteryChargePriorityPct'))} />
      </FieldRow>

      <SwitchField label={t('remote.systemChargePriority')} checked={systemChargePriority} onChange={(v) => { setSystemChargePriority(v); handleSet(t('remote.systemChargePriority')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.systemChargePriorityTooltip')} />

      <FieldRow label={`${t('remote.systemChargePriorityPct')}(%)`} tooltip={t('remote.systemChargePriorityPctTooltip')}>
        <InputNumber min={0} max={100} value={systemChargePriorityPercent} onChange={(v) => setSystemChargePriorityPercent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.systemChargePriorityPct'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.systemChargeSocLimit')}(%)`} tooltip={t('remote.systemChargeSocLimitTooltip')}>
        <InputNumber min={0} max={100} value={systemChargeSocLimit} onChange={(v) => setSystemChargeSocLimit(v ?? 100)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.systemChargeSocLimit'))} />
      </FieldRow>
    </Row>
  )
}

export default ChargeSection
