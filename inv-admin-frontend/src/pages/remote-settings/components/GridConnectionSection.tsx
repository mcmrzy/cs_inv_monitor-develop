import React, { useState } from 'react'
import { Row, InputNumber, App } from 'antd'
import { FieldRow, SettingButton } from './shared-styles'

interface Props {
  deviceInfo: any
}

const GridConnectionSection: React.FC<Props> = ({ deviceInfo }) => {
  const { message } = App.useApp()

  const [gridWaitTime, setGridWaitTime] = useState<number>(300)
  const [reGridWaitTime, setReGridWaitTime] = useState<number>(60)
  const [gridVoltageUpper, setGridVoltageUpper] = useState<number>(264)
  const [gridVoltageLower, setGridVoltageLower] = useState<number>(176)
  const [gridFreqUpper, setGridFreqUpper] = useState<number>(55)
  const [gridFreqLower, setGridFreqLower] = useState<number>(45)

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 指令已下发`)
  }

  return (
    <Row gutter={[16, 8]}>
      <FieldRow label="并网等待时间(s)" range="30~600">
        <InputNumber min={30} max={600} value={gridWaitTime} onChange={(v) => setGridWaitTime(v ?? 30)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('并网等待时间')} />
      </FieldRow>

      <FieldRow label="重新并网等待时间(s)" range="0~600">
        <InputNumber min={0} max={600} value={reGridWaitTime} onChange={(v) => setReGridWaitTime(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('重新并网等待时间')} />
      </FieldRow>

      <FieldRow label="并网市电电压上限(V)">
        <InputNumber value={gridVoltageUpper} onChange={(v) => setGridVoltageUpper(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('并网市电电压上限')} />
      </FieldRow>

      <FieldRow label="并网市电电压下限(V)">
        <InputNumber value={gridVoltageLower} onChange={(v) => setGridVoltageLower(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('并网市电电压下限')} />
      </FieldRow>

      <FieldRow label="并网市电频率上限(Hz)">
        <InputNumber value={gridFreqUpper} onChange={(v) => setGridFreqUpper(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('并网市电频率上限')} />
      </FieldRow>

      <FieldRow label="并网市电频率下限(Hz)">
        <InputNumber value={gridFreqLower} onChange={(v) => setGridFreqLower(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet('并网市电频率下限')} />
      </FieldRow>
    </Row>
  )
}

export default GridConnectionSection
