import { useState } from 'react'
import { Alert, Button, Card, Input, Space, Statistic, Table, Tag, Typography } from 'antd'
import type { ColumnsType } from 'antd/es/table'
import { ReloadOutlined } from '@ant-design/icons'
import { useQuery } from '@tanstack/react-query'
import { getRuntimeMonitor, type RuntimeErrorGroup, type SchemaColumnCheck } from '@/services/runtimeMonitorApi'
import useAuthStore from '@/stores/authStore'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import { formatInTimezone } from '@/utils/timezone'

function useRuntimeMonitor() {
  const isSystemAdmin = useAuthStore((s) => s.user?.isSystemAdmin === true)
  return useQuery({
    queryKey: ['runtime-monitor'], queryFn: getRuntimeMonitor, enabled: isSystemAdmin,
    refetchInterval: 30_000,
  })
}

// Keep runtime failures visible even while container/connectivity cards are green.
export function RuntimeMonitorAlert() {
  const { t } = useTranslation()
  const { data, error } = useRuntimeMonitor()
  if (error || data?.errors_status === 'unknown' || data?.schema.status === 'unknown') {
    return <Alert type="warning" showIcon message={t('system.runtime.unknownHint')} style={{ marginBottom: 16 }} />
  }
  if (data?.schema.status === 'degraded' || (data?.errors_5m ?? 0) > 0) {
    return <Alert type="error" showIcon message={t('system.runtime.faultHint')} style={{ marginBottom: 16 }} />
  }
  return null
}

export default function RuntimeErrorsTab() {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const { data, error, isLoading, isFetching, refetch } = useRuntimeMonitor()
  const [keyword, setKeyword] = useState('')
  const [page, setPage] = useState(1)
  const historyKnown = !error && data?.errors_status === 'ok'
  const formatTime = (value: string) => formatInTimezone(value, timezone, 'YYYY-MM-DD HH:mm:ss')
  const columns: ColumnsType<RuntimeErrorGroup> = [
    { title: t('system.runtime.lastSeen'), dataIndex: 'last_seen', width: 175, render: formatTime },
    { title: t('system.runtime.service'), dataIndex: 'service', width: 130 },
    { title: t('system.runtime.route'), key: 'route', width: 250, render: (_, row) => <Space direction="vertical" size={0}><Typography.Text>{row.method}</Typography.Text><Typography.Text code>{row.route}</Typography.Text></Space> },
    { title: t('system.runtime.status'), dataIndex: 'status', width: 100, render: (v: number, row) => <Tag color="red">{v}{row.http_status !== v ? ` (HTTP ${row.http_status})` : ''}</Tag> },
    { title: t('system.runtime.reason'), key: 'reason', width: 290, render: (_, row) => <Space direction="vertical" size={0}><Typography.Text>{row.summary}</Typography.Text>{row.sql_state && <Typography.Text code>{row.sql_state}</Typography.Text>}</Space> },
    { title: t('system.runtime.count'), dataIndex: 'count', width: 80 },
    { title: t('system.runtime.firstSeen'), dataIndex: 'first_seen', width: 175, render: formatTime },
    { title: t('system.runtime.requestId'), dataIndex: 'request_id', width: 270, render: (v: string) => <Typography.Text code copyable>{v}</Typography.Text> },
    { title: t('system.runtime.duration'), dataIndex: 'duration_ms', width: 100, render: (v: number) => `${v} ms` },
  ]
  const schemaColumns: ColumnsType<SchemaColumnCheck> = [
    { title: t('system.runtime.table'), dataIndex: 'table' },
    { title: t('system.runtime.column'), dataIndex: 'column' },
    { title: t('system.runtime.expected'), dataIndex: 'expected_type' },
    { title: t('system.runtime.actual'), dataIndex: 'actual_type', render: (v?: string) => v || '—' },
    { title: t('system.runtime.status'), dataIndex: 'status', render: (v: SchemaColumnCheck['status']) => <Tag color={v === 'ok' ? 'green' : 'red'}>{t(`system.runtime.${v}`)}</Tag> },
  ]
  const search = keyword.trim().toLowerCase()
  const rows = historyKnown ? (data?.groups ?? []).filter((row) =>
    [row.route, row.summary, row.kind, row.sql_state, row.request_id, row.service].some((v) => v?.toLowerCase().includes(search)),
  ) : []

  return <Space direction="vertical" size="middle" style={{ width: '100%' }}>
    <Alert type="info" showIcon message={t('system.runtime.scope')} description={t('system.runtime.retention')} />
    <Space wrap>
      <Button icon={<ReloadOutlined />} loading={isFetching} onClick={() => void refetch()}>{t('common.refresh')}</Button>
      {data && <Typography.Text type="secondary">{t('system.runtime.checkedAt')}: {formatTime(data.checked_at)}</Typography.Text>}
    </Space>
    {error && <Alert type="error" showIcon message={t('system.runtime.loadFailed')} />}
    {!error && data?.errors_status === 'unknown' && <Alert type="warning" showIcon message={t('system.runtime.historyUnknown')} />}
    <Space size="large" wrap>
      <Statistic title={t('system.runtime.recent')} value={historyKnown ? data?.errors_5m ?? '—' : '—'} />
      <Statistic title={t('system.runtime.retained')} value={historyKnown ? data?.events_retained ?? '—' : '—'} />
    </Space>
    {historyKnown && data?.limited && <Alert type="warning" showIcon message={t('system.runtime.limited')} />}
    <Card title={t('system.runtime.errors')}>
      <Input placeholder={t('system.runtime.filter')} value={keyword} allowClear style={{ maxWidth: 420, marginBottom: 16 }}
        onChange={(e) => { setKeyword(e.target.value); setPage(1) }} />
      <Table<RuntimeErrorGroup> rowKey="fingerprint" columns={columns} dataSource={rows} loading={isLoading}
        locale={{ emptyText: historyKnown ? (search ? t('system.runtime.noMatch') : t('system.runtime.empty')) : t('system.runtime.unknown') }}
        pagination={{ current: page, pageSize: 10, showSizeChanger: false, onChange: setPage }} scroll={{ x: 1570 }} size="small" />
    </Card>
    <Card title={t('system.runtime.schema')}>
      <Typography.Paragraph type="secondary">{t('system.runtime.schemaHint')}</Typography.Paragraph>
      {data?.schema.status === 'degraded' && !error && <Alert type="error" showIcon message={t('system.runtime.schemaDegraded')} style={{ marginBottom: 16 }} />}
      {(error || data?.schema.status === 'unknown') && <Alert type="warning" showIcon message={t('system.runtime.schemaUnknown')} style={{ marginBottom: 16 }} />}
      <Table<SchemaColumnCheck> rowKey={(r) => `${r.table}.${r.column}`} columns={schemaColumns}
        dataSource={!error ? data?.schema.checks ?? [] : []} pagination={false} loading={isLoading} scroll={{ x: 750 }} size="small" />
    </Card>
  </Space>
}
