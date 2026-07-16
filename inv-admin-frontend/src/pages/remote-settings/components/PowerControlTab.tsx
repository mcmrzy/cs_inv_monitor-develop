import React from 'react'
import { Row, Col, Spin } from 'antd'
import { ThunderboltOutlined, SafetyCertificateOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { useControlState } from '../hooks/useControlState'
import SettingField from './SettingField'
import SettingSection from './SettingSection'

interface PowerControlTabProps {
  sn: string
}

const PowerControlTab: React.FC<PowerControlTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { reported, isOnline, isLoading, error, refetch, sendCommand, isSending } = useControlState(sn)

  const pendingTip = t('remote.pendingProtocol')

  const onParam = (fieldKey: string) => (v: any) =>
    sendCommand('set_params', { [fieldKey]: v })

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
        {/* ── 分组1: 功率调节 ── */}
        <Col xs={24} md={12}>
          <SettingSection title="功率调节" icon={<ThunderboltOutlined />}>
            <SettingField
              label="过频降载使能"
              fieldKey="over_freq_derating"
              type="switch"
              disabled={!isOnline}
              onSend={onParam('over_freq_derating')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="无功输出模式"
              fieldKey="reactive_mode"
              type="select"
              options={[
                { label: '恒功率因数', value: '恒功率因数' },
                { label: '恒无功功率', value: '恒无功功率' },
                { label: 'Q(U)特性', value: 'Q(U)特性' },
              ]}
              disabled={!isOnline}
              onSend={onParam('reactive_mode')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="无功百分比设定值"
              fieldKey="reactive_pct"
              type="number"
              min={0}
              max={60}
              unit="%"
              disabled={!isOnline}
              onSend={onParam('reactive_pct')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="PF设定值"
              fieldKey="pf_value"
              type="number"
              min={750}
              max={2000}
              step={1}
              disabled={!isOnline}
              onSend={onParam('pf_value')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="有功百分比设定值"
              fieldKey="active_power_pct"
              type="number"
              min={0}
              max={100}
              unit="%"
              disabled={!isOnline}
              onSend={onParam('active_power_pct')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="电网软启动"
              fieldKey="grid_soft_start"
              type="switch"
              disabled={!isOnline}
              onSend={onParam('grid_soft_start')}
              tooltip={pendingTip}
              pending={isSending}
            />
          </SettingSection>
        </Col>

        {/* ── 分组2: 电网保护等级 ── */}
        <Col xs={24} md={12}>
          <SettingSection title="电网保护等级" icon={<SafetyCertificateOutlined />}>
            <SettingField
              label="市电保护等级"
              fieldKey="grid_protection_level"
              type="select"
              options={[
                { label: '等级1', value: '等级1' },
                { label: '等级2', value: '等级2' },
                { label: '等级3', value: '等级3' },
              ]}
              disabled={!isOnline}
              onSend={onParam('grid_protection_level')}
              tooltip={pendingTip}
              pending={isSending}
            />
          </SettingSection>
        </Col>

        {/* ── 分组3: 1级保护点 ── */}
        <Col xs={24} md={12}>
          <SettingSection title="1级保护点" icon={<SafetyCertificateOutlined />}>
            <SettingField
              label="电网电压1级欠压保护点"
              fieldKey="grid_v_l1_under"
              type="number"
              unit="V"
              disabled={!isOnline}
              onSend={onParam('grid_v_l1_under')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="电网电压1级过压保护点"
              fieldKey="grid_v_l1_over"
              type="number"
              unit="V"
              disabled={!isOnline}
              onSend={onParam('grid_v_l1_over')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="电网频率1级欠频保护点"
              fieldKey="grid_f_l1_under"
              type="number"
              unit="Hz"
              step={0.1}
              disabled={!isOnline}
              onSend={onParam('grid_f_l1_under')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="电网频率1级过频保护点"
              fieldKey="grid_f_l1_over"
              type="number"
              unit="Hz"
              step={0.1}
              disabled={!isOnline}
              onSend={onParam('grid_f_l1_over')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="电网电压滑动平均过压保护点"
              fieldKey="grid_v_slide_avg_over"
              type="number"
              unit="V"
              disabled={!isOnline}
              onSend={onParam('grid_v_slide_avg_over')}
              tooltip={pendingTip}
              pending={isSending}
            />
          </SettingSection>
        </Col>

        {/* ── 分组4: 2级保护点 ── */}
        <Col xs={24} md={12}>
          <SettingSection title="2级保护点" icon={<SafetyCertificateOutlined />}>
            <SettingField
              label="电网电压2级欠压保护点"
              fieldKey="grid_v_l2_under"
              type="number"
              unit="V"
              disabled={!isOnline}
              onSend={onParam('grid_v_l2_under')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="电网电压2级过压保护点"
              fieldKey="grid_v_l2_over"
              type="number"
              unit="V"
              disabled={!isOnline}
              onSend={onParam('grid_v_l2_over')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="电网频率2级欠频保护点"
              fieldKey="grid_f_l2_under"
              type="number"
              unit="Hz"
              step={0.1}
              disabled={!isOnline}
              onSend={onParam('grid_f_l2_under')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="电网频率2级过频保护点"
              fieldKey="grid_f_l2_over"
              type="number"
              unit="Hz"
              step={0.1}
              disabled={!isOnline}
              onSend={onParam('grid_f_l2_over')}
              tooltip={pendingTip}
              pending={isSending}
            />
          </SettingSection>
        </Col>

        {/* ── 分组5: 3级保护点 ── */}
        <Col xs={24} md={12}>
          <SettingSection title="3级保护点" icon={<SafetyCertificateOutlined />}>
            <SettingField
              label="电网电压3级欠压保护点"
              fieldKey="grid_v_l3_under"
              type="number"
              unit="V"
              disabled={!isOnline}
              onSend={onParam('grid_v_l3_under')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="电网电压3级过压保护点"
              fieldKey="grid_v_l3_over"
              type="number"
              unit="V"
              disabled={!isOnline}
              onSend={onParam('grid_v_l3_over')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="电网频率3级欠频保护点"
              fieldKey="grid_f_l3_under"
              type="number"
              unit="Hz"
              step={0.1}
              disabled={!isOnline}
              onSend={onParam('grid_f_l3_under')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="电网频率3级过频保护点"
              fieldKey="grid_f_l3_over"
              type="number"
              unit="Hz"
              step={0.1}
              disabled={!isOnline}
              onSend={onParam('grid_f_l3_over')}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="加载速率"
              fieldKey="ramp_rate"
              type="number"
              min={1}
              max={100}
              unit="%/min"
              disabled={!isOnline}
              onSend={onParam('ramp_rate')}
              tooltip={pendingTip}
              pending={isSending}
            />
          </SettingSection>
        </Col>
      </Row>
    </Spin>
  )
}

export default PowerControlTab
