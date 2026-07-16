import React, { useState, useEffect } from 'react'
import {
  Card, InputNumber, Switch, Button, Row, Col, Space, Spin, Typography, App, Divider,
} from 'antd'
import {
  ThunderboltOutlined, ArrowUpOutlined, ArrowDownOutlined, SettingOutlined,
} from '@ant-design/icons'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'

const { Text } = Typography

interface BatteryTabProps {
  sn: string
}

const PRIMARY = '#4f6ef7'

const cardStyle = { borderRadius: 12 }

const BatteryTab: React.FC<BatteryTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const queryClient = useQueryClient()

  // ── Local input state ──
  const [socLow, setSocLow] = useState<number>(20)
  const [socHigh, setSocHigh] = useState<number>(90)
  const [chargeLimitW, setChargeLimitW] = useState<number>(3000)
  const [dischargeLimitW, setDischargeLimitW] = useState<number>(3000)
  const [bmsChargeEnable, setBmsChargeEnable] = useState(true)
  const [bmsDischargeEnable, setBmsDischargeEnable] = useState(true)
  const [bmsChargeCurrent, setBmsChargeCurrent] = useState<number>(25)
  const [bmsDischargeCurrent, setBmsDischargeCurrent] = useState<number>(50)
  const [bmsChargeVoltage, setBmsChargeVoltage] = useState<number>(56.4)
  const [bmsDischargeVoltage, setBmsDischargeVoltage] = useState<number>(44.0)

  // ── Query: control state ──
  const {
    data: controlState,
    isLoading,
    error,
    refetch,
  } = useQuery({
    queryKey: queryKeys.devices.controlState(sn),
    queryFn: () => deviceApi.getControlState(sn).then((r) => (r as any).data?.data ?? null),
    refetchInterval: 15000,
  })

  const reported = (controlState as any)?.reported ?? {}

  // Sync local state when reported values change
  useEffect(() => {
    if (!reported || Object.keys(reported).length === 0) return
    if (reported.soc_low_x10 !== undefined) setSocLow(Number(reported.soc_low_x10) / 10)
    if (reported.soc_high_x10 !== undefined) setSocHigh(Number(reported.soc_high_x10) / 10)
    if (reported.charge_limit_w !== undefined) setChargeLimitW(Number(reported.charge_limit_w))
    if (reported.discharge_limit_w !== undefined) setDischargeLimitW(Number(reported.discharge_limit_w))
    if (reported.bms_charge_enable !== undefined) setBmsChargeEnable(Boolean(reported.bms_charge_enable))
    if (reported.bms_discharge_enable !== undefined) setBmsDischargeEnable(Boolean(reported.bms_discharge_enable))
    if (reported.bms_charge_current_x10 !== undefined) setBmsChargeCurrent(Number(reported.bms_charge_current_x10) / 10)
    if (reported.bms_discharge_current_x10 !== undefined) setBmsDischargeCurrent(Number(reported.bms_discharge_current_x10) / 10)
    if (reported.bms_charge_voltage_x10 !== undefined) setBmsChargeVoltage(Number(reported.bms_charge_voltage_x10) / 10)
    if (reported.bms_discharge_voltage_x10 !== undefined) setBmsDischargeVoltage(Number(reported.bms_discharge_voltage_x10) / 10)
  }, [reported])

  // Device is considered online unless sync_status is 'unknown'
  const isOnline = (controlState as any)?.sync_status !== 'unknown'

  // ── Command mutation ──
  const commandMutation = useMutation({
    mutationFn: (payload: { command_code: string; params?: Record<string, unknown> }) =>
      deviceApi.sendCommand(sn, payload).then((r: any) => {
        const d = r.data?.data ?? r.data
        if (d && d.success === false) {
          throw new Error(d.message ?? t('common.failed'))
        }
        return d
      }),
    onSuccess: () => {
      message.success(t('common.success'))
      void queryClient.invalidateQueries({ queryKey: queryKeys.devices.controlState(sn) })
      void queryClient.invalidateQueries({ queryKey: queryKeys.devices.commands(sn) })
    },
    onError: (err: Error) => {
      message.error(err.message || t('common.failed'))
    },
  })

  const send = (command_code: string, params?: Record<string, unknown>) => {
    commandMutation.mutate({ command_code, params })
  }

  // ── Command handlers ──
  const sendSocWindow = () => {
    send('set_soc_window', { low_x10: Math.round(socLow * 10), high_x10: Math.round(socHigh * 10) })
  }
  const sendChargeLimit = () => send('set_charge_limit', { w: chargeLimitW })
  const sendDischargeLimit = () => send('set_discharge_limit', { w: dischargeLimitW })
  const sendBmsEnable = (field: 'charge_enable' | 'discharge_enable', value: boolean) => {
    const params = {
      charge_enable: field === 'charge_enable' ? value : bmsChargeEnable,
      discharge_enable: field === 'discharge_enable' ? value : bmsDischargeEnable,
    }
    send('bms_set_enable', params)
  }
  const sendBmsChargeCurrent = () => send('bms_set_charge_current', { amp_x10: Math.round(bmsChargeCurrent * 10) })
  const sendBmsDischargeCurrent = () => send('bms_set_discharge_current', { amp_x10: Math.round(bmsDischargeCurrent * 10) })
  const sendBmsChargeVoltage = () => send('bms_set_charge_voltage', { volt_x10: Math.round(bmsChargeVoltage * 10) })
  const sendBmsDischargeVoltage = () => send('bms_set_discharge_voltage', { volt_x10: Math.round(bmsDischargeVoltage * 10) })

  const sending = commandMutation.isPending

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
        {/* ── SOC 窗口 ── */}
        <Col xs={24} md={12}>
          <Card
            title={<Space><ThunderboltOutlined />SOC 窗口</Space>}
            bordered={false}
            style={cardStyle}
          >
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  下限
                  {reported.soc_low_x10 !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {Number(reported.soc_low_x10) / 10}%
                    </Text>
                  )}
                </Text>
                <InputNumber
                  min={10} max={50} step={5}
                  addonAfter="%"
                  value={socLow}
                  onChange={(v) => setSocLow(v ?? 10)}
                  disabled={!isOnline}
                  style={{ width: '100%' }}
                />
              </div>
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  上限
                  {reported.soc_high_x10 !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {Number(reported.soc_high_x10) / 10}%
                    </Text>
                  )}
                </Text>
                <InputNumber
                  min={50} max={100} step={5}
                  addonAfter="%"
                  value={socHigh}
                  onChange={(v) => setSocHigh(v ?? 90)}
                  disabled={!isOnline}
                  style={{ width: '100%' }}
                />
              </div>
              <Button
                type="primary"
                loading={sending}
                disabled={!isOnline}
                onClick={sendSocWindow}
                style={{ background: PRIMARY, borderColor: PRIMARY }}
              >
                下发
              </Button>
            </Space>
          </Card>
        </Col>

        {/* ── 充电功率限制 ── */}
        <Col xs={24} md={12}>
          <Card
            title={<Space><ArrowUpOutlined />充电功率限制</Space>}
            bordered={false}
            style={cardStyle}
          >
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  功率上限
                  {reported.charge_limit_w !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {String(reported.charge_limit_w)}W
                    </Text>
                  )}
                </Text>
                <InputNumber
                  min={0} max={6200} step={100}
                  addonAfter="W"
                  value={chargeLimitW}
                  onChange={(v) => setChargeLimitW(v ?? 0)}
                  disabled={!isOnline}
                  style={{ width: '100%' }}
                />
              </div>
              <Button
                type="primary"
                loading={sending}
                disabled={!isOnline}
                onClick={sendChargeLimit}
                style={{ background: PRIMARY, borderColor: PRIMARY }}
              >
                下发
              </Button>
            </Space>
          </Card>
        </Col>

        {/* ── 放电功率限制 ── */}
        <Col xs={24} md={12}>
          <Card
            title={<Space><ArrowDownOutlined />放电功率限制</Space>}
            bordered={false}
            style={cardStyle}
          >
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  功率上限
                  {reported.discharge_limit_w !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {String(reported.discharge_limit_w)}W
                    </Text>
                  )}
                </Text>
                <InputNumber
                  min={0} max={6200} step={100}
                  addonAfter="W"
                  value={dischargeLimitW}
                  onChange={(v) => setDischargeLimitW(v ?? 0)}
                  disabled={!isOnline}
                  style={{ width: '100%' }}
                />
              </div>
              <Button
                type="primary"
                loading={sending}
                disabled={!isOnline}
                onClick={sendDischargeLimit}
                style={{ background: PRIMARY, borderColor: PRIMARY }}
              >
                下发
              </Button>
            </Space>
          </Card>
        </Col>

        {/* ── BMS 设置 ── */}
        <Col xs={24} md={12}>
          <Card
            title={<Space><SettingOutlined />BMS 设置</Space>}
            bordered={false}
            style={cardStyle}
          >
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              {/* 使能开关 */}
              <Row gutter={16}>
                <Col span={12}>
                  <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 4 }}>充电使能</Text>
                  <Switch
                    checked={bmsChargeEnable}
                    onChange={(v) => {
                      setBmsChargeEnable(v)
                      sendBmsEnable('charge_enable', v)
                    }}
                    disabled={!isOnline}
                    loading={sending}
                  />
                </Col>
                <Col span={12}>
                  <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 4 }}>放电使能</Text>
                  <Switch
                    checked={bmsDischargeEnable}
                    onChange={(v) => {
                      setBmsDischargeEnable(v)
                      sendBmsEnable('discharge_enable', v)
                    }}
                    disabled={!isOnline}
                    loading={sending}
                  />
                </Col>
              </Row>

              <Divider style={{ margin: '4px 0' }} />

              {/* 充电电流 */}
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  充电电流
                  {reported.bms_charge_current_x10 !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {Number(reported.bms_charge_current_x10) / 10}A
                    </Text>
                  )}
                </Text>
                <Space>
                  <InputNumber
                    min={0} max={60} step={0.1}
                    addonAfter="A"
                    value={bmsChargeCurrent}
                    onChange={(v) => setBmsChargeCurrent(v ?? 0)}
                    disabled={!isOnline}
                    style={{ flex: 1 }}
                  />
                  <Button
                    type="primary" size="small"
                    loading={sending} disabled={!isOnline}
                    onClick={sendBmsChargeCurrent}
                    style={{ background: PRIMARY, borderColor: PRIMARY }}
                  >
                    下发
                  </Button>
                </Space>
              </div>

              {/* 放电电流 */}
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  放电电流
                  {reported.bms_discharge_current_x10 !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {Number(reported.bms_discharge_current_x10) / 10}A
                    </Text>
                  )}
                </Text>
                <Space>
                  <InputNumber
                    min={0} max={120} step={0.1}
                    addonAfter="A"
                    value={bmsDischargeCurrent}
                    onChange={(v) => setBmsDischargeCurrent(v ?? 0)}
                    disabled={!isOnline}
                    style={{ flex: 1 }}
                  />
                  <Button
                    type="primary" size="small"
                    loading={sending} disabled={!isOnline}
                    onClick={sendBmsDischargeCurrent}
                    style={{ background: PRIMARY, borderColor: PRIMARY }}
                  >
                    下发
                  </Button>
                </Space>
              </div>

              <Divider style={{ margin: '4px 0' }} />

              {/* 充电电压 */}
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  充电电压
                  {reported.bms_charge_voltage_x10 !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {Number(reported.bms_charge_voltage_x10) / 10}V
                    </Text>
                  )}
                </Text>
                <Space>
                  <InputNumber
                    min={54.4} max={58.4} step={0.1}
                    addonAfter="V"
                    value={bmsChargeVoltage}
                    onChange={(v) => setBmsChargeVoltage(v ?? 54.4)}
                    disabled={!isOnline}
                    style={{ flex: 1 }}
                  />
                  <Button
                    type="primary" size="small"
                    loading={sending} disabled={!isOnline}
                    onClick={sendBmsChargeVoltage}
                    style={{ background: PRIMARY, borderColor: PRIMARY }}
                  >
                    下发
                  </Button>
                </Space>
              </div>

              {/* 放电电压 */}
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  放电电压
                  {reported.bms_discharge_voltage_x10 !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {Number(reported.bms_discharge_voltage_x10) / 10}V
                    </Text>
                  )}
                </Text>
                <Space>
                  <InputNumber
                    min={40.0} max={48.0} step={0.1}
                    addonAfter="V"
                    value={bmsDischargeVoltage}
                    onChange={(v) => setBmsDischargeVoltage(v ?? 40.0)}
                    disabled={!isOnline}
                    style={{ flex: 1 }}
                  />
                  <Button
                    type="primary" size="small"
                    loading={sending} disabled={!isOnline}
                    onClick={sendBmsDischargeVoltage}
                    style={{ background: PRIMARY, borderColor: PRIMARY }}
                  >
                    下发
                  </Button>
                </Space>
              </div>
            </Space>
          </Card>
        </Col>
      </Row>
    </Spin>
  )
}

export default BatteryTab
