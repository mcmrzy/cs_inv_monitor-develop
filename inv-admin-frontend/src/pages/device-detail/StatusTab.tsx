import { useQuery } from '@tanstack/react-query'
import { Statistic, Tag, Spin, Empty, Typography, Space, Card, Row, Col } from 'antd'
import { ProCard, ProTable } from '@ant-design/pro-components'
import type { ProColumns } from '@ant-design/pro-components'
import { CheckCircleFilled, CloseCircleFilled } from '@ant-design/icons'

import { deviceApi } from '@/services/deviceApi'
import { modelApi, type ModelFieldCapability } from '@/services/modelApi'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'

const { Text } = Typography

interface StatusTabProps {
  sn: string
}

// 分组中文标题（field_capabilities.group_code）
const GROUP_TITLES_ZH: Record<string, string> = {
  sys: '系统',
  pv: 'PV',
  ac: 'AC',
  bat: '电池',
  eng: '能量',
}

const GROUP_TITLES_EN: Record<string, string> = {
  sys: 'System',
  pv: 'PV',
  ac: 'AC',
  bat: 'Battery',
  eng: 'Energy',
}

// realtime 展平后的候选 key（兼容 V1 last_valid 旧 key 与 V2 协议字段名）
const RT_KEY_FALLBACK: Record<string, string[]> = {
  battery_voltage: ['battery_voltage', 'voltage'],
  battery_soc: ['battery_soc', 'soc'],
  battery_current: ['battery_current', 'current'],
  battery_power: ['battery_power', 'power'],
  battery_charge_power: ['battery_charge_power', 'charge_power'],
  battery_discharge_power: ['battery_discharge_power', 'discharge_power'],
  battery_overcharge: ['battery_overcharge', 'overcharge'],
  ac_voltage: ['ac_voltage', 'output_voltage'],
  ac_frequency: ['ac_frequency', 'output_frequency'],
  ac_active_power: ['ac_active_power', 'output_power'],
  ac_apparent_power: ['ac_apparent_power', 'output_apparent_power'],
  ac_current: ['ac_current', 'output_current'],
  pv_total_power: ['pv_total_power', 'total_power'],
}

const BITMASK_FIELDS = new Set(['sys_status', 'warning', 'bms_warning'])

function resolveRtValue(rt: Record<string, any>, fieldKey: string): unknown {
  if (rt[fieldKey] !== undefined && rt[fieldKey] !== null) return rt[fieldKey]
  const candidates = RT_KEY_FALLBACK[fieldKey] ?? []
  for (const k of candidates) {
    if (rt[k] !== undefined && rt[k] !== null) return rt[k]
  }
  return undefined
}

