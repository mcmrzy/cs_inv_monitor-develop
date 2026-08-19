import React, { useMemo, useState } from 'react'
import {
  Collapse, InputNumber, Select, Switch, Button, Tag, App, Spin, Empty,
  Typography, Space, Divider, Table, Card, Tooltip,
} from 'antd'
import type { TableProps } from 'antd'
import { SendOutlined, HistoryOutlined, SettingOutlined, CheckCircleFilled, WarningFilled, ClockCircleFilled } from '@ant-design/icons'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import type { CommandRecord } from '../types'

const { Text } = Typography

// ── device_config_schema 行结构（与 business-api /devices/by-sn/:sn/config-schema 对齐）──
export interface ConfigSchemaItem {
  param_key: string
  group_code: 'general' | 'application' | 'hybrid' | 'parallel'
  sub_group: string
  control_type: 'number' | 'enum' | 'boolean'
  scale: number
  unit: string
  min?: number | null
  max?: number | null
  enum_map?: Record<string, string> | null
  step?: number | null
  permission_code: string
  confirmation_mode?: string | null
  display_name_key: string
  sort_order: number
  visibility?: { param?: string; eq?: number; ne?: number } | null
  validation?: Record<string, string> | null
}

interface SchemaGroupPanelProps {
  sn: string
}

// 分组标题（对齐 V1 界面四分组：通用/应用/混合/并联）
const GROUP_META: Record<string, { key: string; icon: React.ReactNode }> = {
  general: { key: 'remote.schema.general', icon: <SettingOutlined /> },
  application: { key: 'remote.schema.application', icon: <SendOutlined /> },
  hybrid: { key: 'remote.schema.hybrid', icon: <SendOutlined /> },
  parallel: { key: 'remote.schema.parallel', icon: <SendOutlined /> },
}

// 混合设置内子分组标题
const SUBGROUP_META: Record<string, string> = {
  charge: 'remote.schema.sub.charge',
  discharge: 'remote.schema.sub.discharge',
  soc: 'remote.schema.sub.soc',
  equalize: 'remote.schema.sub.equalize',
  gen: 'remote.schema.sub.gen',
}

const GROUP_ORDER = ['general', 'application', 'hybrid', 'parallel']
const SUBGROUP_ORDER = ['charge', 'discharge', 'soc', 'equalize', 'gen']

// 每参数同步状态：desired vs reported
function syncTag(key: string, control: { desired?: Record<string, unknown>; reported?: Record<string, unknown>; sync_status?: string }): React.ReactNode {
  const desired = control?.desired?.[key]
  const reported = control?.reported?.[key]
  if (desired === undefined) return null
  if (reported !== undefined && String(desired) === String(reported)) {
    return (
      <Tooltip title="desired = reported">
        <Tag icon={<CheckCircleFilled />} color="success">synced</Tag>
      </Tooltip>
    )
  }
  const drifted = control?.sync_status === 'drifted'
  return drifted ? (
    <Tooltip title="desired ≠ reported">
      <Tag icon={<WarningFilled />} color="error">drifted</Tag>
    </Tooltip>
  ) : (
    <Tooltip title="等待设备确认">
      <Tag icon={<ClockCircleFilled />} color="processing">pending</Tag>
    </Tooltip>
  )
}

// visibility 联动判定：{"param":"set_battery_type","eq":0} / {"ne":2}
function isVisible(item: ConfigSchemaItem, reported: Record<string, unknown>, desired: Record<string, unknown>): boolean {
  const v = item.visibility
  if (!v?.param) return true
  const cur = reported[v.param] ?? desired[v.param]
  if (cur === undefined) return false // 联动参数未上报：隐藏
  const num = Number(cur)
  if (v.eq !== undefined) return num === v.eq
  if (v.ne !== undefined) return num !== v.ne
  return true
}

