import React, { useMemo, useCallback } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Table, Switch, Checkbox, InputNumber, Tag, Spin, App, Empty } from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  DashboardOutlined, ToolOutlined, InfoCircleOutlined,
  ThunderboltOutlined, FireOutlined, ExportOutlined,
  InboxOutlined,
} from '@ant-design/icons'
import { modelApi } from '@/services/modelApi'
import type { ModelFieldCapability, ModelConfigResponse } from '../types'
import { GROUP_COLORS, GROUP_ICONS, DS } from '../types'
import useTranslation from '@/hooks/useTranslation'

/* ==================== Props ==================== */

interface FieldConfigTabProps {
  modelId: number
}

/* ==================== Group-row helpers ==================== */

interface GroupHeaderRow {
  _isGroupHeader: true
  _groupKey: string
  field_key: string
  [k: string]: any
}

type RowRecord = ModelFieldCapability | GroupHeaderRow

function isGroupHeader(row: RowRecord): row is GroupHeaderRow {
  return (row as GroupHeaderRow)._isGroupHeader === true
}

const GROUP_ORDER: Record<string, number> = {
  telemetry: 0,
  status: 1,
  grid: 2,
  battery: 3,
  output: 4,
  control: 5,
}

function groupSortIndex(code: string): number {
  return GROUP_ORDER[code] ?? 99
}

/** Render group icon by name */
const GroupIcon: React.FC<{ groupKey: string; color: string }> = ({ groupKey, color }) => {
  const iconMap: Record<string, React.ReactNode> = {
    DashboardOutlined: <DashboardOutlined />,
    ToolOutlined: <ToolOutlined />,
    InfoCircleOutlined: <InfoCircleOutlined />,
    ThunderboltOutlined: <ThunderboltOutlined />,
    FireOutlined: <FireOutlined />,
    ExportOutlined: <ExportOutlined />,
  }
  const iconName = GROUP_ICONS[groupKey]
  return <span style={{ color, fontSize: 16, marginRight: 10 }}>{iconMap[iconName] ?? <DashboardOutlined />}</span>
}

/* ==================== Styles ==================== */

const fcStyles = `
.fc-table .ant-table {
  border-radius: 14px !important;
}
.fc-table .ant-table-thead > tr > th {
  background: #f0f2f5 !important;
  font-weight: 700 !important;
  font-size: 12px !important;
  color: #4b5563 !important;
  border-bottom: none !important;
  padding: 14px 16px !important;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}
.fc-table .ant-table-tbody > tr > td {
  padding: 13px 16px !important;
  transition: background 0.15s ease;
  vertical-align: middle !important;
}
.fc-table .ant-table-tbody > tr > td:first-child {
  padding-left: 20px !important;
}
.fc-table .ant-table-thead > tr > th:first-child {
  padding-left: 20px !important;
}
.fc-table .ant-table-tbody > tr:hover > td {
  background: #f0f5ff !important;
}
.fc-table .ant-table-cell-row-hover {
  background: #f0f5ff !important;
}
.fc-table .ant-switch-checked {
  background: ${DS.primary} !important;
}
.fc-group-header-row td {
  padding: 12px 16px !important;
}
.fc-table .ant-table-tbody > tr.fc-group-header-row:hover > td {
  background: inherit !important;
}
.fc-table .ant-table-container {
  border-radius: 14px;
  overflow: hidden;
  border: 1px solid ${DS.border};
}
.fc-group-badge {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 6px 14px;
  border-radius: 10px;
  font-weight: 700;
  font-size: 13px;
  letter-spacing: 0.01em;
}
.fc-field-key {
  font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Roboto Mono', monospace;
  font-size: 12px;
  background: ${DS.bgCode};
  padding: 3px 8px;
  border-radius: 6px;
  color: ${DS.textPrimary};
  display: inline-block;
  width: fit-content;
  border: 1px solid ${DS.border};
  letter-spacing: 0.01em;
}
.fc-unit-text {
  color: ${DS.textSecondary};
  font-size: 13px;
  font-weight: 500;
}
`

/* ==================== Component ==================== */

