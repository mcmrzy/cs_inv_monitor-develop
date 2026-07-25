import React, { useState } from 'react'
import { Row, Col, InputNumber, App, Typography, Space, Button, Select } from 'antd'
import useTranslation from '@/hooks/useTranslation'
import { FieldRow, SettingButton, PRIMARY, labelStyle, fieldRowStyle } from './shared-styles'

const { Text } = Typography
const { Option } = Select

const OtherSection: React.FC = () => {
  const { t } = useTranslation()
  const { message } = App.useApp()

  const [ctCompensation, setCtCompensation] = useState<number>(0)
  const [batteryVoltageSample, setBatteryVoltageSample] = useState<number>(0)
  const [fan1MaxSpeed, setFan1MaxSpeed] = useState<number>(100)
  const [fan1SlopeMode, setFan1SlopeMode] = useState<'default' | 'custom'>('default')
  const [fan1Slope, setFan1Slope] = useState<number>(50)
  const [fan2MaxSpeed, setFan2MaxSpeed] = useState<number>(100)
  const [fan2SlopeMode, setFan2SlopeMode] = useState<'default' | 'custom'>('default')
  const [fan2Slope, setFan2Slope] = useState<number>(50)

  const handleSet = (fieldName: string) => {
    message.success(t('remote.executeSuccess', { title: fieldName }))
  }

  return (
    <Row gutter={[16, 8]}>
      <FieldRow label={`${t('remote.ctPowerCompensation')}(W)`} range="[-199, 199]">
        <InputNumber min={-199} max={199} value={ctCompensation} onChange={(v) => setCtCompensation(v ?? 0)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.ctPowerCompensation'))} />
      </FieldRow>

      <FieldRow label={t('remote.batteryVoltageSample')} tooltip={t('remote.batteryVoltageSampleTip')}>
        <Select<number> value={batteryVoltageSample} onChange={setBatteryVoltageSample} style={{ width: 160 }}>
          <Option value={1}>{t('remote.disableExternalSample')}</Option>
          <Option value={2}>{t('remote.disableInternalSample')}</Option>
          <Option value={0}>{t('remote.bothSamplesEnable')}</Option>
        </Select>
        <SettingButton onClick={() => handleSet(t('remote.batteryVoltageSample'))} />
      </FieldRow>

      <FieldRow label={`${t('remote.fan1MaxSpeed')}(%)`} range="[10, 100]" tooltip={t('remote.fanMaxSpeedTip')}>
        <InputNumber min={10} max={100} value={fan1MaxSpeed} onChange={(v) => setFan1MaxSpeed(v ?? 10)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.fan1MaxSpeed'))} />
      </FieldRow>

      {/* 转速斜率控制1 - 两个按钮 */}
      <Col span={24}>
        <div style={{ ...fieldRowStyle, display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap' }}>
          <Text style={{ ...labelStyle, marginBottom: 0, flexShrink: 0, marginRight: 12 }}>{t('remote.slopeControl1')}</Text>
          <Space size={4}>
            <Button
              type={fan1SlopeMode === 'default' ? 'primary' : 'default'}
              size="small"
              onClick={() => { setFan1SlopeMode('default'); handleSet(`${t('remote.slopeControl1')}-${t('remote.defaultMode')}`) }}
              style={fan1SlopeMode === 'default' ? { background: '#10b981', borderColor: '#10b981' } : {}}
            >
              {t('remote.defaultMode')}
            </Button>
            <Button
              type={fan1SlopeMode === 'custom' ? 'primary' : 'default'}
              size="small"
              onClick={() => setFan1SlopeMode('custom')}
              style={fan1SlopeMode === 'custom' ? { background: PRIMARY, borderColor: PRIMARY } : {}}
            >
              {t('remote.newSlope')}
            </Button>
          </Space>
          {fan1SlopeMode === 'custom' && (
            <div style={{ marginTop: 6, width: '100%' }}>
              <Space>
                <InputNumber min={1} max={100} value={fan1Slope} onChange={(v) => setFan1Slope(v ?? 1)} style={{ width: 100 }} />
                <SettingButton onClick={() => handleSet(t('remote.slopeControl1'))} />
              </Space>
            </div>
          )}
        </div>
      </Col>

      <FieldRow label={`${t('remote.fan2MaxSpeed')}(%)`} range="[10, 100]" tooltip={t('remote.fanMaxSpeedTip')}>
        <InputNumber min={10} max={100} value={fan2MaxSpeed} onChange={(v) => setFan2MaxSpeed(v ?? 10)} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.fan2MaxSpeed'))} />
      </FieldRow>

      {/* 转速斜率控制2 - 两个按钮 */}
      <Col span={24}>
        <div style={{ ...fieldRowStyle, display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap' }}>
          <Text style={{ ...labelStyle, marginBottom: 0, flexShrink: 0, marginRight: 12 }}>{t('remote.slopeControl2')}</Text>
          <Space size={4}>
            <Button
              type={fan2SlopeMode === 'default' ? 'primary' : 'default'}
              size="small"
              onClick={() => { setFan2SlopeMode('default'); handleSet(`${t('remote.slopeControl2')}-${t('remote.defaultMode')}`) }}
              style={fan2SlopeMode === 'default' ? { background: '#10b981', borderColor: '#10b981' } : {}}
            >
              {t('remote.defaultMode')}
            </Button>
            <Button
              type={fan2SlopeMode === 'custom' ? 'primary' : 'default'}
              size="small"
              onClick={() => setFan2SlopeMode('custom')}
              style={fan2SlopeMode === 'custom' ? { background: PRIMARY, borderColor: PRIMARY } : {}}
            >
              {t('remote.newSlope')}
            </Button>
          </Space>
          {fan2SlopeMode === 'custom' && (
            <div style={{ marginTop: 6, width: '100%' }}>
              <Space>
                <InputNumber min={1} max={100} value={fan2Slope} onChange={(v) => setFan2Slope(v ?? 1)} style={{ width: 100 }} />
                <SettingButton onClick={() => handleSet(t('remote.slopeControl2'))} />
              </Space>
            </div>
          )}
        </div>
      </Col>
    </Row>
  )
}

export default OtherSection
