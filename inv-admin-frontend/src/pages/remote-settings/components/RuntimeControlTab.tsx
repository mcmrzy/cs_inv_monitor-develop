import React, { useState, useEffect } from 'react'
import {
  Card, Switch, InputNumber, Button, Row, Col, Space, Spin, Typography, App,
} from 'antd'
import {
  PoweroffOutlined, ThunderboltOutlined, ArrowUpOutlined, ArrowDownOutlined,
} from '@ant-design/icons'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'

const { Text } = Typography

interface RuntimeControlTabProps {
  sn: string
}

const PRIMARY = '#4f6ef7'
const cardStyle = { borderRadius: 12 }

const RuntimeControlTab: React.FC<RuntimeControlTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const queryClient = useQueryClient()

  // ── Local state ──
  const [acEnabled, setAcEnabled] = useState(true)
  const [powerLimit, setPowerLimit] = useState<number>(3000)
  const [forceCharge, setForceCharge] = useState(false)
  const [forceChargeTimeout, setForceChargeTimeout] = useState<number>(30)
  const [forceDischarge, setForceDischarge] = useState(false)
  const [forceDischargeTimeout, setForceDischargeTimeout] = useState<number>(30)

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

  // Sync local state from reported
  useEffect(() => {
    if (!reported || Object.keys(reported).length === 0) return
    if (reported.ac_enabled !== undefined) setAcEnabled(Boolean(reported.ac_enabled))
    if (reported.power_limit_w !== undefined) setPowerLimit(Number(reported.power_limit_w))
    if (reported.force_charge !== undefined) setForceCharge(Boolean(reported.force_charge))
    if (reported.force_charge_timeout !== undefined) setForceChargeTimeout(Number(reported.force_charge_timeout))
    if (reported.force_discharge !== undefined) setForceDischarge(Boolean(reported.force_discharge))
    if (reported.force_discharge_timeout !== undefined) setForceDischargeTimeout(Number(reported.force_discharge_timeout))
  }, [reported])

  const isOnline = (controlState as any)?.sync_status !== 'unknown'

  // ── Query: capabilities (optional enrichment) ──
  useQuery({
    queryKey: queryKeys.devices.controlCapabilities(sn),
    queryFn: () => deviceApi.getControlCapabilities(sn).then((r) => (r as any).data?.data ?? (r as any).data),
    staleTime: 120_000,
  })

  // ── Command mutation ──
  const commandMutation = useMutation({
    mutationFn: (payload: { command_code: string; params?: Record<string, unknown> }) =>
      deviceApi.sendCommand(sn, payload).then((r: any) => {
        const d = r.data?.data ?? r.data
        if (d && d.success === false) throw new Error(d.message ?? t('common.failed'))
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
        {/* ── AC 开关 ── */}
        <Col xs={24} md={12}>
          <Card
            title={<Space><PoweroffOutlined />AC 开关</Space>}
            bordered={false}
            style={cardStyle}
          >
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  交流输出
                  {reported.ac_enabled !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {reported.ac_enabled ? '开启' : '关闭'}
                    </Text>
                  )}
                </Text>
                <Switch
                  checked={acEnabled}
                  onChange={(v) => {
                    setAcEnabled(v)
                    send(v ? 'ac_on' : 'ac_off')
                  }}
                  disabled={!isOnline}
                  loading={sending}
                />
              </div>
            </Space>
          </Card>
        </Col>

        {/* ── 功率限制 ── */}
        <Col xs={24} md={12}>
          <Card
            title={<Space><ThunderboltOutlined />功率限制</Space>}
            bordered={false}
            style={cardStyle}
          >
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  功率上限
                  {reported.power_limit_w !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {String(reported.power_limit_w)}W
                    </Text>
                  )}
                </Text>
                <InputNumber
                  min={0} max={6200} step={100}
                  addonAfter="W"
                  value={powerLimit}
                  onChange={(v) => setPowerLimit(v ?? 0)}
                  disabled={!isOnline}
                  style={{ width: '100%' }}
                />
              </div>
              <Button
                type="primary"
                loading={sending}
                disabled={!isOnline}
                onClick={() => send('set_power_limit', { watts: powerLimit })}
                style={{ background: PRIMARY, borderColor: PRIMARY }}
              >
                下发
              </Button>
            </Space>
          </Card>
        </Col>

        {/* ── 强制充电 ── */}
        <Col xs={24} md={12}>
          <Card
            title={<Space><ArrowUpOutlined />强制充电</Space>}
            bordered={false}
            style={cardStyle}
          >
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  启用
                  {reported.force_charge !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {reported.force_charge ? '开启' : '关闭'}
                    </Text>
                  )}
                </Text>
                <Switch
                  checked={forceCharge}
                  onChange={setForceCharge}
                  disabled={!isOnline}
                  loading={sending}
                />
              </div>
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  超时时间
                  {reported.force_charge_timeout !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {String(reported.force_charge_timeout)}min
                    </Text>
                  )}
                </Text>
                <InputNumber
                  min={5} max={120} step={5}
                  addonAfter="min"
                  value={forceChargeTimeout}
                  onChange={(v) => setForceChargeTimeout(v ?? 30)}
                  disabled={!isOnline}
                  style={{ width: '100%' }}
                />
              </div>
              <Button
                type="primary"
                loading={sending}
                disabled={!isOnline}
                onClick={() => send('force_charge', {
                  enabled: forceCharge,
                  timeout: forceChargeTimeout,
                })}
                style={{ background: PRIMARY, borderColor: PRIMARY }}
              >
                下发
              </Button>
            </Space>
          </Card>
        </Col>

        {/* ── 强制放电 ── */}
        <Col xs={24} md={12}>
          <Card
            title={<Space><ArrowDownOutlined />强制放电</Space>}
            bordered={false}
            style={cardStyle}
          >
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  启用
                  {reported.force_discharge !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {reported.force_discharge ? '开启' : '关闭'}
                    </Text>
                  )}
                </Text>
                <Switch
                  checked={forceDischarge}
                  onChange={setForceDischarge}
                  disabled={!isOnline}
                  loading={sending}
                />
              </div>
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  超时时间
                  {reported.force_discharge_timeout !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {String(reported.force_discharge_timeout)}min
                    </Text>
                  )}
                </Text>
                <InputNumber
                  min={5} max={120} step={5}
                  addonAfter="min"
                  value={forceDischargeTimeout}
                  onChange={(v) => setForceDischargeTimeout(v ?? 30)}
                  disabled={!isOnline}
                  style={{ width: '100%' }}
                />
              </div>
              <Button
                type="primary"
                loading={sending}
                disabled={!isOnline}
                onClick={() => send('force_discharge', {
                  enabled: forceDischarge,
                  timeout: forceDischargeTimeout,
                })}
                style={{ background: PRIMARY, borderColor: PRIMARY }}
              >
                下发
              </Button>
            </Space>
          </Card>
        </Col>
      </Row>
    </Spin>
  )
}

export default RuntimeControlTab
