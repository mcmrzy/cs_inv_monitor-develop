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
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { toRtEnvelope } from './energyUtils'
const { Text, Title: AntTitle } = Typography

interface DiagnosticsTabProps {
  sn: string
}

/** GET /devices/by-sn/:sn/commands 行（business-api GetCommandHistory 的 JSON 字段）：
 *  command_name/command_label、created_at、result_message/result；旧字段名保留兼容。 */
interface CommandRecord {
  id: string | number
  command_name?: string
  command_label?: string
  command_code?: string
  status: string
  created_at?: string
  sent_at?: string
  completed_at?: string | null
  result?: string
  result_message?: string
  response?: string
  error_message?: string
  sent_by?: string
}

/** 命令名（后端 command_label/command_name，兼容旧 command_code） */
const commandName = (r: CommandRecord): string =>
  r.command_label || r.command_name || r.command_code || '-'

/** 发送时间（后端 created_at，兼容旧 sent_at） */
const commandTime = (r: CommandRecord): string | undefined =>
  r.sent_at || r.created_at || undefined

/** 响应/错误摘要（后端 result_message/result，兼容旧 error_message/response） */
const commandResponse = (r: CommandRecord): string =>
  r.error_message || r.result_message || r.result || r.response || '-'

const DiagnosticsTab: React.FC<DiagnosticsTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const queryClient = useQueryClient()

  const { data: controlState, isLoading: stateLoading, error: stateError, refetch: refetchState } = useQuery({
    queryKey: queryKeys.devices.controlState(sn),
    queryFn: () => deviceApi.getControlState(sn).then((r) => r.data?.data ?? null),
  })

  // 设备在线判定以实时心跳为准：sync_status='unknown' 只表示该设备尚未有过控制态记录
  // （无 device_control_state 行），不代表离线，不能作为禁用自检/复位的依据。
  const { data: envelope } = useQuery({
    queryKey: queryKeys.devices.realtime(sn),
    queryFn: () => deviceApi.getRealtime(sn).then((r) => toRtEnvelope(r.data?.data ?? r.data)),
    refetchInterval: () => (document.visibilityState === 'visible' ? 10_000 : false),
  })

  const { data: commandsRes, isLoading: cmdLoading, error: commandsError, refetch: refetchCommands } = useQuery({
    queryKey: queryKeys.devices.commands(sn, { page: 1, page_size: 20 }),
    queryFn: () => deviceApi.getCommands(sn, { page: 1, page_size: 20 }).then((r) => r.data?.data ?? r.data),
  })

  const commandRecords: CommandRecord[] = (commandsRes as any)?.items ?? (Array.isArray(commandsRes) ? commandsRes : [])
  const isOnline = envelope?.online === true
    || controlState?.sync_status === 'in_sync' || controlState?.sync_status === 'pending'

  const selfTestMutation = useMutation({
    mutationFn: () => deviceApi.sendCommand(sn, { command: 'self_test', params: {} }),
    onSuccess: () => {
      message.success(t('deviceDetail.diagnostics.sendSuccess'))
      queryClient.invalidateQueries({ queryKey: queryKeys.devices.commands(sn) })
    },
    onError: () => { message.error(t('deviceDetail.diagnostics.sendFailed')) },
  })

  const faultResetMutation = useMutation({
    mutationFn: () => deviceApi.sendCommand(sn, { command: 'fault_reset', params: {} }),
    onSuccess: () => {
      message.success(t('deviceDetail.diagnostics.sendSuccess'))
      queryClient.invalidateQueries({ queryKey: queryKeys.devices.commands(sn) })
    },
    onError: () => { message.error(t('deviceDetail.diagnostics.sendFailed')) },
  })

  const cmdColumns: ColumnsType<CommandRecord> = [
    {
      title: t('deviceDetail.diagnostics.commandCode'), key: 'command', width: 180,
      render: (_, r) => <Text code>{commandName(r)}</Text>,
    },
    {
      title: t('deviceDetail.diagnostics.status'), dataIndex: 'status', key: 'status', width: 110,
      render: (s: string) => {
        const colorMap: Record<string, string> = {
          pending: 'default', sent: 'processing', success: 'green', failed: 'red', timeout: 'orange',
        }
        const key = `deviceDetail.diagnostics.status.${s}`
        const translated = t(key)
        return <Tag color={colorMap[s] ?? 'default'}>{translated !== key ? translated : s}</Tag>
      },
    },
    {
      title: t('deviceDetail.diagnostics.sentAt'), key: 'sent_at', width: 180,
      render: (_, r) => {
        const ts = commandTime(r)
        return ts ? formatInTimezone(ts, timezone, 'YYYY-MM-DD HH:mm:ss') : '-'
      },
    },
    {
      title: t('deviceDetail.diagnostics.response'), key: 'response', ellipsis: true,
      render: (_, r) => commandResponse(r),
    },
  ]

  const allKeys = Array.from(new Set([
    ...Object.keys(controlState?.desired ?? {}),
    ...Object.keys(controlState?.reported ?? {}),
  ])).sort()

  return (
    <Spin spinning={stateLoading || cmdLoading}>
      {(stateError || commandsError) && (
        <QueryErrorAlert
          error={stateError || commandsError}
          onRetry={() => { void (stateError ? refetchState() : refetchCommands()) }}
          style={{ marginBottom: 16 }}
        />
      )}
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
