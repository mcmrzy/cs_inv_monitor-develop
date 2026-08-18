/**
 * 实时数据（安装商视角）
 *
 * 默认只展示 PV / 电池 / 逆变器 三组精选字段（用户友好视图）；
 * 全量 field_capabilities 参数表收进「全部参数」折叠区供调试，
 * 位掩码字段（sys_status/warning/bms_warning）显示十六进制 + 激活位徽标。
 * 底部保留配置快照 ProTable。
 */
import { useQuery } from '@tanstack/react-query'
import { Statistic, Tag, Spin, Empty, Typography, Space, Card, Row, Col, Alert, Collapse } from 'antd'
import { ProCard, ProTable } from '@ant-design/pro-components'
import type { ProColumns } from '@ant-design/pro-components'
import { CheckCircleFilled, CloseCircleFilled, SunOutlined, ThunderboltOutlined, DashboardOutlined } from '@ant-design/icons'

import { deviceApi } from '@/services/deviceApi'
import { toRtEnvelope, freshRealtime, extractEnergyMetrics, parseSysStatusBits, type SysStatusBits } from './energyUtils'
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

// 分组标题（field_capabilities.group_code，用于「全部参数」折叠区）
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

/** 数值格式化：null 显示 '--'，否则按 decimals 保留小数 */
function num(v: number | null | undefined, decimals = 1): string {
  return v == null ? '--' : v.toFixed(decimals)
}

/** 位掩码激活位徽标（sys_status 展开 12 位；warning/bms_warning 仅提示非 0） */
const BitmaskBadges: React.FC<{ fieldKey: string; value: number }> = ({ fieldKey, value }) => {
  const { t } = useTranslation()
  if (fieldKey === 'sys_status') {
    const bits: SysStatusBits | null = parseSysStatusBits(value)
    if (!bits) return null
    const activeKeys = (Object.keys(bits) as (keyof SysStatusBits)[]).filter((k) => bits[k])
    return (
      <span style={{ marginLeft: 8 }}>
        {activeKeys.length === 0 && <Tag>{t('deviceDetail.realtime.noActiveBits')}</Tag>}
        {activeKeys.map((k) => (
          <Tag key={k} color="blue" style={{ borderRadius: 6 }}>{t(`deviceDetail.bits.${k}`)}</Tag>
        ))}
      </span>
    )
  }
  return value !== 0 ? <Tag color="orange" style={{ marginLeft: 8 }}>{t('deviceDetail.realtime.bitsActive')}</Tag> : null
}

