import React from 'react'
import { Row, Col, Spin } from 'antd'
import { ThunderboltOutlined, SettingOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { useControlState } from '../hooks/useControlState'
import SettingField from './SettingField'
import SettingSection from './SettingSection'

interface OtherSettingsTabProps {
  sn: string
}

const OtherSettingsTab: React.FC<OtherSettingsTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { reported, isOnline, isLoading, error, refetch, sendCommand, isSending } = useControlState(sn)

  return (
    <Spin spinning={isLoading}>
      {error && (
        <QueryErrorAlert
          error={error}
          onRetry={() => { void refetch() }}
          style={{ marginBottom: 16 }}
        />
      )}

      <Row gutter={[16, 16]}>
        <Col xs={24} md={12}>
          <SettingSection title={t('remote.ctPowerCompensation')} icon={<ThunderboltOutlined />}>
            <SettingField
              label={t('remote.ctPowerCompensation')}
              fieldKey="ct_power_comp"
              type="number"
              min={-199}
              max={199}
              step={1}
              unit="W"
              reportedValue={reported.ct_power_comp}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { ct_power_comp: v })}
              tooltip={t('remote.pendingProtocol')}
            />
            <SettingField
              label={t('remote.batteryVoltageSample')}
              fieldKey="battery_v_sample"
              type="switch"
              reportedValue={reported.battery_v_sample}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { battery_v_sample: v })}
              tooltip={t('remote.pendingProtocol')}
            />
            <SettingField
              label={t('remote.disableExternalSample')}
              fieldKey="disable_ext_sample"
              type="switch"
              reportedValue={reported.disable_ext_sample}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { disable_ext_sample: v })}
              tooltip={t('remote.pendingProtocol')}
            />
          </SettingSection>
        </Col>

        <Col xs={24} md={12}>
          <SettingSection title={t('remote.fan1MaxSpeed')} icon={<SettingOutlined />}>
            <SettingField
              label={t('remote.fan1MaxSpeed')}
              fieldKey="fan1_max_speed"
              type="number"
              min={10}
              max={100}
              step={1}
              unit="%"
              reportedValue={reported.fan1_max_speed}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { fan1_max_speed: v })}
              tooltip={t('remote.pendingProtocol')}
            />
            <SettingField
              label={t('remote.slopeControl1')}
              fieldKey="slope_control_1"
              type="number"
              min={1}
              max={100}
              step={1}
              reportedValue={reported.slope_control_1}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { slope_control_1: v })}
              tooltip={t('remote.pendingProtocol')}
            />
            <SettingField
              label={t('remote.fan2MaxSpeed')}
              fieldKey="fan2_max_speed"
              type="number"
              min={10}
              max={100}
              step={1}
              unit="%"
              reportedValue={reported.fan2_max_speed}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { fan2_max_speed: v })}
              tooltip={t('remote.pendingProtocol')}
            />
            <SettingField
              label={t('remote.slopeControl2')}
              fieldKey="slope_control_2"
              type="number"
              min={1}
              max={100}
              step={1}
              reportedValue={reported.slope_control_2}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { slope_control_2: v })}
              tooltip={t('remote.pendingProtocol')}
            />
          </SettingSection>
        </Col>
      </Row>
    </Spin>
  )
}

export default OtherSettingsTab
