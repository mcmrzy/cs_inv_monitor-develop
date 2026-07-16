import React from 'react'
import { Row, Col, Spin, Button, Modal } from 'antd'
import {
  PoweroffOutlined,
  ThunderboltOutlined,
  SettingOutlined,
  ReloadOutlined,
} from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { useControlState } from '../hooks/useControlState'
import SettingField from './SettingField'
import SettingSection from './SettingSection'

interface GeneralSettingsTabProps {
  sn: string
}

const GeneralSettingsTab: React.FC<GeneralSettingsTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { reported, isOnline, isLoading, error, refetch, sendCommand, isSending } =
    useControlState(sn)

  return (
    <Spin spinning={isLoading}>
      {error && (
        <QueryErrorAlert
          error={error}
          onRetry={() => {
            void refetch()
          }}
          style={{ marginBottom: 16 }}
        />
      )}

      <Row gutter={[16, 16]}>
        {/* ── 基础控制：AC 开关 ── */}
        <Col xs={24} md={12}>
          <SettingSection title={t('remote.acSwitch')} icon={<PoweroffOutlined />}>
            <SettingField
              label={t('remote.acSwitch')}
              fieldKey="ac_enabled"
              type="switch"
              reportedValue={reported.ac_enabled}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand(v ? 'ac_on' : 'ac_off')}
            />
          </SettingSection>
        </Col>

        {/* ── 功率限制 ── */}
        <Col xs={24} md={12}>
          <SettingSection title={t('remote.powerLimit')} icon={<ThunderboltOutlined />}>
            <SettingField
              label={t('remote.powerLimitLabel')}
              fieldKey="power_limit_w"
              type="number"
              min={0}
              max={6200}
              step={100}
              unit="W"
              reportedValue={reported.power_limit_w}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_power_limit', { watts: v })}
            />
          </SettingSection>
        </Col>

        {/* ── 设备基础配置 ── */}
        <Col xs={24} md={12}>
          <SettingSection title="设备基础配置" icon={<SettingOutlined />}>
            <SettingField
              label={t('remote.pvWiring')}
              fieldKey="pv_connection_type"
              type="select"
              options={[
                { label: t('remote.singlePhase'), value: 'single' },
                { label: t('remote.twoPhase'), value: 'two' },
                { label: t('remote.threePhase'), value: 'three' },
              ]}
              reportedValue={reported.pv_connection_type}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { pv_connection_type: v })}
              tooltip={t('remote.pendingProtocol')}
            />

            <SettingField
              label={t('remote.batteryTypeLabel')}
              fieldKey="battery_type_setting"
              type="select"
              options={[
                { label: t('remote.lithiumIron'), value: 'lifepo4' },
                { label: t('remote.lithiumTernary'), value: 'ncm' },
                { label: t('remote.leadAcid'), value: 'lead_acid' },
              ]}
              reportedValue={reported.battery_type_setting}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { battery_type_setting: v })}
              tooltip={t('remote.pendingProtocol')}
            />

            <SettingField
              label={t('remote.regulation')}
              fieldKey="grid_regulation"
              type="select"
              options={[
                { label: t('remote.china'), value: 'china' },
                { label: t('remote.europe'), value: 'europe' },
                { label: t('remote.australia'), value: 'australia' },
              ]}
              reportedValue={reported.grid_regulation}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { grid_regulation: v })}
              tooltip={t('remote.pendingProtocol')}
            />
          </SettingSection>
        </Col>

        {/* ── 节能与开关 ── */}
        <Col xs={24} md={12}>
          <SettingSection title="节能与开关" icon={<SettingOutlined />}>
            <SettingField
              label={t('remote.standby')}
              fieldKey="standby"
              type="switch"
              reportedValue={reported.standby}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { standby: v })}
              tooltip={t('remote.pendingProtocol')}
            />

            <SettingField
              label={t('remote.ecoMode')}
              fieldKey="eco_mode"
              type="switch"
              reportedValue={reported.eco_mode}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { eco_mode: v })}
              tooltip={t('remote.pendingProtocol')}
            />

            <SettingField
              label={t('remote.buzzerEnable')}
              fieldKey="buzzer_enable"
              type="switch"
              reportedValue={reported.buzzer_enable}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { buzzer_enable: v })}
              tooltip={t('remote.pendingProtocol')}
            />

            <SettingField
              label={t('remote.batteryEcoMode')}
              fieldKey="battery_eco_mode"
              type="switch"
              reportedValue={reported.battery_eco_mode}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { battery_eco_mode: v })}
              tooltip={t('remote.pendingProtocol')}
            />
          </SettingSection>
        </Col>

        {/* ── 逆变器控制：重启 ── */}
        <Col xs={24} md={12}>
          <SettingSection title={t('remote.restartInverter')} icon={<ReloadOutlined />}>
            <Button
              danger
              disabled={!isOnline}
              loading={isSending}
              onClick={() => {
                Modal.confirm({
                  title: t('remote.restartConfirm'),
                  onOk: () => sendCommand('restart'),
                })
              }}
            >
              {t('remote.restartInverter')}
            </Button>
          </SettingSection>
        </Col>
      </Row>
    </Spin>
  )
}

export default GeneralSettingsTab
