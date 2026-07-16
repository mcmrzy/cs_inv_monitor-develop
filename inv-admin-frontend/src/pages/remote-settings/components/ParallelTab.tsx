import React from 'react'
import { Button, Row, Col, Space, Spin, Typography, Alert, Modal } from 'antd'
import {
  NodeIndexOutlined, SettingOutlined, ThunderboltOutlined, ApiOutlined,
} from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { useControlState } from '../hooks/useControlState'
import SettingField from './SettingField'
import SettingSection from './SettingSection'

const { Text } = Typography

interface ParallelTabProps {
  sn: string
}

const ParallelTab: React.FC<ParallelTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { reported, isOnline, isLoading, error, refetch, sendCommand, isSending } = useControlState(sn)

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
      onOk: () => sendCommand(command_code, params),
    })
  }

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
          <SettingSection title="并机拓扑" icon={<NodeIndexOutlined />}>
            <SettingField
              label="拓扑模式"
              fieldKey="parallel_topology"
              type="select"
              options={[
                { value: 'standalone', label: '单机' },
                { value: 'parallel', label: '并联' },
                { value: 'three_phase', label: '三相' },
              ]}
              reportedValue={reported.parallel_topology}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => confirmSend('parallel_set_topology', { topology: v }, '设置并机拓扑')}
            />
          </SettingSection>
        </Col>

        {/* ── 角色与机号 ── */}
        <Col xs={24} md={12}>
          <SettingSection title="角色与机号" icon={<SettingOutlined />}>
            <SettingField
              label="角色"
              fieldKey="parallel_role"
              type="select"
              options={[
                { value: 'master', label: '主机' },
                { value: 'slave', label: '从机' },
              ]}
              reportedValue={reported.parallel_role}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => confirmSend('parallel_set_role', { role: v }, '设置角色')}
            />
            <SettingField
              label="机号"
              fieldKey="parallel_machine_id"
              type="number"
              min={1}
              max={16}
              step={1}
              reportedValue={reported.parallel_machine_id}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => confirmSend('parallel_set_role', { machine_id: v }, '设置机号')}
            />
          </SettingSection>
        </Col>

        {/* ── 相位设置 ── */}
        <Col xs={24} md={12}>
          <SettingSection title="相位设置" icon={<ThunderboltOutlined />}>
            <SettingField
              label="相位"
              fieldKey="parallel_phase"
              type="select"
              options={[
                { value: 'A', label: 'A相' },
                { value: 'B', label: 'B相' },
                { value: 'C', label: 'C相' },
              ]}
              reportedValue={reported.parallel_phase}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => confirmSend('parallel_set_phase', { phase: v }, '设置相位')}
            />
          </SettingSection>
        </Col>

        {/* ── 共用电池 ── */}
        <Col xs={24} md={12}>
          <SettingSection title="共用电池" icon={<ThunderboltOutlined />}>
            <SettingField
              label="共用电池"
              fieldKey="shared_battery"
              type="switch"
              reportedValue={reported.shared_battery}
              disabled={!isOnline}
              pending={isSending}
              onSend={(v) => sendCommand('set_params', { shared_battery: v })}
              tooltip={t('remote.pendingProtocol')}
            />
          </SettingSection>
        </Col>

        {/* ── 组级控制 ── */}
        <Col xs={24} md={12}>
          <SettingSection title="组级控制" icon={<ApiOutlined />}>
            <Space direction="vertical" style={{ width: '100%' }} size="middle">
              <Text type="secondary" style={{ fontSize: 12 }}>
                以下操作将影响整个并机组，请谨慎操作
              </Text>
              <Row gutter={[8, 8]}>
                <Col span={12}>
                  <Button
                    block
                    loading={isSending}
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
                    loading={isSending}
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
                    loading={isSending}
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
                    loading={isSending}
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
          </SettingSection>
        </Col>
      </Row>
    </Spin>
  )
}

export default ParallelTab
