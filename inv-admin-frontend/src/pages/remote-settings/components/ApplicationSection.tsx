import React, { useState } from 'react'
import { Row, Col, Select, InputNumber, App, Typography, Space, Tooltip, Switch } from 'antd'
import { QuestionCircleOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
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

const TimeRangeField: React.FC<TimeRangeFieldProps> = ({ label, h, m, onHChange, onMChange, onSet, tooltip }) => {
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
        <InputNumber min={0} max={23} value={h} onChange={onHChange} style={{ width: 70 }} addonAfter={t('remote.hour')} />
        <Text>:</Text>
        <InputNumber min={0} max={59} value={m} onChange={onMChange} style={{ width: 70 }} addonAfter={t('remote.minute')} />
        <SettingButton onClick={onSet} />
      </Space>
    </div>
  </Col>
  )
}

const ApplicationSection: React.FC = () => {
  const { t } = useTranslation()
  const { message } = App.useApp()

  // 顶层新增字段
  const [highGridFreq, setHighGridFreq] = useState('50')
  const [highGridMode, setHighGridMode] = useState(false)
  const [microGrid, setMicroGrid] = useState(false)
  const [gridTied, setGridTied] = useState(false)
  const [fastAntiBackflow, setFastAntiBackflow] = useState(false)
  const [reverseCtDirection, setReverseCtDirection] = useState(false)
  const [onStandby, setOnStandby] = useState(false)

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
  const [gridTiedPowerPercent, setGridTiedPowerPercent] = useState<number>(0)
  const [ctPowerCompensation, setCtPowerCompensation] = useState<number>(0)
  const [gridMaxInputPower, setGridMaxInputPower] = useState<number>(0)
  const [gridCtConnection, setGridCtConnection] = useState(false)
  // 新增混合设置字段
  const [pvMaxPowerPercent, setPvMaxPowerPercent] = useState<number>(100)
  const [acChargeMaxPower, setAcChargeMaxPower] = useState<number>(0)
  const [batteryChargeMaxPower, setBatteryChargeMaxPower] = useState<number>(0)
  const [systemMaxPower, setSystemMaxPower] = useState<number>(0)

  // 并联设置
  const [systemType, setSystemType] = useState<number>(0)
  const [sharedBattery, setSharedBattery] = useState(false)
  const [composedPhase, setComposedPhase] = useState<number>(1)

  // 无市电输入
  const [noGridInput, setNoGridInput] = useState(false)

  const handleSet = (fieldName: string) => {
    message.success(t('remote.executeSuccess', { title: fieldName }))
  }

  return (
    <Row gutter={[16, 8]}>
      {/* 顶层新增字段 */}
      <FieldRow label={`${t('remote.highGridFreq')}(Hz)`} tooltip={t('remote.highGridFreqTip')}>
        <Select value={highGridFreq} onChange={setHighGridFreq} style={{ width: 140 }} showSearch>
          <Option value="50">50</Option>
          <Option value="60">60</Option>
        </Select>
        <SettingButton onClick={() => handleSet(t('remote.highGridFreq'))} />
      </FieldRow>

      <SwitchField label={t('remote.highGridMode')} checked={highGridMode} onChange={(v) => { setHighGridMode(v); handleSet(t('remote.highGridMode')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.highGridModeTip')} />
      <SwitchField label={t('remote.microGrid')} checked={microGrid} onChange={(v) => { setMicroGrid(v); handleSet(t('remote.microGrid')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.microGridTip')} />
      <SwitchField label={t('remote.gridTied')} checked={gridTied} onChange={(v) => { setGridTied(v); handleSet(t('remote.gridTied')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.gridTiedTip')} />
      <SwitchField label={t('remote.fastAntiBackflow')} checked={fastAntiBackflow} onChange={(v) => { setFastAntiBackflow(v); handleSet(t('remote.fastAntiBackflow')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.fastAntiBackflowTip')} />
      <SwitchField label={t('remote.ctDirectionReverse')} checked={reverseCtDirection} onChange={(v) => { setReverseCtDirection(v); handleSet(t('remote.ctDirectionReverse')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.ctReverse')} />
      <SwitchField label={t('remote.standby')} checked={onStandby} onChange={(v) => { setOnStandby(v); handleSet(t('remote.standby')) }} enableText={t('remote.powerOn')} disableText={t('remote.standbyMode')} tooltip={t('remote.standbyTip')} />

      <FieldRow label={`${t('remote.offgridVoltage')}(V)`} tooltip={t('remote.offgridVoltageTip')}>
        <Select value={outputVoltage} onChange={setOutputVoltage} style={{ width: 140 }} showSearch>
          <Option value="220">220</Option>
          <Option value="230">230</Option>
          <Option value="240">240</Option>
        </Select>
        <SettingButton onClick={() => handleSet(t('remote.offgridVoltage'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.offgridFrequency')}(Hz)`} tooltip={t('remote.offgridFreqTip')}>
        <Select value={outputFreq} onChange={setOutputFreq} style={{ width: 140 }} showSearch>
          <Option value="50">50</Option>
          <Option value="60">60</Option>
        </Select>
        <SettingButton onClick={() => handleSet(t('remote.offgridFrequency'))} />
      </FieldRow>

      <FieldRow label={t('remote.acInputRange')} tooltip={t('remote.acInputRangeTip')}>
        <Select value={acInputRange} onChange={setAcInputRange} style={{ width: 280 }} showSearch>
          <Option value={0}>APL({t('remote.aplRange')})</Option>
          <Option value={1}>UPS({t('remote.upsRange')})</Option>
        </Select>
        <SettingButton onClick={() => handleSet(t('remote.acInputRange'))} />
      </FieldRow>

      <SwitchField label={t('remote.pvOffgrid')} checked={pvOffGrid} onChange={(v) => { setPvOffGrid(v); handleSet(t('remote.pvOffgrid')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.pvOffgridTip')} />
      <SwitchField label={t('remote.nPeConnection')} checked={nPeConnection} onChange={(v) => { setNPeConnection(v); handleSet(t('remote.nPeConnection')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.nPeConnectionTip')} />
      <SubGroupHelp title={t('remote.acPriority')} color="#3b82f6" helpItems={[{ label: t('remote.description'), value: t('remote.acPriorityDesc') }]} />
      <SwitchField label={t('remote.acPriority')} checked={acFirst} onChange={(v) => { setAcFirst(v); handleSet(t('remote.acPriority')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.acPriorityTip')} />

      {/* AC优先时间段 - 仅 acFirst 开启时显示 */}
      {acFirst ? (
        <>
          <TimeRangeField label={`${t('remote.acPriorityStart')} 1`} h={acStart1H} m={acStart1M} onHChange={(v) => setAcStart1H(v ?? 0)} onMChange={(v) => setAcStart1M(v ?? 0)} onSet={() => handleSet(`${t('remote.acPriorityStart')} 1`)} tooltip={t('remote.timeRangeHint')} />
          <TimeRangeField label={`${t('remote.acPriorityEnd')} 1`} h={acEnd1H} m={acEnd1M} onHChange={(v) => setAcEnd1H(v ?? 0)} onMChange={(v) => setAcEnd1M(v ?? 0)} onSet={() => handleSet(`${t('remote.acPriorityEnd')} 1`)} tooltip={t('remote.timeRangeHint')} />
          <TimeRangeField label={`${t('remote.acPriorityStart')} 2`} h={acStart2H} m={acStart2M} onHChange={(v) => setAcStart2H(v ?? 0)} onMChange={(v) => setAcStart2M(v ?? 0)} onSet={() => handleSet(`${t('remote.acPriorityStart')} 2`)} tooltip={t('remote.timeRangeHint')} />
          <TimeRangeField label={`${t('remote.acPriorityEnd')} 2`} h={acEnd2H} m={acEnd2M} onHChange={(v) => setAcEnd2H(v ?? 0)} onMChange={(v) => setAcEnd2M(v ?? 0)} onSet={() => handleSet(`${t('remote.acPriorityEnd')} 2`)} tooltip={t('remote.timeRangeHint')} />
          <TimeRangeField label={`${t('remote.acPriorityStart')} 3`} h={acStart3H} m={acStart3M} onHChange={(v) => setAcStart3H(v ?? 0)} onMChange={(v) => setAcStart3M(v ?? 0)} onSet={() => handleSet(`${t('remote.acPriorityStart')} 3`)} tooltip={t('remote.timeRangeHint')} />
          <TimeRangeField label={`${t('remote.acPriorityEnd')} 3`} h={acEnd3H} m={acEnd3M} onHChange={(v) => setAcEnd3H(v ?? 0)} onMChange={(v) => setAcEnd3M(v ?? 0)} onSet={() => handleSet(`${t('remote.acPriorityEnd')} 3`)} tooltip={t('remote.timeRangeHint')} />
        </>
      ) : (
        <Col span={24}>
          <div style={{ padding: '12px 0', color: '#bbb', fontSize: 13 }}>
            {t('remote.acPriorityHint')}
          </div>
        </Col>
      )}

      {/* 混合设置 */}
      <SubGroupHelp title={t('remote.hybridSettings')} color="#3b82f6" />
      <SwitchField label={t('remote.pvAcLoad')} checked={pvAcLoad} onChange={(v) => { setPvAcLoad(v); handleSet(t('remote.pvAcLoad')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.pvAcLoadTip')} />
      <FieldRow label={t('remote.feedToGrid')} tooltip={t('remote.feedToGridTip')}>
        <Switch checked={feedToGrid} onChange={(v) => { setFeedToGrid(v); handleSet(t('remote.feedToGrid')) }} />
      </FieldRow>

      <FieldRow label={`${t('remote.outputPowerPct')}(%)`} tooltip={t('remote.outputPowerPctTip')}>
        <InputNumber min={0} max={100} value={outputPowerPercent} onChange={(v) => setOutputPowerPercent(v ?? 0)} style={{ width: 120 }} />
        <SettingButton onClick={() => handleSet(t('remote.outputPowerPct'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridtiedPct')}(%)`} tooltip={t('remote.gridtiedPctTip')}>
        <InputNumber min={0} max={100} value={gridTiedPowerPercent} onChange={(v) => setGridTiedPowerPercent(v ?? 0)} style={{ width: 120 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridtiedPct'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.ctPowerCompensation')}(W)`} tooltip={t('remote.ctPowerCompensationTip')}>
        <InputNumber min={-199} max={199} value={ctPowerCompensation} onChange={(v) => setCtPowerCompensation(v ?? 0)} style={{ width: 120 }} />
        <SettingButton onClick={() => handleSet(t('remote.ctPowerCompensation'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridMaxInputPower')}(W)`} tooltip={t('remote.gridMaxInputPowerTip')}>
        <InputNumber min={0} max={65535} value={gridMaxInputPower} onChange={(v) => setGridMaxInputPower(v ?? 0)} style={{ width: 120 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridMaxInputPower'))} />
      </FieldRow>

      <SwitchField label={t('remote.gridCtConnection')} checked={gridCtConnection} onChange={(v) => { setGridCtConnection(v); handleSet(t('remote.gridCtConnection')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.gridCtConnectionTip')} />

      <FieldRow label={`${t('remote.pvMaxPowerPct')}(%)`} tooltip={t('remote.pvMaxPowerPctTip')}>
        <InputNumber min={0} max={100} value={pvMaxPowerPercent} onChange={(v) => setPvMaxPowerPercent(v ?? 100)} style={{ width: 120 }} />
        <SettingButton onClick={() => handleSet(t('remote.pvMaxPowerPct'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.acChargeMaxPower')}(W)`} tooltip={t('remote.acChargeMaxPowerTip')}>
        <InputNumber min={0} max={65535} value={acChargeMaxPower} onChange={(v) => setAcChargeMaxPower(v ?? 0)} style={{ width: 120 }} />
        <SettingButton onClick={() => handleSet(t('remote.acChargeMaxPower'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.batteryChargeMaxPower')}(W)`} tooltip={t('remote.batteryChargeMaxPowerTip')}>
        <InputNumber min={0} max={65535} value={batteryChargeMaxPower} onChange={(v) => setBatteryChargeMaxPower(v ?? 0)} style={{ width: 120 }} />
        <SettingButton onClick={() => handleSet(t('remote.batteryChargeMaxPower'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.systemMaxPower')}(W)`} tooltip={t('remote.systemMaxPowerTip')}>
        <InputNumber min={0} max={65535} value={systemMaxPower} onChange={(v) => setSystemMaxPower(v ?? 0)} style={{ width: 120 }} />
        <SettingButton onClick={() => handleSet(t('remote.systemMaxPower'))} />
      </FieldRow>

      {/* 并联设置 */}
      <SubGroupTitle title={t('remote.parallelSettings')} />

      <FieldRow label={t('remote.systemType')} tooltip={t('remote.systemTypeTip')}>
        <Select value={systemType} onChange={setSystemType} style={{ width: 140 }} showSearch>
          <Option value={0}>{t('remote.singleMachine')}</Option>
          <Option value={1}>{t('remote.singlePhaseParallel')}</Option>
          <Option value={3}>{t('remote.threePhaseParallel')}</Option>
        </Select>
        <SettingButton onClick={() => handleSet(t('remote.systemType'))} />
      </FieldRow>

      <SwitchField label={t('remote.sharedBattery')} checked={sharedBattery} onChange={(v) => { setSharedBattery(v); handleSet(t('remote.sharedBattery')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} tooltip={t('remote.sharedBatteryTip')} />

      <FieldRow label={t('remote.setGridPhase')} tooltip={t('remote.setGridPhaseTip')}>
        <Select value={composedPhase} onChange={setComposedPhase} style={{ width: 140 }} showSearch>
          <Option value={1}>{t('remote.rPhase')}</Option>
          <Option value={2}>{t('remote.sPhase')}</Option>
          <Option value={3}>{t('remote.tPhase')}</Option>
        </Select>
        <SettingButton onClick={() => handleSet(t('remote.setGridPhase'))} />
      </FieldRow>

      {/* 无市电输入 */}
      <SwitchField label={t('remote.noGridInput')} checked={noGridInput} onChange={(v) => { setNoGridInput(v); handleSet(t('remote.noGridInput')) }} enableText={t('remote.enable')} disableText={t('remote.disable')} />
    </Row>
  )
}

export default ApplicationSection
