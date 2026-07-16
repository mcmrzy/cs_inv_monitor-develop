import React from 'react'
import { Row, Col, Spin } from 'antd'
import { ArrowUpOutlined, ThunderboltOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { useControlState } from '../hooks/useControlState'
import SettingField from './SettingField'
import SettingSection from './SettingSection'

interface ChargeSettingsTabProps {
  sn: string
}

const ChargeSettingsTab: React.FC<ChargeSettingsTabProps> = ({ sn }) => {
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
        {/* ── 分组1: BMS 充电设置（已有命令） ── */}
        <Col xs={24} md={12}>
          <SettingSection title="BMS 充电设置" icon={<ArrowUpOutlined />}>
            <SettingField
              label="BMS充电使能"
              fieldKey="bms_charge_enable"
              type="switch"
              reportedValue={reported.bms_charge_enable}
              disabled={!isOnline}
              onSend={(v) =>
                sendCommand('bms_set_enable', {
                  charge: v,
                  discharge: reported.bms_discharge_enable ?? true,
                })
              }
              pending={isSending}
            />
            <SettingField
              label="充电电流限制"
              fieldKey="bms_charge_current"
              type="number"
              min={0}
              max={110}
              step={0.1}
              unit="A"
              reportedValue={Number(reported.bms_charge_current_x10) / 10}
              disabled={!isOnline}
              onSend={(v) =>
                sendCommand('bms_set_charge_current', { amp_x10: Math.round(v * 10) })
              }
              pending={isSending}
            />
            <SettingField
              label="BMS充电电压"
              fieldKey="bms_charge_voltage"
              type="number"
              min={54.4}
              max={58.4}
              step={0.1}
              unit="V"
              reportedValue={Number(reported.bms_charge_voltage_x10) / 10}
              disabled={!isOnline}
              onSend={(v) =>
                sendCommand('bms_set_charge_voltage', { volt_x10: Math.round(v * 10) })
              }
              pending={isSending}
            />
            <SettingField
              label="充电功率限制"
              fieldKey="charge_limit_w"
              type="number"
              min={0}
              max={6200}
              step={100}
              unit="W"
              reportedValue={reported.charge_limit_w}
              disabled={!isOnline}
              onSend={(v) => sendCommand('set_charge_limit', { watts: v })}
              pending={isSending}
            />
          </SettingSection>
        </Col>

        {/* ── 分组2: 强制充电（已有命令） ── */}
        <Col xs={24} md={12}>
          <SettingSection title="强制充电" icon={<ArrowUpOutlined />}>
            <SettingField
              label="强制充电"
              fieldKey="force_charge"
              type="switch"
              reportedValue={reported.force_charge}
              disabled={!isOnline}
              onSend={(v) => sendCommand('force_charge', { enabled: v })}
              pending={isSending}
            />
            <SettingField
              label="强制充电超时"
              fieldKey="force_charge_timeout"
              type="number"
              min={5}
              max={120}
              step={5}
              unit="min"
              reportedValue={reported.force_charge_timeout}
              disabled={!isOnline}
              onSend={() =>
                sendCommand('force_charge', {
                  enabled: reported.force_charge ?? false,
                })
              }
              pending={isSending}
            />
          </SettingSection>
        </Col>

        {/* ── 分组3: 铅酸充电参数（待协议） ── */}
        <Col xs={24} md={12}>
          <SettingSection title="铅酸充电参数" icon={<ThunderboltOutlined />}>
            <SettingField
              label="充电电压(铅酸)"
              fieldKey="lead_charge_v"
              type="number"
              min={50}
              max={58}
              step={0.1}
              unit="V"
              onSend={onParam('lead_charge_v')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="浮动电压"
              fieldKey="float_v"
              type="number"
              min={50}
              max={58}
              step={0.1}
              unit="V"
              onSend={onParam('float_v')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="均衡电压"
              fieldKey="equalize_v"
              type="number"
              min={50}
              max={59}
              step={0.1}
              unit="V"
              onSend={onParam('equalize_v')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="均衡周期"
              fieldKey="equalize_cycle"
              type="number"
              min={0}
              max={365}
              step={1}
              unit="天"
              onSend={onParam('equalize_cycle')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="均衡时间"
              fieldKey="equalize_time"
              type="number"
              min={0}
              max={24}
              step={0.1}
              unit="小时"
              onSend={onParam('equalize_time')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
          </SettingSection>
        </Col>

        {/* ── 分组4: 交流充电（待协议） ── */}
        <Col xs={24} md={12}>
          <SettingSection title="交流充电" icon={<ThunderboltOutlined />}>
            <SettingField
              label="AC充电控制依据"
              fieldKey="ac_charge_control"
              type="select"
              options={[
                { label: '电池电压', value: '电池电压' },
                { label: 'SOC', value: 'SOC' },
                { label: '电压+SOC', value: '电压+SOC' },
              ]}
              onSend={onParam('ac_charge_control')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="交流充电电池电流"
              fieldKey="ac_charge_current"
              type="number"
              min={0}
              max={150}
              step={0.1}
              unit="A"
              onSend={onParam('ac_charge_current')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="AC充电起始时间1"
              fieldKey="ac_charge_start_1"
              type="time-range"
              onSend={onParam('ac_charge_start_1')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="AC充电结束时间1"
              fieldKey="ac_charge_end_1"
              type="time-range"
              onSend={onParam('ac_charge_end_1')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="AC充电起始时间2"
              fieldKey="ac_charge_start_2"
              type="time-range"
              onSend={onParam('ac_charge_start_2')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="AC充电结束时间2"
              fieldKey="ac_charge_end_2"
              type="time-range"
              onSend={onParam('ac_charge_end_2')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="AC充电起始时间3"
              fieldKey="ac_charge_start_3"
              type="time-range"
              onSend={onParam('ac_charge_start_3')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="AC充电结束时间3"
              fieldKey="ac_charge_end_3"
              type="time-range"
              onSend={onParam('ac_charge_end_3')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="交流充电开始电池电压"
              fieldKey="ac_charge_start_v"
              type="number"
              min={38.4}
              max={52}
              step={0.1}
              unit="V"
              onSend={onParam('ac_charge_start_v')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="交流充电结束电池电压"
              fieldKey="ac_charge_end_v"
              type="number"
              min={48}
              max={59}
              step={0.1}
              unit="V"
              onSend={onParam('ac_charge_end_v')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="交流充电开始电池SOC"
              fieldKey="ac_charge_start_soc"
              type="number"
              min={0}
              max={90}
              step={1}
              unit="%"
              onSend={onParam('ac_charge_start_soc')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="交流充电结束电池SOC"
              fieldKey="ac_charge_end_soc"
              type="number"
              min={20}
              max={100}
              step={1}
              unit="%"
              onSend={onParam('ac_charge_end_soc')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
          </SettingSection>
        </Col>

        {/* ── 分组5: 发电机充电（待协议） ── */}
        <Col xs={24} md={12}>
          <SettingSection title="发电机充电" icon={<ThunderboltOutlined />}>
            <SettingField
              label="发电机充电类型"
              fieldKey="gen_charge_type"
              type="select"
              options={[
                { label: '手动', value: '手动' },
                { label: '自动', value: '自动' },
              ]}
              onSend={onParam('gen_charge_type')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="发电机充电电池电流"
              fieldKey="gen_charge_current"
              type="number"
              min={0}
              max={110}
              step={0.1}
              unit="A"
              onSend={onParam('gen_charge_current')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="发电机充电开始电池电压"
              fieldKey="gen_charge_start_v"
              type="number"
              min={38.4}
              max={52}
              step={0.1}
              unit="V"
              onSend={onParam('gen_charge_start_v')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="发电机充电结束电池电压"
              fieldKey="gen_charge_end_v"
              type="number"
              min={48}
              max={59}
              step={0.1}
              unit="V"
              onSend={onParam('gen_charge_end_v')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="发电机充电开始电池SOC"
              fieldKey="gen_charge_start_soc"
              type="number"
              min={0}
              max={90}
              step={1}
              unit="%"
              onSend={onParam('gen_charge_start_soc')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="发电机充电结束电池SOC"
              fieldKey="gen_charge_end_soc"
              type="number"
              min={20}
              max={100}
              step={1}
              unit="%"
              onSend={onParam('gen_charge_end_soc')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="发电机额定功率"
              fieldKey="gen_rated_power"
              type="number"
              min={0}
              max={7370}
              step={10}
              unit="W"
              onSend={onParam('gen_rated_power')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
          </SettingSection>
        </Col>
      </Row>
    </Spin>
  )
}

export default ChargeSettingsTab
