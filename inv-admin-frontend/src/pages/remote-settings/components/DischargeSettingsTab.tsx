import React, { useState, useEffect } from 'react'
import { Row, Col, Spin, InputNumber, Button, Space, Typography, App } from 'antd'
import { ArrowDownOutlined, ThunderboltOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { useControlState } from '../hooks/useControlState'
import SettingField from './SettingField'
import SettingSection from './SettingSection'

const { Text } = Typography

interface DischargeSettingsTabProps {
  sn: string
}

const PRIMARY = '#4f6ef7'

const DischargeSettingsTab: React.FC<DischargeSettingsTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { reported, isOnline, isLoading, error, refetch, sendCommand, isSending } = useControlState(sn)
  const { message } = App.useApp()

  const pendingTip = t('remote.pendingProtocol')

  // ── SOC 窗口本地状态（关联字段） ──
  const [socLow, setSocLow] = useState(20)
  const [socHigh, setSocHigh] = useState(90)

  useEffect(() => {
    if (reported.soc_low_x10 !== undefined) setSocLow(Number(reported.soc_low_x10) / 10)
    if (reported.soc_high_x10 !== undefined) setSocHigh(Number(reported.soc_high_x10) / 10)
  }, [reported])

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
        {/* ── 分组1: BMS 放电设置（已有命令） ── */}
        <Col xs={24} md={12}>
          <SettingSection title="BMS 放电设置" icon={<ArrowDownOutlined />}>
            <SettingField
              label="BMS放电使能"
              fieldKey="bms_discharge_enable"
              type="switch"
              reportedValue={reported.bms_discharge_enable}
              disabled={!isOnline}
              onSend={(v) =>
                sendCommand('bms_set_enable', {
                  charge: reported.bms_charge_enable ?? true,
                  discharge: v,
                })
              }
              pending={isSending}
            />
            <SettingField
              label="放电电流限制"
              fieldKey="bms_discharge_current"
              type="number"
              min={0}
              max={120}
              step={0.1}
              unit="A"
              reportedValue={Number(reported.bms_discharge_current_x10) / 10}
              disabled={!isOnline}
              onSend={(v) =>
                sendCommand('bms_set_discharge_current', { amp_x10: Math.round(v * 10) })
              }
              pending={isSending}
            />
            <SettingField
              label="BMS放电电压"
              fieldKey="bms_discharge_voltage"
              type="number"
              min={40}
              max={48}
              step={0.1}
              unit="V"
              reportedValue={Number(reported.bms_discharge_voltage_x10) / 10}
              disabled={!isOnline}
              onSend={(v) =>
                sendCommand('bms_set_discharge_voltage', { volt_x10: Math.round(v * 10) })
              }
              pending={isSending}
            />
            <SettingField
              label="放电功率限制"
              fieldKey="discharge_limit_w"
              type="number"
              min={0}
              max={6200}
              step={100}
              unit="W"
              reportedValue={reported.discharge_limit_w}
              disabled={!isOnline}
              onSend={(v) => sendCommand('set_discharge_limit', { watts: v })}
              pending={isSending}
            />
          </SettingSection>
        </Col>

        {/* ── 分组2: 强制放电（已有命令） ── */}
        <Col xs={24} md={12}>
          <SettingSection title="强制放电" icon={<ArrowDownOutlined />}>
            <SettingField
              label="强制放电"
              fieldKey="force_discharge"
              type="switch"
              reportedValue={reported.force_discharge}
              disabled={!isOnline}
              onSend={(v) => sendCommand('force_discharge', { enabled: v })}
              pending={isSending}
            />
            <SettingField
              label="强制放电超时"
              fieldKey="force_discharge_timeout"
              type="number"
              min={5}
              max={120}
              step={5}
              unit="min"
              reportedValue={reported.force_discharge_timeout}
              disabled={!isOnline}
              onSend={() =>
                sendCommand('force_discharge', {
                  enabled: reported.force_discharge ?? false,
                })
              }
              pending={isSending}
            />
          </SettingSection>
        </Col>

        {/* ── 分组3: SOC 窗口（已有命令，关联字段） ── */}
        <Col xs={24} md={12}>
          <SettingSection title="SOC 窗口" icon={<ThunderboltOutlined />}>
            <div style={{ marginBottom: 12 }}>
              <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                SOC下限
                {reported.soc_low_x10 !== undefined && (
                  <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                    当前: {String(Number(reported.soc_low_x10) / 10)}%
                  </Text>
                )}
              </Text>
              <InputNumber
                min={10}
                max={50}
                step={5}
                addonAfter="%"
                value={socLow}
                onChange={(v) => setSocLow(v ?? 10)}
                style={{ width: 180 }}
                disabled={!isOnline}
              />
            </div>
            <div style={{ marginBottom: 12 }}>
              <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                SOC上限
                {reported.soc_high_x10 !== undefined && (
                  <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                    当前: {String(Number(reported.soc_high_x10) / 10)}%
                  </Text>
                )}
              </Text>
              <InputNumber
                min={50}
                max={100}
                step={5}
                addonAfter="%"
                value={socHigh}
                onChange={(v) => setSocHigh(v ?? 90)}
                style={{ width: 180 }}
                disabled={!isOnline}
              />
            </div>
            <Space>
              <Button
                type="primary"
                size="small"
                loading={isSending}
                disabled={!isOnline}
                onClick={() => {
                  const lowX10 = Math.round(socLow * 10)
                  const highX10 = Math.round(socHigh * 10)
                  if (lowX10 >= highX10) {
                    message.error('SOC下限必须小于上限')
                    return
                  }
                  if (highX10 - lowX10 < 50) {
                    message.error('SOC窗口差值不能小于5%')
                    return
                  }
                  sendCommand('set_soc_window', { low_x10: lowX10, high_x10: highX10 })
                }}
                style={{ background: PRIMARY, borderColor: PRIMARY }}
              >
                下发
              </Button>
            </Space>
          </SettingSection>
        </Col>

        {/* ── 分组4: 放电保护参数（待协议） ── */}
        <Col xs={24} md={12}>
          <SettingSection title="放电保护参数" icon={<ThunderboltOutlined />}>
            <SettingField
              label="电池警告电压"
              fieldKey="battery_warn_v"
              type="number"
              min={40}
              max={50}
              step={0.1}
              unit="V"
              onSend={onParam('battery_warn_v')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="电池警告SOC"
              fieldKey="battery_warn_soc"
              type="number"
              min={0}
              max={90}
              step={1}
              unit="%"
              onSend={onParam('battery_warn_soc')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="铅酸电池放电截止电压"
              fieldKey="lead_acid_cutoff_v"
              type="number"
              min={40}
              max={50}
              step={0.1}
              unit="V"
              onSend={onParam('lead_acid_cutoff_v')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="放电截止SOC"
              fieldKey="cutoff_soc"
              type="number"
              min={0}
              max={90}
              step={1}
              unit="%"
              onSend={onParam('cutoff_soc')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="并网EOD电压"
              fieldKey="grid_eod_v"
              type="number"
              min={40}
              max={50}
              step={0.1}
              unit="V"
              onSend={onParam('grid_eod_v')}
              disabled={!isOnline}
              tooltip={pendingTip}
              pending={isSending}
            />
            <SettingField
              label="并网截止SOC"
              fieldKey="grid_cutoff_soc"
              type="number"
              min={0}
              max={90}
              step={1}
              unit="%"
              onSend={onParam('grid_cutoff_soc')}
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

export default DischargeSettingsTab