const SchemaGroupPanel: React.FC<SchemaGroupPanelProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { message, modal } = App.useApp()
  const queryClient = useQueryClient()
  const hasPermission = useAuthStore((s) => s.hasPermission)
  const [values, setValues] = useState<Record<string, unknown>>({})
  const [sendingKey, setSendingKey] = useState<string | null>(null)

  const { data: schema, isLoading: schemaLoading, error: schemaError, refetch: refetchSchema } = useQuery({
    queryKey: ['config-schema', sn],
    queryFn: () =>
      deviceApi.getConfigSchema(sn).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        // 兼容直接数组 / {items:[...]} 两种形状，非数组一律降级为空列表，避免渲染期 .map / for...of 崩溃
        return (Array.isArray(d) ? d : (Array.isArray((d as any)?.items) ? (d as any).items : [])) as ConfigSchemaItem[]
      }),
    staleTime: 300_000,
  })

  const { data: controlState, error: stateError, refetch: refetchState } = useQuery({
    queryKey: queryKeys.devices.controlState(sn),
    queryFn: () => deviceApi.getControlState(sn).then((r) => (r.data?.data ?? null) as any),
    refetchInterval: 10_000, // 闭环轮询
  })

  const { data: history, refetch: refetchHistory } = useQuery({
    queryKey: ['device-commands', sn],
    queryFn: () =>
      deviceApi.getCommands(sn, { page: 1, page_size: 10 }).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (d?.items ?? (Array.isArray(d) ? d : [])) as CommandRecord[]
      }),
    refetchInterval: 10_000,
  })

  const reported = (controlState?.reported ?? {}) as Record<string, unknown>
  const desired = (controlState?.desired ?? {}) as Record<string, unknown>

  const label = (item: ConfigSchemaItem): string => {
    const key = item.display_name_key
    if (t(key) !== key) return t(key)
    const cmdKey = `commands.${item.param_key}`
    if (t(cmdKey) !== cmdKey) return t(cmdKey)
    return item.param_key
  }

  const enumLabel = (item: ConfigSchemaItem, rawKey: string): string => {
    const semantic = item.enum_map?.[rawKey]
    if (!semantic) return rawKey
    const key = `config.enum.${semantic}`
    return t(key) !== key ? t(key) : semantic
  }

  const doSend = (item: ConfigSchemaItem, value: unknown) => {
    setSendingKey(item.param_key)
    deviceApi
      .sendCommand(sn, { command: item.param_key, params: { value } })
      .then(() => {
        message.success(t('remote.commandSent', { taskId: '' }))
        void queryClient.invalidateQueries({ queryKey: queryKeys.devices.controlState(sn) })
        void refetchHistory()
      })
      .catch((err: any) => {
        const detail = err?.response?.data?.data?.reject_detail ?? err?.response?.data?.message ?? err?.message ?? ''
        message.error(`${t('remote.commandSendFailed')}${detail ? `: ${detail}` : ''}`)
      })
      .finally(() => setSendingKey(null))
  }

  const handleSend = (item: ConfigSchemaItem, value: unknown) => {
    if (value === undefined || value === null || value === '') {
      message.warning(t('remote.paramRequired'))
      return
    }
    const action = () => doSend(item, value)
    if (item.confirmation_mode === 'modal') {
      modal.confirm({
        title: t('remote.confirmSendTitle'),
        content: t('remote.confirmSendContent', { sn, cmd: label(item) }),
        okText: t('remote.confirmExecute'),
        cancelText: t('remote.cancel'),
        okButtonProps: { danger: true },
        onOk: action,
      })
    } else {
      action()
    }
  }

  // 行渲染：标签 + 工程单位 + 控件 + 设置按钮 + 同步标记
  const renderFieldRow = (item: ConfigSchemaItem) => {
    const perm = hasPermission(item.permission_code)
    const current = values[item.param_key] ?? reported[item.param_key] ?? desired[item.param_key]
    const sending = sendingKey === item.param_key

    let control: React.ReactNode
    if (item.control_type === 'boolean') {
      control = (
        <Switch
          size="small"
          checked={Boolean(current)}
          disabled={!perm || sending}
          loading={sending}
          onChange={(v) => handleSend(item, v ? 1 : 0)}
        />
      )
    } else if (item.control_type === 'enum') {
      control = (
        <Select
          size="small"
          style={{ width: 160 }}
          value={current as number | undefined}
          disabled={!perm}
          options={Object.keys(item.enum_map ?? {}).map((k) => ({
            label: `${k} - ${enumLabel(item, k)}`,
            value: Number(k),
          }))}
          onChange={(v) => setValues((prev) => ({ ...prev, [item.param_key]: v }))}
        />
      )
    } else {
      control = (
        <InputNumber
          size="small"
          style={{ width: 120 }}
          min={item.min ?? undefined}
          max={item.max ?? undefined}
          step={item.step ?? 1}
          value={current as number | undefined}
          disabled={!perm}
          onChange={(v) => setValues((prev) => ({ ...prev, [item.param_key]: v }))}
        />
      )
    }

    return (
      <div
        key={item.param_key}
        style={{
          display: 'flex', alignItems: 'center', gap: 12,
          padding: '8px 0', borderBottom: '1px solid #f5f5f5',
        }}
      >
        <div style={{ flex: 1, minWidth: 0 }}>
          <Space size={6} wrap>
            <Text style={{ fontSize: 13 }}>{label(item)}</Text>
            {item.unit && <Text type="secondary" style={{ fontSize: 12 }}>({item.unit})</Text>}
            {syncTag(item.param_key, controlState)}
          </Space>
          <div>
            <Text code style={{ fontSize: 11, color: '#bbb' }}>{item.param_key}</Text>
          </div>
        </div>
        {control}
        {item.control_type !== 'boolean' && (
          <Button
            type="primary"
            size="small"
            icon={<SendOutlined />}
            loading={sending}
            disabled={!perm}
            onClick={() => handleSend(item, values[item.param_key] ?? current)}
          >
            {t('remote.set')}
          </Button>
        )}
      </div>
    )
  }

  // 按组/子组组织参数
  const grouped = useMemo(() => {
    const groups: Record<string, { direct: ConfigSchemaItem[]; subs: Record<string, ConfigSchemaItem[]> }> = {}
    for (const g of GROUP_ORDER) {
      groups[g] = { direct: [], subs: {} }
      for (const s of SUBGROUP_ORDER) groups[g].subs[s] = []
    }
    for (const item of Array.isArray(schema) ? schema : []) {
      if (!groups[item.group_code]) continue
      if (item.sub_group) {
        groups[item.group_code].subs[item.sub_group]?.push(item)
      } else {
        groups[item.group_code].direct.push(item)
      }
    }
    return groups
  }, [schema])

  const historyColumns: TableProps<CommandRecord>['columns'] = [
    {
      title: t('remote.commandCode'), dataIndex: 'command_code', key: 'command_code', width: 200,
      render: (v: string) => <Text code>{v}</Text>,
    },
    {
      title: t('remote.stage'), dataIndex: 'stage', key: 'stage', width: 110,
      render: (_, r) => {
        const color = r.stage === 'completed' ? (r.success === false ? 'error' : 'success') : 'processing'
        return <Tag color={color}>{r.stage}</Tag>
      },
    },
    {
      title: t('remote.commandParams'), dataIndex: 'params', key: 'params', ellipsis: true,
      render: (_, r) => r.params ? <Text type="secondary" style={{ fontSize: 12 }}>{JSON.stringify(r.params)}</Text> : '-',
    },
    {
      title: t('remote.sentAt'), dataIndex: 'created_at', key: 'created_at', width: 170,
      render: (v: string) => v ? <Text type="secondary" style={{ fontSize: 12 }}>{v}</Text> : '-',
    },
  ]

  const renderGroup = (groupCode: string) => {
    const g = grouped[groupCode]
    const items = [
      ...g.direct,
      ...SUBGROUP_ORDER.filter((s) => (g.subs[s]?.length ?? 0) > 0).flatMap((s) => g.subs[s] ?? []),
    ]
    const visible = items.filter((it) => isVisible(it, reported, desired))
    if (visible.length === 0) return <Text type="secondary" style={{ fontSize: 12 }}>{t('remote.schema.noVisibleParams')}</Text>
    return (
      <div>
        {/* 无子分组参数 */}
        {g.direct.filter((it) => isVisible(it, reported, desired)).map(renderFieldRow)}
        {/* 子分组 */}
        {SUBGROUP_ORDER.filter((s) => (g.subs[s]?.length ?? 0) > 0).map((s) => {
          const subItems = (g.subs[s] ?? []).filter((it) => isVisible(it, reported, desired))
          if (subItems.length === 0) return null
          return (
            <div key={s}>
              <Divider orientation="left" style={{ margin: '12px 0 4px', fontSize: 13 }}>
                <Text strong style={{ fontSize: 13 }}>{t(SUBGROUP_META[s])}</Text>
              </Divider>
              {subItems.map(renderFieldRow)}
            </div>
          )
        })}
      </div>
    )
  }

  const loadError = schemaError || stateError
  const refetchAll = () => { void refetchSchema(); void refetchState() }

  return (
    <Spin spinning={schemaLoading}>
      {loadError && (
        <QueryErrorAlert error={loadError} onRetry={refetchAll} style={{ marginBottom: 16 }} />
      )}

      {schema && schema.length > 0 ? (
        <Collapse
          defaultActiveKey={['general', 'application', 'hybrid', 'parallel']}
          style={{ background: 'transparent', border: 'none' }}
          ghost
        >
          {GROUP_ORDER.map((g) => (
            <Collapse.Panel
              key={g}
              header={
                <Space size={8}>
                  <span style={{ fontSize: 15, fontWeight: 600, color: '#333' }}>{t(GROUP_META[g].key)}</span>
                  <Tag color="blue" style={{ marginLeft: 4 }}>{grouped[g].direct.length + SUBGROUP_ORDER.reduce((n, s) => n + (grouped[g].subs[s]?.length ?? 0), 0)}</Tag>
                </Space>
              }
              style={{ marginBottom: 12, background: '#fff', borderRadius: 12, borderLeft: '3px solid #1677ff', overflow: 'hidden', boxShadow: '0 1px 4px rgba(0,0,0,0.06)' }}
            >
              {renderGroup(g)}
            </Collapse.Panel>
          ))}
        </Collapse>
      ) : (
        !schemaLoading && <Empty description={t('remote.schema.empty')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
      )}

      <Card
        size="small"
        title={<Space size={8}><HistoryOutlined style={{ color: '#1677ff' }} /><span>{t('remote.commandHistory')}</span></Space>}
        style={{ borderRadius: 12, marginTop: 16, boxShadow: '0 1px 4px rgba(0,0,0,0.06)' }}
      >
        <Table<CommandRecord>
          rowKey={(r) => `${r.task_id}-${r.command_code}`}
          size="small"
          columns={historyColumns}
          dataSource={history ?? []}
          pagination={false}
          scroll={{ y: 260 }}
          locale={{ emptyText: <Empty description={t('remote.noHistory')} image={Empty.PRESENTED_IMAGE_SIMPLE} /> }}
        />
      </Card>
    </Spin>
  )
}

export default SchemaGroupPanel
