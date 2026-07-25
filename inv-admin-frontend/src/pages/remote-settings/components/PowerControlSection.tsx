import React, { useState } from 'react'
import { Row, Select, InputNumber, App } from 'antd'
import useTranslation from '@/hooks/useTranslation'
import { FieldRow, SwitchField, SettingButton } from './shared-styles'

const { Option } = Select

interface Props {
  deviceInfo: any
}

const PowerControlSection: React.FC<Props> = ({ deviceInfo }) => {
  const { message } = App.useApp()
  const { t } = useTranslation()

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
    message.success(t('remote.executeSuccess', { title: fieldName }))
  }

  return (
    <Row gutter={[16, 8]}>
      <SwitchField label={t('remote.overFreqDerating')} checked={freqDeratingEnable} onChange={(v) => { setFreqDeratingEnable(v); handleSet(t('remote.overFreqDerating')) }} />

      <FieldRow label={t('remote.reactiveOutputMode')}>
        <Select value={reactivePowerMode} onChange={setReactivePowerMode} style={{ width: 140 }}>
          <Option value="fixed_pf">{t('remote.fixedPfOutput')}</Option>
          <Option value="fixed_q">{t('remote.fixedReactivePower')}</Option>
          <Option value="volt_var">{t('remote.voltVarCurve')}</Option>
          <Option value="pf_p">{t('remote.pfPCurve')}</Option>
        </Select>
        <SettingButton onClick={() => handleSet(t('remote.reactiveOutputMode'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.reactivePct')}(%)`} range="0~60">
        <InputNumber min={0} max={60} value={reactivePowerPercent} onChange={(v) => setReactivePowerPercent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.reactivePct'))} />
      </FieldRow>

      <FieldRow label={t('remote.pfSetting')} range="750~2000">
        <InputNumber min={750} max={2000} value={pfValue} onChange={(v) => setPfValue(v ?? 750)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.pfSetting'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.activePowerPct')}(%)`} range="0~100">
        <InputNumber min={0} max={100} value={activePowerPercent} onChange={(v) => setActivePowerPercent(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.activePowerPct'))} />
      </FieldRow>

      <SwitchField label={t('remote.gridSoftStart')} checked={gridSoftStart} onChange={(v) => { setGridSoftStart(v); handleSet(t('remote.gridSoftStart')) }} />

      <FieldRow label={t('remote.gridProtectionLevel')}>
        <Select value={gridProtectionLevel} onChange={setGridProtectionLevel} style={{ width: 140 }}>
          <Option value="level1">{t('remote.level1Protection')}</Option>
          <Option value="level2">{t('remote.level2Protection')}</Option>
          <Option value="level3">{t('remote.level3Protection')}</Option>
        </Select>
        <SettingButton onClick={() => handleSet(t('remote.gridProtectionLevel'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridVoltL1Under')}(V)`}>
        <InputNumber value={v1UnderVoltage} onChange={(v) => setV1UnderVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridVoltL1Under'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridVoltL1Over')}(V)`}>
        <InputNumber value={v1OverVoltage} onChange={(v) => setV1OverVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridVoltL1Over'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridFreqL1Under')}(Hz)`}>
        <InputNumber value={f1UnderFreq} onChange={(v) => setF1UnderFreq(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridFreqL1Under'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridFreqL1Over')}(Hz)`}>
        <InputNumber value={f1OverFreq} onChange={(v) => setF1OverFreq(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridFreqL1Over'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridVoltSlideAvgOver')}(V)`}>
        <InputNumber value={vMovingAvgOverVoltage} onChange={(v) => setVMovingAvgOverVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridVoltSlideAvgOver'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridVoltL2Under')}(V)`}>
        <InputNumber value={v2UnderVoltage} onChange={(v) => setV2UnderVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridVoltL2Under'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridVoltL2Over')}(V)`}>
        <InputNumber value={v2OverVoltage} onChange={(v) => setV2OverVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridVoltL2Over'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridFreqL2Under')}(Hz)`}>
        <InputNumber value={f2UnderFreq} onChange={(v) => setF2UnderFreq(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridFreqL2Under'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridFreqL2Over')}(Hz)`}>
        <InputNumber value={f2OverFreq} onChange={(v) => setF2OverFreq(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridFreqL2Over'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.rampRate')}(%)`} range="1~100">
        <InputNumber min={1} max={100} value={rampRate} onChange={(v) => setRampRate(v ?? 1)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.rampRate'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridVoltL3Under')}(V)`}>
        <InputNumber value={v3UnderVoltage} onChange={(v) => setV3UnderVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridVoltL3Under'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridVoltL3Over')}(V)`}>
        <InputNumber value={v3OverVoltage} onChange={(v) => setV3OverVoltage(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridVoltL3Over'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridFreqL3Under')}(Hz)`}>
        <InputNumber value={f3UnderFreq} onChange={(v) => setF3UnderFreq(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridFreqL3Under'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.gridFreqL3Over')}(Hz)`}>
        <InputNumber value={f3OverFreq} onChange={(v) => setF3OverFreq(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.gridFreqL3Over'))} />
      </FieldRow>
    </Row>
  )
}

export default PowerControlSection
