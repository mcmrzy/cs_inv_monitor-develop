import React, { useState } from 'react'
import { Row, Select, App } from 'antd'
import useTranslation from '@/hooks/useTranslation'
import { FieldRow, SwitchField, SettingButton } from './shared-styles'

const { Option } = Select

const ParallelSection: React.FC = () => {
  const { t } = useTranslation()
  const { message } = App.useApp()

  const [systemType, setSystemType] = useState('single')
  const [sharedBattery, setSharedBattery] = useState(false)
  const [gridPhase, setGridPhase] = useState('L1')
  const [noGridInput, setNoGridInput] = useState(false)

  const handleSet = (fieldName: string) => {
    message.success(t('remote.executeSuccess', { title: fieldName }))
  }

  return (
    <Row gutter={[16, 8]}>
      <FieldRow label={t('remote.systemType')}>
        <Select value={systemType} onChange={setSystemType} style={{ width: 140 }}>
          <Option value="single">{t('remote.singleMachine')}</Option>
          <Option value="single_phase_parallel">{t('remote.singlePhaseParallel')}</Option>
          <Option value="three_phase_parallel">{t('remote.threePhaseParallel')}</Option>
        </Select>
        <SettingButton onClick={() => handleSet(t('remote.systemType'))} />
      </FieldRow>

      <FieldRow label={t('remote.setGridPhase')}>
        <Select value={gridPhase} onChange={setGridPhase} style={{ width: 140 }}>
          <Option value="L1">L1</Option>
          <Option value="L2">L2</Option>
          <Option value="L3">L3</Option>
        </Select>
        <SettingButton onClick={() => handleSet(t('remote.setGridPhase'))} />
      </FieldRow>

      <SwitchField label={t('remote.sharedBattery')} checked={sharedBattery} onChange={(v) => { setSharedBattery(v); handleSet(t('remote.sharedBattery')) }} />
      <SwitchField label={t('remote.noGridInput')} checked={noGridInput} onChange={(v) => { setNoGridInput(v); handleSet(t('remote.noGridInput')) }} />
    </Row>
  )
}

export default ParallelSection
