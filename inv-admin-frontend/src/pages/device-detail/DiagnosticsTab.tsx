import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Card, Table, Tag, Spin, Empty, Typography, Tooltip, Button, Space, Alert, Popconfirm, App,
  Row, Col,
} from 'antd'
import { ExperimentOutlined, WarningOutlined } from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
const { Text, Title: AntTitle } = Typography

interface DiagnosticsTabProps {
  sn: string
}

interface CommandRecord {
  id: string
  command_code: string
  status: string
  sent_at: string
  completed_at: string | null
  response: string
  error_message: string
  sent_by: string
}

const DiagnosticsTab: React.FC<DiagnosticsTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const queryClient = useQueryClient()

  const { data: controlState, isLoading: stateLoading } = useQuery({
    queryKey: queryKeys.devices.controlState(sn),
    queryFn: () => deviceApi.getControlState(sn).then((r) => r.data?.data ?? null),
  })

  const { data: commandsRes, isLoading: cmdLoading } = useQuery({
    queryKey: queryKeys.devices.commands(sn, { page: 1, page_size: 20 }),
    queryFn: () => deviceApi.getCommands(sn, { page: 1, page_size: 20 }).then((r) => r.data?.data ?? r.data),
  })

  const commandRecords: CommandRecord[] = (commandsRes as any)?.items ?? (Array.isArray(commandsRes) ? commandsRes : [])
  const isOnline = controlState?.sync_status === 'in_sync' || controlState?.sync_status === 'pending'

  const selfTestMutation = useMutation({
    mutationFn: () => deviceApi.sendCommand(sn, { command_code: 'self_test', args: {} }),
    onSuccess: () => {
      message.success(t('deviceDetail.diagnostics.sendSuccess'))
      queryClient.invalidateQueries({ queryKey: queryKeys.devices.commands(sn) })
    },
    onError: () => { message.error(t('deviceDetail.diagnostics.sendFailed')) },
  })

  const faultResetMutation = useMutation({
    mutationFn: () => deviceApi.sendCommand(sn, { command_code: 'fault_reset', args: {} }),
    onSuccess: () => {
      message.success(t('deviceDetail.diagnostics.sendSuccess'))
      queryClient.invalidateQueries({ queryKey: queryKeys.devices.commands(sn) })
    },
    onError: () => { message.error(t('deviceDetail.diagnostics.sendFailed')) },
  })

  const cmdColumns: ColumnsType<CommandRecord> = [
    { title: t('deviceDetail.diagnostics.commandCode'), dataIndex: 'command_code', key: 'command_code', width: 160, render: (v: string) => <Text code>{v}</Text> },
    {
      title: t('deviceDetail.diagnostics.status'), dataIndex: 'status', key: 'status', width: 120,
      render: (s: string) => {
        const colorMap: Record<string, string> = {
          pending: 'default', sent: 'processing', success: 'green', failed: 'red', timeout: 'orange',
        }
        return <Tag color={colorMap[s] ?? 'default'}>{s}</Tag>
      },
    },
    {
      title: t('deviceDetail.diagnostics.sentAt'), dataIndex: 'sent_at', key: 'sent_at', width: 170,
      render: (v: string) => formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss'),
    },
    {
      title: t('deviceDetail.diagnostics.response'), key: 'response', ellipsis: true,
      render: (_: unknown, r: CommandRecord) => r.error_message || r.response || '-',
    },
  ]

  const allKeys = Array.from(new Set([
    ...Object.keys(controlState?.desired ?? {}),
    ...Object.keys(controlState?.reported ?? {}),
  ])).sort()

  return (
    <Spin spinning={stateLoading || cmdLoading}>
      {/* Action Cards */}
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={12}>
          <Card
            title={
              <Space>
                <ExperimentOutlined />
                <span>{t('deviceDetail.diagnostics.selfTest')}</span>
              </Space>
            }
            size="small"
            bordered={false}
            style={{ borderRadius: 12 }}
          >
            <Alert message={t('deviceDetail.diagnostics.selfTestHint')} type="info" showIcon style={{ marginBottom: 12 }} />
            <Tooltip title={!isOnline ? t('deviceDetail.diagnostics.selfTestHint') : ''} placement="top">
              <Button
                type="primary"
                icon={<ExperimentOutlined />}
                loading={selfTestMutation.isPending}
                disabled={!isOnline}
                onClick={() => selfTestMutation.mutate()}
              >
                {t('deviceDetail.diagnostics.runSelfTest')}
              </Button>
            </Tooltip>
          </Card>
        </Col>
        <Col span={12}>
          <Card
            title={
              <Space>
                <WarningOutlined style={{ color: '#faad14' }} />
                <span>{t('deviceDetail.diagnostics.faultReset')}</span>
              </Space>
            }
            size="small"
            bordered={false}
            style={{ borderRadius: 12 }}
          >
            <Alert message={t('deviceDetail.diagnostics.faultResetHint')} type="warning" showIcon style={{ marginBottom: 12 }} />
            <Popconfirm
              title={t('deviceDetail.diagnostics.runFaultReset')}
              description={t('deviceDetail.diagnostics.faultResetHint')}
              onConfirm={() => faultResetMutation.mutate()}
              disabled={!isOnline}
            >
              <Tooltip title={!isOnline ? t('deviceDetail.diagnostics.faultResetHint') : ''} placement="top">
                <Button
                  danger
                  icon={<WarningOutlined />}
                  loading={faultResetMutation.isPending}
                  disabled={!isOnline}
                >
                  {t('deviceDetail.diagnostics.runFaultReset')}
                </Button>
              </Tooltip>
            </Popconfirm>
          </Card>
        </Col>
      </Row>

      {/* Config Snapshot */}
      <Card
        title={t('deviceDetail.diagnostics.configSnapshot')}
        size="small"
        bordered={false}
        style={{ marginBottom: 16, borderRadius: 12 }}
      >
        <Alert message={t('deviceDetail.diagnostics.snapshotHint')} type="info" showIcon style={{ marginBottom: 12 }} />
        {allKeys.length > 0 ? (
          <Row gutter={16}>
            <Col span={12}>
              <AntTitle level={5}>{t('deviceDetail.diagnostics.desired')}</AntTitle>
              {allKeys.map((key) => (
                <div key={key} style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', borderBottom: '1px solid #f0f0f0' }}>
                  <Text type="secondary" style={{ fontSize: 12 }}>{key}</Text>
                  <Text style={{ fontSize: 12 }}>{String(controlState?.desired?.[key] ?? '-')}</Text>
                </div>
              ))}
            </Col>
            <Col span={12}>
              <AntTitle level={5}>{t('deviceDetail.diagnostics.reported')}</AntTitle>
              {allKeys.map((key) => (
                <div key={key} style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', borderBottom: '1px solid #f0f0f0' }}>
                  <Text type="secondary" style={{ fontSize: 12 }}>{key}</Text>
                  <Text style={{ fontSize: 12 }}>{String(controlState?.reported?.[key] ?? '-')}</Text>
                </div>
              ))}
            </Col>
          </Row>
        ) : (
          <Empty description={t('deviceDetail.status.noData')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
        )}
      </Card>

      {/* Command History */}
      <Card
        title={t('deviceDetail.diagnostics.commandHistory')}
        size="small"
        bordered={false}
        style={{ borderRadius: 12 }}
      >
        <Table<CommandRecord>
          rowKey="id"
          columns={cmdColumns}
          dataSource={commandRecords}
          size="small"
          pagination={{ pageSize: 10, showSizeChanger: false }}
          locale={{ emptyText: <Empty description={t('deviceDetail.diagnostics.noCommands')} /> }}
        />
      </Card>
    </Spin>
  )
}

export default DiagnosticsTab