const StatusTab: React.FC<StatusTabProps> = ({ sn }) => {
  const { t, lang } = useTranslation()
  const { timezone } = useTimezoneStore()

  const { data: controlState, isLoading: stateLoading, error: stateError, refetch: refetchState } = useQuery({
    queryKey: queryKeys.devices.controlState(sn),
    queryFn: () => deviceApi.getControlState(sn).then((r) => r.data?.data ?? null),
    refetchInterval: 15000,
  })

  const { data: realtime, isLoading: rtLoading, error: realtimeError, refetch: refetchRealtime } = useQuery({
    queryKey: queryKeys.devices.realtime(sn),
    queryFn: () => deviceApi.getRealtime(sn).then((r) => r.data?.data ?? null),
    refetchInterval: 10000,
  })

  const { data: deviceInfo, error: deviceError, refetch: refetchDevice } = useQuery({
    queryKey: queryKeys.devices.detail(sn),
    queryFn: () => deviceApi.getDeviceBySn(sn).then((r) => r.data?.data ?? null),
  })

  // 按型号字段能力动态渲染实时数据（show_realtime + is_visible）
  const { data: fieldCaps } = useQuery({
    queryKey: ['model-field-caps', deviceInfo?.model_id],
    queryFn: () =>
      modelApi.getFieldCapabilities(deviceInfo.model_id).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (Array.isArray(d) ? d : d?.items ?? []) as ModelFieldCapability[]
      }),
    enabled: Boolean(deviceInfo?.model_id),
    staleTime: 60_000,
  })

  const isOnline = deviceInfo?.status === 'online'
  const reported = controlState?.reported ?? {}
  const rtData = (realtime ?? {}) as Record<string, any>

  // Extract power-related fields from realtime data
  const powerOutput = rtData.output_power ?? rtData.power_output ?? rtData.ac_active_power ?? '-'
  const powerInput = rtData.input_power ?? rtData.power_input ?? rtData.ac_input_power ?? '-'
  const loadPower = rtData.load_power ?? '-'
  const batterySoc = rtData.battery_soc ?? rtData.soc ?? reported.battery_soc ?? '-'
  const workMode = rtData.work_mode ?? reported.work_mode ?? '-'

  // 动态字段：show_realtime 且 is_visible，按 group_code 分组
  const dynamicGroups = (() => {
    const caps = fieldCaps ?? []
    const visible = caps.filter((f) => f.show_realtime && f.is_supported !== false && f.is_visible !== false)
    const groups: { code: string; fields: ModelFieldCapability[] }[] = []
    const order = ['sys', 'pv', 'ac', 'bat', 'eng', 'system', 'battery', 'energy']
    const byGroup = new Map<string, ModelFieldCapability[]>()
    for (const f of visible) {
      const g = f.group_code || 'other'
      if (!byGroup.has(g)) byGroup.set(g, [])
      byGroup.get(g)!.push(f)
    }
    const sortedCodes = [...byGroup.keys()].sort((a, b) => {
      const ia = order.indexOf(a)
      const ib = order.indexOf(b)
      return (ia === -1 ? 999 : ia) - (ib === -1 ? 999 : ib)
    })
    for (const code of sortedCodes) {
      const fields = byGroup.get(code)!.sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0))
      groups.push({ code, fields })
    }
    return groups
  })()
  const hasDynamic = dynamicGroups.length > 0

  const groupTitle = (code: string) => {
    const zh = GROUP_TITLES_ZH[code] ?? code
    return lang === 'en' ? GROUP_TITLES_EN[code] ?? code : zh
  }

  const fieldLabel = (f: ModelFieldCapability) => {
    const key = f.display_name_key || `fields.${f.field_key}`
    const translated = t(key)
    return translated !== key ? translated : f.field_key
  }

  const formatFieldValue = (f: ModelFieldCapability, raw: unknown): string => {
    if (raw === undefined || raw === null || raw === '') return '-'
    const num = Number(raw)
    if (Number.isNaN(num)) return String(raw)
    if (BITMASK_FIELDS.has(f.field_key) || f.field_type === 'bitmask') {
      return `0x${num.toString(16).toUpperCase()}`
    }
    const decimals = f.decimal_places ?? (Number.isInteger(num) ? 0 : 2)
    return num.toFixed(decimals)
  }

  const fieldSuffix = (f: ModelFieldCapability) => f.display_unit || f.base_unit || undefined

  const statusIcon = (ok: boolean) => ok
    ? <CheckCircleFilled style={{ color: '#52c41a', fontSize: 18 }} />
    : <CloseCircleFilled style={{ color: '#ff4d4f', fontSize: 18 }} />

  const snapshotColumns: ProColumns<{ key: string; desired: string; reported: string }>[] = [
    { title: 'Key', dataIndex: 'key', key: 'key', width: 180, render: (_, record) => <Text code>{record.key}</Text> },
    { title: t('deviceDetail.diagnostics.desired'), dataIndex: 'desired', key: 'desired', render: (_, record) => record.desired || '-' },
    { title: t('deviceDetail.diagnostics.reported'), dataIndex: 'reported', key: 'reported', render: (_, record) => record.reported || '-' },
  ]

  const allKeys = Array.from(new Set([
    ...Object.keys(controlState?.desired ?? {}),
    ...Object.keys(controlState?.reported ?? {}),
  ])).sort()

  const snapshotData = allKeys.map((key) => ({
    key,
    desired: String(controlState?.desired?.[key] ?? ''),
    reported: String(controlState?.reported?.[key] ?? ''),
  }))

  return (
    <Spin spinning={stateLoading || rtLoading}>
      {(stateError || realtimeError || deviceError) && (
        <QueryErrorAlert
          error={stateError || realtimeError || deviceError}
          onRetry={() => {
            void (stateError ? refetchState() : realtimeError ? refetchRealtime() : refetchDevice())
          }}
          style={{ marginBottom: 16 }}
        />
      )}
      <ProCard gutter={16} style={{ marginBottom: 16 }}>
        <ProCard colSpan={6} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Space>
            {statusIcon(isOnline)}
            <span>{t('deviceDetail.status.onlineStatus')}</span>
          </Space>
          <div style={{ marginTop: 8 }}>
            <Tag color={isOnline ? 'green' : 'red'}>{isOnline ? t('admin.connected') : t('admin.disconnected')}</Tag>
          </div>
        </ProCard>
        <ProCard colSpan={6} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Statistic title={t('deviceDetail.status.workMode')} value={workMode} />
        </ProCard>
        <ProCard colSpan={6} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Statistic title={t('deviceDetail.status.batterySoc')} value={batterySoc} suffix={typeof batterySoc === 'number' ? '%' : ''} />
        </ProCard>
        <ProCard colSpan={6} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Statistic title={t('deviceDetail.status.syncStatus')} value={controlState?.sync_status ?? '-'} />
          {controlState?.reported_at && (
            <div style={{ color: '#999', fontSize: 12, marginTop: 4 }}>
              {t('deviceDetail.status.reportedAt')}: {formatInTimezone(controlState.reported_at, timezone, 'YYYY-MM-DD HH:mm:ss')}
            </div>
          )}
        </ProCard>
      </ProCard>

      {hasDynamic ? (
        // 按模型字段能力动态渲染（CS-L10-6K2 等 V2 型号）
        dynamicGroups.map((g) => (
          <Card
            key={g.code}
            size="small"
            title={<span style={{ fontSize: 14, fontWeight: 600 }}>{groupTitle(g.code)}</span>}
            style={{ borderRadius: 12, marginBottom: 16, boxShadow: '0 1px 4px rgba(0,0,0,0.06)' }}
          >
            <Row gutter={[16, 12]}>
              {g.fields.map((f) => {
                const raw = resolveRtValue(rtData, f.field_key)
                const value = formatFieldValue(f, raw)
                const suffix = fieldSuffix(f)
                return (
                  <Col xs={12} md={8} xl={6} key={f.field_key}>
                    <Statistic
                      title={fieldLabel(f)}
                      value={value}
                      suffix={suffix && value !== '-' ? suffix : undefined}
                      valueStyle={{ fontSize: 18, color: raw !== undefined && raw !== null ? '#1f2937' : '#9ca3af' }}
                    />
                  </Col>
                )
              })}
            </Row>
          </Card>
        ))
      ) : (
        // 旧型号回退：功率卡片
        <ProCard gutter={16} style={{ marginBottom: 16 }}>
          <ProCard colSpan={8} size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('deviceDetail.status.powerOutput')} value={powerOutput} suffix="W" />
          </ProCard>
          <ProCard colSpan={8} size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('deviceDetail.status.powerInput')} value={powerInput} suffix="W" />
          </ProCard>
          <ProCard colSpan={8} size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('deviceDetail.status.loadPower')} value={loadPower} suffix="W" />
          </ProCard>
        </ProCard>
      )}

      <ProCard
        title={t('deviceDetail.diagnostics.configSnapshot')}
        size="small"
        bordered={false}
        style={{ borderRadius: 12 }}
      >
        {snapshotData.length > 0 ? (
          <ProTable
            rowKey="key"
            columns={snapshotColumns}
            dataSource={snapshotData}
            size="small"
            search={false}
            options={{ density: true, reload: false, setting: true }}
            pagination={false}
            scroll={{ y: 300 }}
          />
        ) : (
          <Empty description={t('deviceDetail.status.noData')} />
        )}
      </ProCard>
    </Spin>
  )
}

export default StatusTab
