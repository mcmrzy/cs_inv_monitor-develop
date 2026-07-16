import React, { useState, useEffect } from 'react'
import {
  Card, Select, Radio, InputNumber, Button, Row, Col, Space, Spin, Typography, App, Alert, Modal,
} from 'antd'
import {
  NodeIndexOutlined, SettingOutlined, ThunderboltOutlined, ApiOutlined,
} from '@ant-design/icons'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'

const { Text } = Typography

interface ParallelTabProps {
  sn: string
}

const PRIMARY = '#4f6ef7'
const cardStyle = { borderRadius: 12 }

const ParallelTab: React.FC<ParallelTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const queryClient = useQueryClient()

  // ── Local state ──
  const [topology, setTopology] = useState<string>('standalone')
  const [role, setRole] = useState<'master' | 'slave'>('master')
  const [machineId, setMachineId] = useState<number>(1)
  const [phase, setPhase] = useState<string>('A')

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

  useEffect(() => {
    if (!reported || Object.keys(reported).length === 0) return
    if (reported.parallel_topology !== undefined) setTopology(String(reported.parallel_topology))
    if (reported.parallel_role !== undefined) setRole(reported.parallel_role === 'slave' ? 'slave' : 'master')
    if (reported.parallel_machine_id !== undefined) setMachineId(Number(reported.parallel_machine_id))
    if (reported.parallel_phase !== undefined) setPhase(String(reported.parallel_phase))
  }, [reported])

  const isOnline = (controlState as any)?.sync_status !== 'unknown'

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

  const confirmSend = (
    command_code: string,
    params: Record<string, unknown> | undefined,
    title: string,
  ) => {
    Modal.confirm({
      title: '高风险操作确认',
      content: `确定要对设备 ${sn} 执行"${title}"操作吗？此操作不可撤销。`,
      okText: '确认执行',
      okType: 'danger',
      cancelText: '取消',
      onOk: () => commandMutation.mutate({ command_code, params }),
    })
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

      <Alert
        type="warning"
        showIcon
        message="高风险操作警告"
        description="并机/三相配置涉及多设备协同，错误配置可能导致设备损坏或电网事故。请确认操作人员具备相关资质。"
        style={{ marginBottom: 16, borderRadius: 12 }}
      />

      <Row gutter={[16, 16]}>
        {/* ── 并机拓扑 ── */}
        <Col xs={24} md={12}>
          <Card
            title={<Space><NodeIndexOutlined />并机拓扑</Space>}
            bordered={false}
            style={cardStyle}
          >
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  拓扑模式
                  {reported.parallel_topology !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {String(reported.parallel_topology)}
                    </Text>
                  )}
                </Text>
                <Select
                  value={topology}
                  onChange={setTopology}
                  disabled={!isOnline}
                  style={{ width: '100%' }}
                  options={[
                    { value: 'standalone', label: '单机' },
                    { value: 'parallel', label: '并联' },
                    { value: 'three_phase', label: '三相' },
                  ]}
                />
              </div>
              <Button
                type="primary"
                loading={sending}
                disabled={!isOnline}
                onClick={() =>
                  confirmSend('parallel_set_topology', { topology }, '设置并机拓扑')
                }
                style={{ background: PRIMARY, borderColor: PRIMARY }}
              >
                下发
              </Button>
            </Space>
          </Card>
        </Col>

        {/* ── 角色与机号 ── */}
        <Col xs={24} md={12}>
          <Card
            title={<Space><SettingOutlined />角色与机号</Space>}
            bordered={false}
            style={cardStyle}
          >
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  角色
                  {reported.parallel_role !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {String(reported.parallel_role)}
                    </Text>
                  )}
                </Text>
                <Radio.Group
                  value={role}
                  onChange={(e) => setRole(e.target.value)}
                  disabled={!isOnline}
                >
                  <Radio value="master">主机</Radio>
                  <Radio value="slave">从机</Radio>
                </Radio.Group>
              </div>
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  机号
                  {reported.parallel_machine_id !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {String(reported.parallel_machine_id)}
                    </Text>
                  )}
                </Text>
                <InputNumber
                  min={1} max={16} step={1}
                  value={machineId}
                  onChange={(v) => setMachineId(v ?? 1)}
                  disabled={!isOnline}
                  style={{ width: '100%' }}
                />
              </div>
              <Button
                type="primary"
                loading={sending}
                disabled={!isOnline}
                onClick={() =>
                  confirmSend(
                    'parallel_set_role',
                    { role, machine_id: machineId },
                    '设置角色与机号',
                  )
                }
                style={{ background: PRIMARY, borderColor: PRIMARY }}
              >
                下发
              </Button>
            </Space>
          </Card>
        </Col>

        {/* ── 相位设置 ── */}
        <Col xs={24} md={12}>
          <Card
            title={<Space><ThunderboltOutlined />相位设置</Space>}
            bordered={false}
            style={cardStyle}
          >
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              <div>
                <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
                  相位
                  {reported.parallel_phase !== undefined && (
                    <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                      当前: {String(reported.parallel_phase)}
                    </Text>
                  )}
                </Text>
                <Select
                  value={phase}
                  onChange={setPhase}
                  disabled={!isOnline}
                  style={{ width: '100%' }}
                  options={[
                    { value: 'A', label: 'A相' },
                    { value: 'B', label: 'B相' },
                    { value: 'C', label: 'C相' },
                  ]}
                />
              </div>
              <Button
                type="primary"
                loading={sending}
                disabled={!isOnline}
                onClick={() =>
                  confirmSend('parallel_set_phase', { phase }, '设置相位')
                }
                style={{ background: PRIMARY, borderColor: PRIMARY }}
              >
                下发
              </Button>
            </Space>
          </Card>
        </Col>

        {/* ── 组级控制 ── */}
        <Col xs={24} md={12}>
          <Card
            title={<Space><ApiOutlined />组级控制</Space>}
            bordered={false}
            style={cardStyle}
          >
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              <Text type="secondary" style={{ fontSize: 12 }}>
                以下操作将影响整个并机组，请谨慎操作
              </Text>
              <Row gutter={[8, 8]}>
                <Col span={12}>
                  <Button
                    block
                    loading={sending}
                    disabled={!isOnline}
                    onClick={() =>
                      confirmSend('parallel_enable', undefined, '使能并联')
                    }
                  >
                    使能并联
                  </Button>
                </Col>
                <Col span={12}>
                  <Button
                    block
                    danger
                    loading={sending}
                    disabled={!isOnline}
                    onClick={() =>
                      confirmSend('parallel_disable', undefined, '禁用并联')
                    }
                  >
                    禁用并联
                  </Button>
                </Col>
                <Col span={12}>
                  <Button
                    block
                    loading={sending}
                    disabled={!isOnline}
                    onClick={() =>
                      confirmSend('parallel_sync_start', undefined, '开始同步')
                    }
                  >
                    开始同步
                  </Button>
                </Col>
                <Col span={12}>
                  <Button
                    block
                    loading={sending}
                    disabled={!isOnline}
                    onClick={() =>
                      confirmSend('parallel_sync_stop', undefined, '停止同步')
                    }
                  >
                    停止同步
                  </Button>
                </Col>
              </Row>
            </Space>
          </Card>
        </Col>
      </Row>
    </Spin>
  )
}

export default ParallelTab