const StatusTab: React.FC<StatusTabProps> = ({ sn }) => {
  const { t, lang } = useTranslation()
  const { timezone } = useTimezoneStore()

  const { data: controlState, isLoading: stateLoading, error: stateError, refetch: refetchState } = useQuery({
    queryKey: queryKeys.devices.controlState(sn),
    queryFn: () => deviceApi.getControlState(sn).then((r) => r.data?.data ?? null),
    refetchInterval: 15000,
  })

  const { data: envelope, isLoading: rtLoading, error: realtimeError, refetch: refetchRealtime } = useQuery({
    queryKey: queryKeys.devices.realtime(sn),
    queryFn: () => deviceApi.getRealtime(sn).then((r) => toRtEnvelope(r.data?.data ?? r.data)),
    refetchInterval: () => (document.visibilityState === 'visible' ? 10_000 : false),
  })

  const { data: deviceInfo, error: deviceError, refetch: refetchDevice } = useQuery({
    queryKey: queryKeys.devices.detail(sn),
    queryFn: () => deviceApi.getDeviceBySn(sn).then((r) => r.data?.data ?? null),
  })

  // 按型号字段能力动态渲染全量参数（收进「全部参数」折叠区）
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

  const isOnline = deviceInfo?.status === 'online' || envelope?.online === true
  const reported = controlState?.reported ?? {}
  // 展平字段在 envelope.realtime 内层；离线/数据过期时不展示陈旧缓存值
  const rtFresh = freshRealtime(envelope)
  const rtData = (rtFresh ?? {}) as Record<string, any>
  const m = extractEnergyMetrics(rtFresh)
  const fresh = rtFresh != null

  const batterySoc = rtData.battery_soc ?? rtData.soc ?? reported.battery_soc ?? '-'
  const workMode = rtData.work_mode ?? reported.work_mode ?? '-'

  // ══ 精选三组（PV / 电池 / 逆变器）══
  const battCharging = fresh && m.battPower > 5
  const battDischarging = fresh && m.battPower < -5
  const curatedGroups = [
    {
      key: 'pv',
      icon: <SunOutlined style={{ color: '#F59E0B' }} />,
      title: t('deviceDetail.realtime.groupPv'),
      color: '#F59E0B',
      fields: [
        { label: t('deviceDetail.realtime.pv1Voltage'), value: fresh ? num(m.pv1Voltage) : '--', suffix: 'V' },
        { label: t('deviceDetail.realtime.pv2Voltage'), value: fresh ? num(m.pv2Voltage) : '--', suffix: 'V' },
        { label: t('deviceDetail.realtime.pvPower'), value: fresh ? Math.round(m.pvPower).toString() : '--', suffix: 'W' },
      ],
    },
    {
      key: 'battery',
      icon: <DashboardOutlined style={{ color: '#00E676' }} />,
      title: t('deviceDetail.realtime.groupBattery'),
      color: '#00E676',
      fields: [
        { label: t('deviceDetail.realtime.battVoltage'), value: fresh ? num(m.battVoltage, 2) : '--', suffix: 'V' },
        { label: 'SOC', value: fresh ? Math.round(m.battSoc).toString() : '--', suffix: '%' },
        { label: t('deviceDetail.realtime.chargeCurrent'), value: fresh ? num(battCharging ? m.battCurrent : 0) : '--', suffix: 'A' },
        { label: t('deviceDetail.realtime.dischargeCurrent'), value: fresh ? num(battDischarging ? Math.abs(m.battCurrent ?? 0) : 0) : '--', suffix: 'A' },
      ],
    },
    {
      key: 'inverter',
      icon: <ThunderboltOutlined style={{ color: '#8B5CF6' }} />,
      title: t('deviceDetail.realtime.groupInverter'),
      color: '#8B5CF6',
      fields: [
        { label: t('deviceDetail.realtime.inverterTemp'), value: fresh ? num(m.inverterTemp) : '--', suffix: '℃' },
        { label: t('deviceDetail.realtime.busVoltage'), value: fresh ? num(m.dcBusVoltage) : '--', suffix: 'V' },
        { label: t('deviceDetail.realtime.loadRatio'), value: fresh ? num(m.loadPercent, 0) : '--', suffix: '%' },
        { label: t('deviceDetail.realtime.efficiency'), value: fresh ? num(m.efficiency) : '--', suffix: '%' },
      ],
    },
  ]

  // ══ 全量参数（field_capabilities 动态渲染，收进折叠区）══
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

  const isBitmaskField = (f: ModelFieldCapability) => BITMASK_FIELDS.has(f.field_key) || f.field_type === 'bitmask'

  const formatFieldValue = (f: ModelFieldCapability, raw: unknown): string => {
    if (raw === undefined || raw === null || raw === '') return '-'
    const numVal = Number(raw)
    if (Number.isNaN(numVal)) return String(raw)
    if (isBitmaskField(f)) {
      return `0x${numVal.toString(16).toUpperCase()}`
    }
    const decimals = f.decimal_places ?? (Number.isInteger(numVal) ? 0 : 2)
    return numVal.toFixed(decimals)
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
      {envelope && rtFresh == null && (
        <Alert
          type="warning"
          showIcon
          message={t('deviceDetail.status.staleData')}
          style={{ marginBottom: 16, borderRadius: 12 }}
        />
      )}

      {/* ── 顶部摘要 ── */}
      <ProCard gutter={16} style={{ marginBottom: 16 }}>
        <ProCard colSpan={8} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Space>
            {statusIcon(isOnline)}
            <span>{t('deviceDetail.status.onlineStatus')}</span>
          </Space>
          <div style={{ marginTop: 8 }}>
            <Tag color={isOnline ? 'green' : 'red'}>{isOnline ? t('admin.connected') : t('admin.disconnected')}</Tag>
          </div>
        </ProCard>
        <ProCard colSpan={8} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Statistic title={t('deviceDetail.status.workMode')} value={workMode} />
        </ProCard>
        <ProCard colSpan={8} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Statistic title={t('deviceDetail.status.batterySoc')} value={batterySoc} suffix={typeof batterySoc === 'number' ? '%' : ''} />
          {controlState?.reported_at && (
            <div style={{ color: '#999', fontSize: 12, marginTop: 4 }}>
              {t('deviceDetail.status.reportedAt')}: {formatInTimezone(controlState.reported_at, timezone, 'YYYY-MM-DD HH:mm:ss')}
            </div>
          )}
        </ProCard>
      </ProCard>

      {/* ── 精选三组：PV / 电池 / 逆变器 ── */}
      <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
        {curatedGroups.map((g) => (
          <Col xs={24} lg={8} key={g.key}>
            <Card
              size="small"
              title={
                <span style={{ fontSize: 14, fontWeight: 600 }}>
                  {g.icon} <span style={{ marginLeft: 6 }}>{g.title}</span>
                </span>
              }
              style={{ borderRadius: 12, height: '100%', boxShadow: '0 1px 4px rgba(0,0,0,0.06)' }}
            >
              <Row gutter={[16, 12]}>
                {g.fields.map((f) => (
                  <Col span={12} key={f.label}>
                    <Statistic
                      title={f.label}
                      value={f.value}
                      suffix={f.value !== '--' ? f.suffix : undefined}
                      valueStyle={{ fontSize: 18, color: f.value !== '--' ? '#1f2937' : '#9ca3af' }}
                    />
                  </Col>
                ))}
              </Row>
            </Card>
          </Col>
        ))}
      </Row>

      {/* ── 全部参数（调试用，默认收起）── */}
      {hasDynamic && (
        <Collapse
          size="small"
          style={{ marginBottom: 16, borderRadius: 12, background: '#fff' }}
          items={[{
            key: 'all-params',
            label: <span style={{ fontWeight: 600 }}>{t('deviceDetail.realtime.allParams')}</span>,
            children: (
              <>
                {dynamicGroups.map((g) => (
                  <Card
                    key={g.code}
                    size="small"
                    title={<span style={{ fontSize: 13, fontWeight: 600 }}>{groupTitle(g.code)}</span>}
                    style={{ borderRadius: 12, marginBottom: 12, boxShadow: '0 1px 4px rgba(0,0,0,0.06)' }}
                  >
                    <Row gutter={[16, 12]}>
                      {g.fields.map((f) => {
                        const raw = resolveRtValue(rtData, f.field_key)
                        const value = formatFieldValue(f, raw)
                        const suffix = fieldSuffix(f)
                        const bitmask = isBitmaskField(f)
                        return (
                          <Col xs={12} md={8} xl={6} key={f.field_key}>
                            <Statistic
                              title={fieldLabel(f)}
                              value={value}
                              suffix={suffix && value !== '-' ? suffix : undefined}
                              valueStyle={{ fontSize: 16, color: raw !== undefined && raw !== null ? '#1f2937' : '#9ca3af' }}
                            />
                            {bitmask && raw !== undefined && raw !== null && Number(raw) !== 0 && (
                              <BitmaskBadges fieldKey={f.field_key} value={Number(raw)} />
                            )}
                          </Col>
                        )
                      })}
                    </Row>
                  </Card>
                ))}
              </>
            ),
          }]}
        />
      )}

      {/* ── 配置快照 ── */}
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