const FieldConfigTab: React.FC<FieldConfigTabProps> = ({ modelId }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const queryClient = useQueryClient()

  const queryKey = ['models', 'config', modelId]

  const { data, isLoading } = useQuery({
    queryKey,
    queryFn: async () => {
      const res = await modelApi.getModelConfig(modelId)
      return res.data as ModelConfigResponse
    },
    enabled: modelId > 0,
  })

  const fields: ModelFieldCapability[] = data?.fields ?? []

  const mutation = useMutation({
    mutationFn: (updated: Partial<ModelFieldCapability>[]) =>
      modelApi.batchUpdateFieldCapabilities(modelId, updated),
    onSuccess: () => {
      message.success(t('remoteSettings.saveSuccess'))
      queryClient.invalidateQueries({ queryKey })
    },
    onError: () => {
      message.error(t('remoteSettings.saveFailed'))
    },
  })

  const { tableData, groupRowKeySet } = useMemo(() => {
    const sorted = [...fields].sort((a, b) => {
      const gi = groupSortIndex(a.group_code) - groupSortIndex(b.group_code)
      if (gi !== 0) return gi
      return a.sort_order - b.sort_order
    })

    const rows: RowRecord[] = []
    const keySet = new Set<string>()
    let prevGroup: string | null = null

    sorted.forEach((field) => {
      if (field.group_code !== prevGroup) {
        const groupKey = field.group_code
        const headerKey = `__group_${groupKey}`
        keySet.add(headerKey)
        rows.push({
          _isGroupHeader: true,
          _groupKey: groupKey,
          field_key: headerKey,
        } as GroupHeaderRow)
        prevGroup = groupKey
      }
      rows.push(field)
    })

    return { tableData: rows, groupRowKeySet: keySet }
  }, [fields])

  const patchField = useCallback(
    (field: ModelFieldCapability, patch: Partial<ModelFieldCapability>) => {
      mutation.mutate([{ ...field, ...patch }])
    },
    [mutation],
  )

  const groupColor = (code: string) => GROUP_COLORS[code] ?? GROUP_COLORS.default

  /* ---------- Columns ---------- */

  const columns: ColumnsType<RowRecord> = useMemo(
    () => [
      {
        title: t('remoteSettings.fieldName'),
        dataIndex: 'field_key',
        width: 220,
        render: (_: unknown, record: RowRecord) => {
          if (isGroupHeader(record)) {
            const color = groupColor(record._groupKey)
            return (
              <div className="fc-group-badge" style={{ background: `${color}12`, color }}>
                <GroupIcon groupKey={record._groupKey} color={color} />
                {t(`fieldGroup.${record._groupKey}`, { fallback: record._groupKey })}
              </div>
            )
          }
          const f = record as ModelFieldCapability
          const translated = f.display_name_key ? t(f.display_name_key) : ''
          return (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
              <code className="fc-field-key">{f.field_key}</code>
              {translated && translated !== f.display_name_key && (
                <span style={{ fontSize: 12, color: DS.textSecondary }}>{translated}</span>
              )}
            </div>
          )
        },
      },
      {
        title: t('remoteSettings.group'),
        dataIndex: 'group_code',
        width: 110,
        render: (_: unknown, record: RowRecord) => {
          if (isGroupHeader(record)) return null
          const f = record as ModelFieldCapability
          return (
            <Tag
              color={groupColor(f.group_code)}
              style={{ borderRadius: DS.radiusTag, fontWeight: 600, fontSize: 12, padding: '2px 10px' }}
            >
              {f.group_code}
            </Tag>
          )
        },
      },
      {
        title: t('remoteSettings.unit'),
        dataIndex: 'display_unit',
        width: 80,
        align: 'center',
        render: (_: unknown, record: RowRecord) =>
          isGroupHeader(record) ? null : (
            <span className="fc-unit-text">
              {(record as ModelFieldCapability).display_unit ?? '—'}
            </span>
          ),
      },
      {
        title: t('remoteSettings.decimalPlaces'),
        dataIndex: 'decimal_places',
        width: 90,
        align: 'center',
        render: (_: unknown, record: RowRecord) =>
          isGroupHeader(record) ? null : (record as ModelFieldCapability).decimal_places,
      },
      {
        title: t('remoteSettings.visible'),
        dataIndex: 'is_visible',
        width: 80,
        align: 'center',
        render: (_: unknown, record: RowRecord) => {
          if (isGroupHeader(record)) return null
          const f = record as ModelFieldCapability
          return <Switch size="small" checked={f.is_visible} onChange={(v) => patchField(f, { is_visible: v })} />
        },
      },
      {
        title: t('remoteSettings.showRealtime'),
        dataIndex: 'show_realtime',
        width: 100,
        align: 'center',
        render: (_: unknown, record: RowRecord) => {
          if (isGroupHeader(record)) return null
          const f = record as ModelFieldCapability
          return <Switch size="small" checked={f.show_realtime} onChange={(v) => patchField(f, { show_realtime: v })} />
        },
      },
      {
        title: t('remoteSettings.showHistory'),
        dataIndex: 'show_history',
        width: 100,
        align: 'center',
        render: (_: unknown, record: RowRecord) => {
          if (isGroupHeader(record)) return null
          const f = record as ModelFieldCapability
          return <Switch size="small" checked={f.show_history} onChange={(v) => patchField(f, { show_history: v })} />
        },
      },
      {
        title: t('remoteSettings.allowCompare'),
        dataIndex: 'allow_compare',
        width: 90,
        align: 'center',
        render: (_: unknown, record: RowRecord) => {
          if (isGroupHeader(record)) return null
          const f = record as ModelFieldCapability
          return <Checkbox checked={f.allow_compare} onChange={(e) => patchField(f, { allow_compare: e.target.checked })} />
        },
      },
      {
        title: t('remoteSettings.allowAlarm'),
        dataIndex: 'allow_alarm_rule',
        width: 90,
        align: 'center',
        render: (_: unknown, record: RowRecord) => {
          if (isGroupHeader(record)) return null
          const f = record as ModelFieldCapability
          return <Checkbox checked={f.allow_alarm_rule} onChange={(e) => patchField(f, { allow_alarm_rule: e.target.checked })} />
        },
      },
      {
        title: t('remoteSettings.sortOrder'),
        dataIndex: 'sort_order',
        width: 90,
        align: 'center',
        render: (_: unknown, record: RowRecord) => {
          if (isGroupHeader(record)) return null
          const f = record as ModelFieldCapability
          return (
            <InputNumber
              size="small"
              style={{ width: 64, borderRadius: 8, border: `1px solid ${DS.border}` }}
              value={f.sort_order}
              min={0}
              onBlur={(e) => {
                const v = Number(e.target.value)
                if (!Number.isNaN(v) && v !== f.sort_order) patchField(f, { sort_order: v })
              }}
              onPressEnter={(e) => {
                const v = Number((e.target as HTMLInputElement).value)
                if (!Number.isNaN(v) && v !== f.sort_order) patchField(f, { sort_order: v })
              }}
            />
          )
        },
      },
    ],
    [t, patchField],
  )

  if (isLoading) {
    return (
      <div style={{ textAlign: 'center', padding: 80 }}>
        <Spin size="large" />
      </div>
    )
  }

  return (
    <div className="fc-table">
      <style>{fcStyles}</style>
      <Table<RowRecord>
        columns={columns}
        dataSource={tableData}
        rowKey="field_key"
        size="middle"
        pagination={false}
        scroll={{ y: 'calc(100vh - 320px)' }}
        locale={{
          emptyText: (
            <div style={{ padding: '60px 0' }}>
              <Empty
                image={<InboxOutlined style={{ fontSize: 48, color: DS.textMuted }} />}
                description={
                  <span style={{ color: DS.textSecondary, fontSize: 14 }}>
                    {t('remoteSettings.noFields', { fallback: 'No fields configured yet' })}
                  </span>
                }
              />
            </div>
          ),
        }}
        onHeaderRow={() => ({
          style: { position: 'sticky', top: 0, zIndex: 10 },
        })}
        onRow={(record, index) => {
          if (isGroupHeader(record)) {
            const color = groupColor(record._groupKey)
            return {
              style: {
                position: 'sticky',
                top: 44,
                zIndex: 9,
                background: `linear-gradient(90deg, ${color}10, ${color}05)`,
                borderLeft: `4px solid ${color}`,
              },
            }
          }
          return {
            style: {
              background: index !== undefined && index % 2 === 0 ? '#fff' : '#fafbfc',
            },
          }
        }}
        rowClassName={(record) => (isGroupHeader(record) ? 'fc-group-header-row' : '')}
      />
    </div>
  )
}

export default FieldConfigTab
