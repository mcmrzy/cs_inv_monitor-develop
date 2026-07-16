import React from 'react'
import { Row, Col, Spin } from 'antd'
import { ClockCircleOutlined, ThunderboltOutlined, DashboardOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { useControlState } from '../hooks/useControlState'
import SettingField from './SettingField'
import SettingSection from './SettingSection'

interface GridSettingsTabProps {
  sn: string
}

const GridSettingsTab: React.FC<GridSettingsTabProps> = ({ sn }) => {
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
        {/* ── 并网时间 ── */}
        <Col xs={24} md={12}>
          <SettingSection title={t('remote.gridWaitTime')} icon={<ClockCircleOutlined />}>
            <SettingField
              label={t('remote.gridWaitTime')}
              fieldKey="grid_wait_time"
              type="number"
              min={30}
              max={600}
              step={1}
              unit="s"
              reportedValue={reported.grid_wait_time}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { grid_wait_time: v })}
              tooltip={t('remote.pendingProtocol')}
            />
            <SettingField
              label={t('remote.gridReconnectWait')}
              fieldKey="grid_reconnect_wait"
              type="number"
              min={0}
              max={600}
              step={1}
              unit="s"
              reportedValue={reported.grid_reconnect_wait}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { grid_reconnect_wait: v })}
              tooltip={t('remote.pendingProtocol')}
            />
          </SettingSection>
        </Col>

        {/* ── 并网电压 ── */}
        <Col xs={24} md={12}>
          <SettingSection title={t('remote.gridVoltageUpper')} icon={<ThunderboltOutlined />}>
            <SettingField
              label={t('remote.gridVoltageUpper')}
              fieldKey="grid_v_upper"
              type="number"
              min={0}
              max={300}
              step={1}
              unit="V"
              reportedValue={reported.grid_v_upper}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { grid_v_upper: v })}
              tooltip={t('remote.pendingProtocol')}
            />
            <SettingField
              label={t('remote.gridVoltageLower')}
              fieldKey="grid_v_lower"
              type="number"
              min={0}
              max={300}
              step={1}
              unit="V"
              reportedValue={reported.grid_v_lower}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { grid_v_lower: v })}
              tooltip={t('remote.pendingProtocol')}
            />
          </SettingSection>
        </Col>

        {/* ── 并网频率 ── */}
        <Col xs={24} md={12}>
          <SettingSection title={t('remote.gridFreqUpper')} icon={<DashboardOutlined />}>
            <SettingField
              label={t('remote.gridFreqUpper')}
              fieldKey="grid_f_upper"
              type="number"
              min={0}
              max={70}
              step={0.1}
              unit="Hz"
              reportedValue={reported.grid_f_upper}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { grid_f_upper: v })}
              tooltip={t('remote.pendingProtocol')}
            />
            <SettingField
              label={t('remote.gridFreqLower')}
              fieldKey="grid_f_lower"
              type="number"
              min={0}
              max={70}
              step={0.1}
              unit="Hz"
              reportedValue={reported.grid_f_lower}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { grid_f_lower: v })}
              tooltip={t('remote.pendingProtocol')}
            />
          </SettingSection>
        </Col>
      </Row>
    </Spin>
  )
}

export default GridSettingsTab
