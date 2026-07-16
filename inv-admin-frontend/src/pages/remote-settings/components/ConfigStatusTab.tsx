import React, { useState } from 'react'
import {
  Card, Table, Tag, Spin, Typography, Button, Space, Row, Col, App,
} from 'antd'
import { ReloadOutlined, SyncOutlined, CheckCircleOutlined, CloseCircleOutlined } from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { SYNC_STATUS_MAP, STAGE_MAP } from '../types'
import type { ControlState, CommandRecord } from '../types'

const { Text, Title } = Typography

interface ConfigStatusTabProps {
  sn: string
}

const PRIMARY = '#4f6ef7'

const cardStyle = { borderRadius: 12 }

const ConfigStatusTab: React.FC<ConfigStatusTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const queryClient = useQueryClient()

  const [cmdPage, setCmdPage] = useState(1)

  // ── Query: control state ──
  const {
    data: controlState,
    isLoading: stateLoading,
    error: stateError,
    refetch: refetchState,
  } = useQuery({
    queryKey: queryKeys.devices.controlState(sn),
    queryFn: () => deviceApi.getControlState(sn).then((r) => (r as any).data?.data ?? null),
    refetchInterval: 15000,
  })

  const state = controlState as ControlState | null
  const syncStatus = state?.sync_status ?? 'unknown'
  const syncInfo = SYNC_STATUS_MAP[syncStatus] ?? SYNC_STATUS_MAP.unknown

  // ── Query: commands ──
  const {
    data: commandsRes,
    isLoading: cmdLoading,
    error: cmdError,
    refetch: refetchCmds,
  } = useQuery({
    queryKey: queryKeys.devices.commands(sn, { page: cmdPage, page_size: 20 }),
    queryFn: () =>
      deviceApi
        .getCommands(sn, { page: cmdPage, page_size: 20 })
        .then((r) => (r as any).data?.data ?? (r as any).data),
  })

  const commandRecords: CommandRecord[] =
    (commandsRes as any)?.items ?? (Array.isArray(commandsRes) ? commandsRes : [])
  const totalCommands: number = (commandsRes as any)?.total ?? commandRecords.length

  // ── Mutations ──
  const queryConfigMutation = useMutation({
    mutationFn: () =>
      deviceApi.sendCommand(sn, { command_code: 'query_config' }).then((r: any) => {
        const d = r.data?.data ?? r.data
        if (d && d.success === false) throw new Error(d.message ?? t('common.failed'))
        return d
      }),
    onSuccess: () => {
      message.success('查询命令已下发')
      void queryClient.invalidateQueries({ queryKey: queryKeys.devices.controlState(sn) })
      void queryClient.invalidateQueries({ queryKey: queryKeys.devices.commands(sn) })
    },
    onError: (err: Error) => message.error(err.message || t('common.failed')),
  })

  const handleSyncStatus = () => {
    void queryClient.invalidateQueries({ queryKey: queryKeys.devices.controlState(sn) })
    void queryClient.invalidateQueries({ queryKey: queryKeys.devices.commands(sn) })
    void refetchState()
    void refetchCmds()
    message.success('正在刷新')
  }

  // ── Comparison rows: merge desired + reported keys ──
  const desired = state?.desired ?? {}
  const reported = state?.reported ?? {}
  const allKeys = Array.from(
    new Set([...Object.keys(desired), ...Object.keys(reported)])
  ).sort()

  const comparisonData = allKeys.map((key) => ({
    key,
    desired: desired[key] !== undefined ? String(desired[key]) : '-',
    reported: reported[key] !== undefined ? String(reported[key]) : '-',
    match:
      desired[key] !== undefined &&
      reported[key] !== undefined &&
      String(desired[key]) === String(reported[key]),
    hasBoth: desired[key] !== undefined && reported[key] !== undefined,
  }))

  const compColumns: ColumnsType<(typeof comparisonData)[number]> = [
    { title: '参数名', dataIndex: 'key', key: 'key', width: 200 },
    {
      title: '期望值 (desired)',
      dataIndex: 'desired',
      key: 'desired',
      width: 200,
      render: (v: string) => <Text code>{v}</Text>,
    },
    {
      title: '实际值 (reported)',
      dataIndex: 'reported',
      key: 'reported',
      width: 200,
      render: (v: string) => <Text code>{v}</Text>,
    },
    {
      title: '状态',
      key: 'status',
      width: 80,
      align: 'center',
      render: (_: unknown, row: (typeof comparisonData)[number]) => {
        if (!row.hasBoth) return <Text type="secondary">—</Text>
        return row.match ? (
          <CheckCircleOutlined style={{ color: '#22c55e', fontSize: 16 }} />
        ) : (
          <CloseCircleOutlined style={{ color: '#ef4444', fontSize: 16 }} />
        )
      },
    },
  ]

  // ── Command history columns ──
  const cmdColumns: ColumnsType<CommandRecord> = [
    {
      title: '时间',
      dataIndex: 'created_at',
      key: 'created_at',
      width: 170,
      render: (v: string) => formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss'),
    },
    {
      title: '命令名称',
      dataIndex: 'command_code',
      key: 'command_code',
      width: 160,
      render: (v: string) => <Text code>{v}</Text>,
    },
    {
      title: '阶段',
      dataIndex: 'stage',
      key: 'stage',
      width: 100,
      render: (stage: string) => {
        const info = STAGE_MAP[stage]
        return <Tag color={info?.color ?? 'default'}>{info?.label_zh ?? stage}</Tag>
      },
    },
    {
      title: '结果',
      key: 'success',
      width: 80,
      align: 'center',
      render: (_: unknown, row: CommandRecord) => {
        if (row.success === undefined || row.success === null) return <Text type="secondary">—</Text>
        return row.success ? (
          <Tag color="success">成功</Tag>
        ) : (
          <Tag color="error">失败</Tag>
        )
      },
    },
  ]

  return (
    <Spin spinning={stateLoading || cmdLoading}>
      {(stateError || cmdError) && (
        <QueryErrorAlert
          error={stateError || cmdError}
          onRetry={() => {
            void refetchState()
            void refetchCmds()
          }}
          style={{ marginBottom: 16 }}
        />
      )}

      {/* ── 同步状态 ── */}
      <Card bordered={false} style={{ ...cardStyle, marginBottom: 16 }}>
        <Row gutter={24} align="middle">
          <Col flex="auto">
            <Text type="secondary" style={{ fontSize: 12 }}>同步状态</Text>
            <div>
              <Title level={2} style={{ margin: '4px 0', color: syncInfo.color }}>
                {syncInfo.label_zh}
              </Title>
            </div>
            <Space size="large" style={{ marginTop: 8 }}>
              <div>
                <Text type="secondary" style={{ fontSize: 12 }}>期望时间</Text>
                <div style={{ fontSize: 13 }}>
                  {state?.desired_at
                    ? formatInTimezone(state.desired_at, timezone, 'YYYY-MM-DD HH:mm:ss')
                    : '—'}
                </div>
              </div>
              <div>
                <Text type="secondary" style={{ fontSize: 12 }}>上报时间</Text>
                <div style={{ fontSize: 13 }}>
                  {state?.reported_at
                    ? formatInTimezone(state.reported_at, timezone, 'YYYY-MM-DD HH:mm:ss')
                    : '—'}
                </div>
              </div>
            </Space>
          </Col>
          <Col>
            <Space>
              <Button
                type="primary"
                icon={<ReloadOutlined />}
                loading={queryConfigMutation.isPending}
                onClick={() => queryConfigMutation.mutate()}
                style={{ background: PRIMARY, borderColor: PRIMARY }}
              >
                刷新配置
              </Button>
              <Button icon={<SyncOutlined />} onClick={handleSyncStatus}>
                同步状态
              </Button>
            </Space>
          </Col>
        </Row>
      </Card>

      {/* ── 参数对比 ── */}
      <Card
        title="参数对比"
        bordered={false}
        style={{ ...cardStyle, marginBottom: 16 }}
      >
        <Table
          rowKey="key"
          columns={compColumns}
          dataSource={comparisonData}
          size="middle"
          pagination={comparisonData.length > 20 ? { pageSize: 20, showSizeChanger: false } : false}
          locale={{ emptyText: '暂无参数数据' }}
        />
      </Card>

      {/* ── 命令历史 ── */}
      <Card title="命令历史" bordered={false} style={cardStyle}>
        <Table<CommandRecord>
          rowKey="task_id"
          columns={cmdColumns}
          dataSource={commandRecords}
          size="middle"
          pagination={{
            current: cmdPage,
            pageSize: 20,
            total: totalCommands,
            showSizeChanger: false,
            onChange: (page) => setCmdPage(page),
          }}
          locale={{ emptyText: '暂无命令记录' }}
        />
      </Card>
    </Spin>
  )
}

export default ConfigStatusTab
