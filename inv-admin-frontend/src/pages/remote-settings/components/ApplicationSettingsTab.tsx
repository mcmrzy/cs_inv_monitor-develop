import React from 'react'
import { Row, Col, Spin } from 'antd'
import { ThunderboltOutlined, SettingOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { useControlState } from '../hooks/useControlState'
import SettingField from './SettingField'
import SettingSection from './SettingSection'

interface ApplicationSettingsTabProps {
  sn: string
}

const ApplicationSettingsTab: React.FC<ApplicationSettingsTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { reported, isOnline, isLoading, error, refetch, sendCommand, isSending } =
    useControlState(sn)

  const pendingProtocol = t('remote.pendingProtocol')

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
        {/* ── 离网输出 ── */}
        <Col xs={24} md={12}>
          <SettingSection
            title={t('remote.offgridOutputVoltage')}
            icon={<ThunderboltOutlined />}
          >
            <SettingField
              label={t('remote.offgridOutputVoltage')}
              fieldKey="offgrid_voltage"
              type="select"
              options={[
                { label: '220V', value: 220 },
                { label: '230V', value: 230 },
                { label: '240V', value: 240 },
              ]}
              reportedValue={reported.offgrid_voltage}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { offgrid_voltage: v })}
              tooltip={pendingProtocol}
            />

            <SettingField
              label={t('remote.offgridOutputFreq')}
              fieldKey="offgrid_freq"
              type="select"
              options={[
                { label: '50Hz', value: 50 },
                { label: '60Hz', value: 60 },
              ]}
              reportedValue={reported.offgrid_freq}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { offgrid_freq: v })}
              tooltip={pendingProtocol}
            />

            <SettingField
              label={t('remote.acInputRange')}
              fieldKey="ac_input_range"
              type="select"
              options={[
                { label: t('remote.wideRange'), value: 'wide' },
                { label: t('remote.narrowRange'), value: 'narrow' },
              ]}
              reportedValue={reported.ac_input_range}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { ac_input_range: v })}
              tooltip={pendingProtocol}
            />
          </SettingSection>
        </Col>

        {/* ── PV 与交流电优先 ── */}
        <Col xs={24} md={12}>
          <SettingSection title={t('remote.pvOffgrid')} icon={<SettingOutlined />}>
            <SettingField
              label={t('remote.pvOffgrid')}
              fieldKey="pv_offgrid"
              type="switch"
              reportedValue={reported.pv_offgrid}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { pv_offgrid: v })}
              tooltip={pendingProtocol}
            />

            <SettingField
              label={t('remote.acPriority')}
              fieldKey="ac_priority"
              type="switch"
              reportedValue={reported.ac_priority}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { ac_priority: v })}
              tooltip={pendingProtocol}
            />
          </SettingSection>
        </Col>

        {/* ── 交流电优先时间段 ── */}
        <Col xs={24} md={12}>
          <SettingSection title={t('remote.acPriorityStart')}>
            {/* 时间段 1 */}
            <SettingField
              label={`${t('remote.acPriorityStart')} 1`}
              fieldKey="ac_priority_start_1"
              type="time-range"
              reportedValue={
                reported.ac_priority_start_1_h !== undefined
                  ? [reported.ac_priority_start_1_h, reported.ac_priority_start_1_m]
                  : undefined
              }
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) =>
                sendCommand('set_params', {
                  ac_priority_start_1_h: v.hour,
                  ac_priority_start_1_m: v.minute,
                })
              }
              tooltip={pendingProtocol}
            />
            <SettingField
              label={`${t('remote.acPriorityEnd')} 1`}
              fieldKey="ac_priority_end_1"
              type="time-range"
              reportedValue={
                reported.ac_priority_end_1_h !== undefined
                  ? [reported.ac_priority_end_1_h, reported.ac_priority_end_1_m]
                  : undefined
              }
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) =>
                sendCommand('set_params', {
                  ac_priority_end_1_h: v.hour,
                  ac_priority_end_1_m: v.minute,
                })
              }
              tooltip={pendingProtocol}
            />

            {/* 时间段 2 */}
            <SettingField
              label={`${t('remote.acPriorityStart')} 2`}
              fieldKey="ac_priority_start_2"
              type="time-range"
              reportedValue={
                reported.ac_priority_start_2_h !== undefined
                  ? [reported.ac_priority_start_2_h, reported.ac_priority_start_2_m]
                  : undefined
              }
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) =>
                sendCommand('set_params', {
                  ac_priority_start_2_h: v.hour,
                  ac_priority_start_2_m: v.minute,
                })
              }
              tooltip={pendingProtocol}
            />
            <SettingField
              label={`${t('remote.acPriorityEnd')} 2`}
              fieldKey="ac_priority_end_2"
              type="time-range"
              reportedValue={
                reported.ac_priority_end_2_h !== undefined
                  ? [reported.ac_priority_end_2_h, reported.ac_priority_end_2_m]
                  : undefined
              }
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) =>
                sendCommand('set_params', {
                  ac_priority_end_2_h: v.hour,
                  ac_priority_end_2_m: v.minute,
                })
              }
              tooltip={pendingProtocol}
            />

            {/* 时间段 3 */}
            <SettingField
              label={`${t('remote.acPriorityStart')} 3`}
              fieldKey="ac_priority_start_3"
              type="time-range"
              reportedValue={
                reported.ac_priority_start_3_h !== undefined
                  ? [reported.ac_priority_start_3_h, reported.ac_priority_start_3_m]
                  : undefined
              }
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) =>
                sendCommand('set_params', {
                  ac_priority_start_3_h: v.hour,
                  ac_priority_start_3_m: v.minute,
                })
              }
              tooltip={pendingProtocol}
            />
            <SettingField
              label={`${t('remote.acPriorityEnd')} 3`}
              fieldKey="ac_priority_end_3"
              type="time-range"
              reportedValue={
                reported.ac_priority_end_3_h !== undefined
                  ? [reported.ac_priority_end_3_h, reported.ac_priority_end_3_m]
                  : undefined
              }
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) =>
                sendCommand('set_params', {
                  ac_priority_end_3_h: v.hour,
                  ac_priority_end_3_m: v.minute,
                })
              }
              tooltip={pendingProtocol}
            />
          </SettingSection>
        </Col>
      </Row>
    </Spin>
  )
}

export default ApplicationSettingsTab
