import React, { useState, useCallback } from 'react'
import { Row, Col, Select, InputNumber, Divider, App, Typography, Space, Tooltip } from 'antd'
import { QuestionCircleOutlined } from '@ant-design/icons'
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

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 指令已下发`)
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
    handleSet('AC充电控制依据')
  }, [acChargeControl])

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
    handleSet('发电机充电类型')
  }, [genChargeType])

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
      {/* 主充电参数 */}
      <SubGroupTitle title="主充电参数" color={sectionColor} />

      <FieldRow label="充电电流限制(A)" tooltip="根据电池要求进行设置，范围：0~110（单台）4480（并联）。">
        <InputNumber min={0} max={110} step={0.1} value={chargeCurrent} onChange={(v) => setChargeCurrent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('充电电流限制')} />
      </FieldRow>

      <Col span={24}><Divider style={{ margin: '8px 0' }} /></Col>

      {/* 铅酸充电参数 */}
      <SubGroupTitle title="铅酸" color={sectionColor} />

      <FieldRow label="充电电压(V)" tooltip="根据电池要求进行设置，范围：50~59V。">
        <InputNumber min={50} max={59} step={0.1} value={chargeVoltage} onChange={(v) => setChargeVoltage(v ?? 50)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('充电电压')} />
      </FieldRow>

      <FieldRow label="浮动电压(V)" tooltip="根据电池要求进行设置，范围：50~56V。1：使用铅酸电池时，必须设置低于充电电压。2：在铅酸模式下使用锂电池时，可以设置为等于或低于充电电压。">
        <InputNumber min={50} max={56} step={0.1} value={floatVoltage} onChange={(v) => setFloatVoltage(v ?? 50)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('浮动电压')} />
      </FieldRow>

      <FieldRow label="均衡电压(V)" tooltip="1：使用铅酸电池时，设置范围：50~59。2：在铅酸模式下使用锂电池时，输入 0。">
        <InputNumber min={0} max={59} step={0.1} value={equalVoltage} onChange={(v) => setEqualVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('均衡电压')} />
      </FieldRow>

      <FieldRow label="均衡周期(天)" tooltip="1：使用铅酸电池时，设置范围：0~365。2：在铅酸模式下使用锂电池时，输入 0。">
        <InputNumber min={0} max={365} value={equalCycle} onChange={(v) => setEqualCycle(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('均衡周期')} />
      </FieldRow>

      <FieldRow label="均衡时间(小时)" tooltip="1：使用铅酸电池时，设置范围：0~24。2：在铅酸模式下使用锂电池时，输入 0。">
        <InputNumber min={0} max={24} value={equalTime} onChange={(v) => setEqualTime(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('均衡时间')} />
      </FieldRow>

      <Col span={24}><Divider style={{ margin: '8px 0' }} /></Col>

      {/* 交流充电 */}
      <SubGroupTitle title="交流充电" color={sectionColor} />

      <FieldRow label="AC充电控制依据" tooltip="根据时间：设定一个优选的充电时间段给电池。根据SOC/电压：当SOC/电压下降到设定阈值时设定交流电充电电池。">
        <Select value={acChargeControl} onChange={(v: number) => setAcChargeControl(v)} style={{ width: 180 }}>
          <Option value={0}>禁用</Option>
          <Option value={1}>时间</Option>
          <Option value={2}>电池电压</Option>
          <Option value={3}>电池SOC</Option>
          <Option value={4}>电池电压+时间</Option>
          <Option value={5}>电池SOC+时间</Option>
        </Select>
        <SettingButton onClick={handleAcControlSet} />
      </FieldRow>

      <FieldRow label="交流充电电池电流(A)" tooltip="根据电池要求进行设置，范围：0~100A。">
        <InputNumber min={0} max={100} step={0.1} value={acChargeCurrent} onChange={(v) => setAcChargeCurrent(v ?? 0)} style={{ width: 140, ...(!acShowCurrent ? disabledInputStyle : {}) }} disabled={!acShowCurrent} />
        <SettingButton onClick={() => handleSet('交流充电电池电流')} disabled={!acShowCurrent} />
      </FieldRow>

      <FieldRow label="交流充电开始电池电压(V)" tooltip="根据电池要求进行设置，范围：38.4~52V。">
        <InputNumber min={0} max={52} step={0.1} value={acChargeStartVoltage} onChange={(v) => setAcChargeStartVoltage(v ?? 0)} style={{ width: 140, ...(!acShowVoltage ? disabledInputStyle : {}) }} disabled={!acShowVoltage} />
        <SettingButton onClick={() => handleSet('交流充电开始电池电压')} disabled={!acShowVoltage} />
      </FieldRow>

      <FieldRow label="交流充电结束电池电压(V)" tooltip="根据电池要求进行设置，范围：48~59V。">
        <InputNumber min={0} max={59} step={0.1} value={acChargeEndVoltage} onChange={(v) => setAcChargeEndVoltage(v ?? 0)} style={{ width: 140, ...(!acShowVoltage ? disabledInputStyle : {}) }} disabled={!acShowVoltage} />
        <SettingButton onClick={() => handleSet('交流充电结束电池电压')} disabled={!acShowVoltage} />
      </FieldRow>

      <FieldRow label="交流充电开始电池SOC(%)" tooltip="根据电池要求进行设置，范围：0~90%。">
        <InputNumber min={0} max={90} value={acChargeStartSoc} onChange={(v) => setAcChargeStartSoc(v ?? 0)} style={{ width: 140, ...(!acShowSoc ? disabledInputStyle : {}) }} disabled={!acShowSoc} />
        <SettingButton onClick={() => handleSet('交流充电开始电池SOC')} disabled={!acShowSoc} />
      </FieldRow>

      <FieldRow label="交流充电结束电池SOC(%)" tooltip="根据电池要求进行设置，范围：20~100%。">
        <InputNumber min={0} max={100} value={acChargeEndSoc} onChange={(v) => setAcChargeEndSoc(v ?? 0)} style={{ width: 140, ...(!acShowSoc ? disabledInputStyle : {}) }} disabled={!acShowSoc} />
        <SettingButton onClick={() => handleSet('交流充电结束电池SOC')} disabled={!acShowSoc} />
      </FieldRow>

      <TimeRangeField label="AC充电起始时间1" h={acStart1H} m={acStart1M} onHChange={(v) => setAcStart1H(v ?? 0)} onMChange={(v) => setAcStart1M(v ?? 0)} onSet={() => handleSet('AC充电起始时间1')} disabled={!acShowTime} />
      <TimeRangeField label="AC充电结束时间1" h={acEnd1H} m={acEnd1M} onHChange={(v) => setAcEnd1H(v ?? 0)} onMChange={(v) => setAcEnd1M(v ?? 0)} onSet={() => handleSet('AC充电结束时间1')} disabled={!acShowTime} />
      <TimeRangeField label="AC充电起始时间2" h={acStart2H} m={acStart2M} onHChange={(v) => setAcStart2H(v ?? 0)} onMChange={(v) => setAcStart2M(v ?? 0)} onSet={() => handleSet('AC充电起始时间2')} disabled={!acShowTime} />
      <TimeRangeField label="AC充电结束时间2" h={acEnd2H} m={acEnd2M} onHChange={(v) => setAcEnd2H(v ?? 0)} onMChange={(v) => setAcEnd2M(v ?? 0)} onSet={() => handleSet('AC充电结束时间2')} disabled={!acShowTime} />
      <TimeRangeField label="AC充电起始时间3" h={acStart3H} m={acStart3M} onHChange={(v) => setAcStart3H(v ?? 0)} onMChange={(v) => setAcStart3M(v ?? 0)} onSet={() => handleSet('AC充电起始时间3')} disabled={!acShowTime} />
      <TimeRangeField label="AC充电结束时间3" h={acEnd3H} m={acEnd3M} onHChange={(v) => setAcEnd3H(v ?? 0)} onMChange={(v) => setAcEnd3M(v ?? 0)} onSet={() => handleSet('AC充电结束时间3')} disabled={!acShowTime} />

      <Col span={24}><Divider style={{ margin: '8px 0' }} /></Col>

      {/* 发电机充电 */}
      <SubGroupTitle title="发电机充电" color={sectionColor} />

      <FieldRow label="发电机充电类型" tooltip="根据电池电压或电池SOC设置发电机充电。">
        <Select value={genChargeType} onChange={(v: number) => setGenChargeType(v)} style={{ width: 140 }}>
          <Option value={0}>电池电压</Option>
          <Option value={1}>电池SOC</Option>
        </Select>
        <SettingButton onClick={handleGenTypeSet} />
      </FieldRow>

      <FieldRow label="发电机充电电池电流(A)" tooltip="设置发电机电池充电电流。范围为0-110安培。">
        <InputNumber min={0} max={110} step={0.1} value={genChargeCurrent} onChange={(v) => setGenChargeCurrent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('发电机充电电池电流')} />
      </FieldRow>

      <FieldRow label="发电机充电开始电池电压(V)" tooltip="根据电池要求进行设置，范围：38.4~52V。">
        <InputNumber min={0} max={52} step={0.1} value={genChargeStartVoltage} onChange={(v) => setGenChargeStartVoltage(v ?? 0)} style={{ width: 140, ...(!genShowVoltage ? disabledInputStyle : {}) }} disabled={!genShowVoltage} />
        <SettingButton onClick={() => handleSet('发电机充电开始电池电压')} disabled={!genShowVoltage} />
      </FieldRow>

      <FieldRow label="发电机充电结束电池电压(V)" tooltip="根据电池要求进行设置，范围：48~59V。">
        <InputNumber min={0} max={59} step={0.1} value={genChargeEndVoltage} onChange={(v) => setGenChargeEndVoltage(v ?? 0)} style={{ width: 140, ...(!genShowVoltage ? disabledInputStyle : {}) }} disabled={!genShowVoltage} />
        <SettingButton onClick={() => handleSet('发电机充电结束电池电压')} disabled={!genShowVoltage} />
      </FieldRow>

      <FieldRow label="发电机充电开始电池SOC(%)" tooltip="根据电池要求进行设置，范围：0~90%。">
        <InputNumber min={0} max={90} value={genChargeStartSoc} onChange={(v) => setGenChargeStartSoc(v ?? 0)} style={{ width: 140, ...(!genShowSoc ? disabledInputStyle : {}) }} disabled={!genShowSoc} />
        <SettingButton onClick={() => handleSet('发电机充电开始电池SOC')} disabled={!genShowSoc} />
      </FieldRow>

      <FieldRow label="发电机充电结束电池SOC(%)" tooltip="根据电池要求进行设置，范围：20~100%。">
        <InputNumber min={0} max={100} value={genChargeEndSoc} onChange={(v) => setGenChargeEndSoc(v ?? 0)} style={{ width: 140, ...(!genShowSoc ? disabledInputStyle : {}) }} disabled={!genShowSoc} />
        <SettingButton onClick={() => handleSet('发电机充电结束电池SOC')} disabled={!genShowSoc} />
      </FieldRow>

      <FieldRow label="发电机额定功率(W)" tooltip="范围 0~7370（单台）65534（并联）。逆变器将限制功率为发电机总输入的 90% 以避免过载。">
        <InputNumber min={0} max={7370} value={genRatedPower} onChange={(v) => setGenRatedPower(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('发电机额定功率')} />
      </FieldRow>

      <SwitchField label="发电机提升" checked={genBoost} onChange={(v) => { setGenBoost(v); handleSet('发电机提升') }} enableText="启用" disableText="禁用" />
    </Row>
  )
}

export default ChargeSection
