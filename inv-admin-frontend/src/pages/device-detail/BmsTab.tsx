/**
 * 储能 BMS 页（BmsTab）
 *
 * 数据源：
 *  - 实时：GET /devices/by-sn/:sn/realtime 的 bms 组（储能BMS PC485 链路，45 字段，见
 *    docs/design/储能BMS遥测扩展协议设计.md §7.7）；bms 组缺失或 bms_online=0 → 空态。
 *  - 历史曲线：GET /devices/by-sn/:sn/telemetry 的逆变器侧电池列（battery_soc/voltage/current/power）。
 *
 * 布局（对标主流逆变器/储能监控的电池详情页）：
 *  状态行 → SOC/SOH 双环 + 核心指标 → 容量与请求 → 电芯电压柱状图 → 温度与 MOS
 *  → BMS 告警/故障解码面板 → 24h 历史曲线。
 */
import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Row, Col, Progress, Spin, Tag, Typography, Empty, Tooltip, Segmented, Descriptions } from 'antd'
import { ProCard } from '@ant-design/pro-components'
import {
  ThunderboltOutlined, WarningOutlined, CheckCircleOutlined,
  ThunderboltFilled, ApiOutlined,
} from '@ant-design/icons'
import dayjs from 'dayjs'

import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import { safeNum } from '@/utils/format'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import ReactECharts from '@/lib/echarts'
import {
  toRtEnvelope, isRealtimeFresh, freshRealtime, extractEnergyMetrics,
  parseRtTimestamp, ENERGY_COLORS,
} from './energyUtils'

const { Text } = Typography

interface BmsTabProps {
  sn: string
}

const CARD_SHADOW = '0 2px 8px rgba(17,24,39,0.06)'

/* ═══════════ BMS 数据提取 ═══════════ */

interface BmsData {
  online: boolean
  soc: number | null
  soh: number | null
  remainCap: number | null
  fullCap: number | null
  designCap: number | null
  cycle: number | null
  vMax: number | null
  vMin: number | null
  vDiff: number | null
  vMaxIdx: number | null
  vMinIdx: number | null
  tMax: number | null
  tMin: number | null
  mosTemp: number | null
  envTemp: number | null
  pcbTemp: number | null
  workMode: number | null
  mosStatus: number | null
  chgReqCur: number | null
  chgReqVolt: number | null
  fault: number | null
  alarms: [number, number, number]
  totalChg: number | null
  totalDsg: number | null
  cells: (number | null)[]
  balance: number
}

/** 从 realtime.bms 组提取 BMS 数据；组缺失返回 null（未接电池/旧固件） */
function extractBms(rt: Record<string, any> | null | undefined): BmsData | null {
  const g = rt?.bms?.data
  if (g == null || typeof g !== 'object') return null
  const num = (k: string): number | null => {
    const v = g[k]
    return v == null || v === '' ? null : safeNum(v)
  }
  const cells = Array.from({ length: 16 }, (_, i) =>
    num(`bms_cell_voltage_${String(i).padStart(2, '0')}`))
  return {
    online: num('bms_online') === 1,
    soc: num('bms_soc'),
    soh: num('bms_soh'),
    remainCap: num('bms_capacity_remain'),
    fullCap: num('bms_capacity_full'),
    designCap: num('bms_capacity_design'),
    cycle: num('bms_cycle_count'),
    vMax: num('bms_cell_voltage_max'),
    vMin: num('bms_cell_voltage_min'),
    vDiff: num('bms_cell_voltage_diff'),
    vMaxIdx: num('bms_cell_voltage_max_index'),
    vMinIdx: num('bms_cell_voltage_min_index'),
    tMax: num('bms_cell_temp_max'),
    tMin: num('bms_cell_temp_min'),
    mosTemp: num('bms_mos_temp'),
    envTemp: num('bms_env_temp'),
    pcbTemp: num('bms_pcb_temp'),
    workMode: num('bms_battery_work_mode'),
    mosStatus: num('bms_mos_status'),
    chgReqCur: num('bms_chg_request_current'),
    chgReqVolt: num('bms_chg_request_voltage'),
    fault: num('bms_fault_status'),
    alarms: [num('bms_alarm_w0') ?? 0, num('bms_alarm_w1') ?? 0, num('bms_alarm_w2') ?? 0],
    totalChg: num('bms_total_chg_capacity'),
    totalDsg: num('bms_total_dsg_capacity'),
    cells,
    balance: num('bms_balance_bitmap') ?? 0,
  }
}

/* ═══════════ 告警/故障位定义（来源：BMS 固件枚举 + ARM 映射，见设计文档 §7.4/§7.7）═══════════ */

/** 告警等级字 w0/w1/w2：每类告警 2bit（0 无 / 1~3 级） */
const BMS_ALARM_DEFS: Array<{ word: 0 | 1 | 2; bit: number; key: string }> = [
  { word: 0, bit: 0, key: 'cellOv' },
  { word: 0, bit: 1, key: 'packOv' },
  { word: 0, bit: 2, key: 'chgOc' },
  { word: 0, bit: 3, key: 'chgOt' },
  { word: 0, bit: 4, key: 'chgUt' },
  { word: 0, bit: 5, key: 'cellUv' },
  { word: 0, bit: 6, key: 'packUv' },
  { word: 0, bit: 7, key: 'dsgOc' },
  { word: 1, bit: 0, key: 'dsgOt' },
  { word: 1, bit: 1, key: 'dsgUt' },
  { word: 1, bit: 2, key: 'socLow' },
  { word: 1, bit: 3, key: 'envOt' },
  { word: 1, bit: 4, key: 'envUt' },
  { word: 1, bit: 5, key: 'pcbOt' },
  { word: 1, bit: 6, key: 'pcbUt' },
  { word: 1, bit: 7, key: 'mosOt' },
  { word: 2, bit: 0, key: 'mosUt' },
  { word: 2, bit: 1, key: 'dv' },
  { word: 2, bit: 2, key: 'dt' },
]

/** 故障位图主要位（bit 定义以 BMS 手册为准，此处覆盖固件已确认位） */
const BMS_FAULT_DEFS: Array<{ bit: number; key: string }> = [
  { bit: 0, key: 'sc' },
  { bit: 1, key: 'reverse' },
  { bit: 2, key: 'ntcBreak' },
  { bit: 3, key: 'wireBreak' },
  { bit: 4, key: 'afeComm' },
  { bit: 5, key: 'chgMosFault' },
  { bit: 6, key: 'dsgMosFault' },
  { bit: 7, key: 'fanLow' },
  { bit: 8, key: 'fanStall' },
  { bit: 24, key: 'lock' },
]

/* ═══════════ 小组件 ═══════════ */

const KvRow: React.FC<{ label: string; value: React.ReactNode }> = ({ label, value }) => (
  <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6, fontSize: 12 }}>
    <span style={{ color: '#6b7280' }}>{label}</span>
    <span style={{ color: ENERGY_COLORS.dark, fontWeight: 600 }}>{value}</span>
  </div>
)

const Gauge: React.FC<{
  percent: number; label: string; sub: string; size?: number; color?: string | Record<string, string>;
}> = ({ percent, label, sub, size = 128, color }) => (
  <Progress
    type="dashboard"
    size={size}
    percent={Math.max(0, Math.min(100, Math.round(percent)))}
    strokeColor={color ?? { '0%': ENERGY_COLORS.smartBlue, '100%': ENERGY_COLORS.energyGreen }}
    format={(p) => (
      <div>
        <div style={{ fontSize: size >= 120 ? 26 : 18, fontWeight: 700, color: ENERGY_COLORS.dark }}>{p}%</div>
        <div style={{ fontSize: 11, color: '#9ca3af' }}>{label}</div>
        <div style={{ fontSize: 10, color: '#c4c7cd' }}>{sub}</div>
      </div>
    )}
  />
)

const TempCard: React.FC<{ label: string; value: number | null; icon: string }> = ({ label, value, icon }) => {
  const color = value == null ? '#9ca3af'
    : value >= 55 ? '#ef4444' : value >= 45 ? '#F59E0B' : value <= 0 ? '#3b82f6' : '#22c55e'
  return (
    <div style={{ background: '#f9fafb', borderRadius: 10, padding: '10px 12px', textAlign: 'center' }}>
      <div style={{ fontSize: 12, color: '#6b7280' }}>{icon} {label}</div>
      <div style={{ fontSize: 18, fontWeight: 700, color, marginTop: 2 }}>
        {value != null ? `${value.toFixed(1)}°C` : '--'}
      </div>
    </div>
  )
}

/* ═══════════ 主组件 ═══════════ */

const BmsTab: React.FC<BmsTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const [historyRange, setHistoryRange] = useState<'24h' | '7d'>('24h')

  const { data: envelope, isLoading, error, refetch } = useQuery({
    queryKey: queryKeys.devices.realtime(sn),
    queryFn: () => deviceApi.getRealtime(sn).then((r) => toRtEnvelope(r.data?.data ?? r.data)),
    refetchInterval: () => (document.visibilityState === 'visible' ? 10_000 : false),
  })

  const fresh = isRealtimeFresh(envelope)
  const rt = freshRealtime(envelope)
  const bms = extractBms(rt)
  const m = extractEnergyMetrics(rt)

  // 24h/7d 历史曲线（逆变器侧电池列；bms 字段历史待 device_telemetry 落库后接入）
  const { data: historyRows, isLoading: historyLoading } = useQuery({
    queryKey: ['device-bms-history', sn, historyRange],
    queryFn: async () => {
      const end = dayjs().tz(timezone)
      const start = historyRange === '24h' ? end.subtract(24, 'hour') : end.subtract(7, 'day')
      const res = await deviceApi.getTelemetry(sn, {
        startTime: start.toISOString(),
        endTime: end.toISOString(),
        granularity: historyRange === '24h' ? 'hour' : 'day',
        page_size: 500,
      })
      const d = res.data?.data ?? res.data ?? {}
      return Array.isArray(d) ? d : (d?.items ?? d?.list ?? [])
    },
    staleTime: 5 * 60_000,
  })

  /* 告警解码：等级 > 0 的告警列表 */
  const activeAlarms = useMemo(() => {
    if (!bms) return []
    return BMS_ALARM_DEFS
      .map(({ word, bit, key }) => ({ key, level: (bms.alarms[word] >> (bit * 2)) & 0x3 }))
      .filter((a) => a.level > 0)
  }, [bms])

  const activeFaults = useMemo(() => {
    if (!bms || bms.fault == null) return []
    return BMS_FAULT_DEFS.filter((f) => ((bms.fault! >> f.bit) & 1) === 1)
  }, [bms])

  /* 电芯电压柱状图：max 红 / min 蓝 / 均衡中橙框，其余绿色渐变 */
  const cellChartOption = useMemo(() => {
    if (!bms) return null
    const valid = bms.cells.filter((v): v is number => v != null && v > 0)
    if (valid.length === 0) return null
    const vMax = bms.vMax ?? Math.max(...valid)
    const vMin = bms.vMin ?? Math.min(...valid)
    return {
      tooltip: {
        trigger: 'axis' as const,
        axisPointer: { type: 'shadow' as const },
        formatter: (params: any) => {
          const p = Array.isArray(params) ? params[0] : params
          const idx = p.dataIndex
          const bal = ((bms.balance >> idx) & 1) === 1
          return `<b>${t('deviceDetail.bms.cell')} ${idx + 1}</b><br/>${p.value} mV` +
            (bal ? `<br/>⚡ ${t('deviceDetail.bms.balancing')}` : '')
        },
      },
      grid: { left: '2%', right: '2%', bottom: '8%', top: 30, containLabel: true },
      xAxis: {
        type: 'category' as const,
        data: bms.cells.map((_, i) => `${i + 1}`),
        axisLabel: { fontSize: 11 },
        name: t('deviceDetail.bms.cellNo'),
        nameTextStyle: { fontSize: 11 },
      },
      yAxis: {
        type: 'value' as const,
        scale: true,
        axisLabel: { fontSize: 11 },
        name: 'mV',
        nameTextStyle: { fontSize: 11 },
      },
      series: [{
        type: 'bar' as const,
        barMaxWidth: 26,
        data: bms.cells.map((v, i) => {
          if (v == null || v <= 0) return { value: 0, itemStyle: { color: '#e5e7eb' } }
          const isMax = vMax > 0 && Math.abs(v - vMax) < 0.5
          const isMin = vMin > 0 && Math.abs(v - vMin) < 0.5
          const balancing = ((bms.balance >> i) & 1) === 1
          return {
            value: v,
            itemStyle: {
              color: isMax ? '#ef4444' : isMin ? '#3b82f6' : '#22c55e',
              borderRadius: [4, 4, 0, 0],
              borderColor: balancing ? '#F59E0B' : 'transparent',
              borderWidth: balancing ? 2 : 0,
            },
          }
        }),
        markLine: {
          silent: true,
          symbol: 'none',
          lineStyle: { type: 'dashed' as const, color: '#9ca3af' },
          label: { formatter: '{c} mV', fontSize: 10 },
          data: [{ type: 'average' as const, name: 'avg' }],
        },
      }],
    }
  }, [bms, t])

  /* 历史曲线：SOC / 电压 / 电流 / 功率 */
  const historyOption = useMemo(() => {
    const rows = historyRows ?? []
    if (rows.length === 0) return null
    const fmt = historyRange === '24h' ? 'HH:mm' : 'MM-DD'
    const labels = rows.map((r: any) => {
      const ts = r?.time ?? r?.event_time
      const d = dayjs(ts)
      return d.isValid() ? d.format(fmt) : ''
    })
    const pick = (r: any, keys: string[]): number | null => {
      for (const k of keys) {
        const v = r?.[k]
        if (v != null && Number.isFinite(Number(v))) return Number(v)
      }
      return null
    }
    const series = [
      { name: 'SOC', unit: '%', color: '#22c55e', yAxis: 0, get: (r: any) => pick(r, ['battery_soc']) },
      { name: t('deviceDetail.bms.voltage'), unit: 'V', color: '#3b82f6', yAxis: 0, get: (r: any) => pick(r, ['battery_voltage']) },
      { name: t('deviceDetail.bms.current'), unit: 'A', color: '#F59E0B', yAxis: 1, get: (r: any) => pick(r, ['battery_current']) },
      { name: t('deviceDetail.bms.power'), unit: 'kW', color: '#8B5CF6', yAxis: 1, get: (r: any) => { const v = pick(r, ['battery_power']); return v != null ? v / 1000 : null } },
    ]
    return {
      tooltip: { trigger: 'axis' as const },
      legend: { data: series.map((s) => s.name), top: 0, itemGap: 16 },
      grid: { left: '3%', right: '4%', bottom: '8%', top: 40, containLabel: true },
      xAxis: { type: 'category' as const, data: labels, axisLabel: { fontSize: 11 } },
      yAxis: [
        { type: 'value' as const, name: '% / V', scale: true, axisLabel: { fontSize: 11 } },
        { type: 'value' as const, name: 'A / kW', scale: true, splitLine: { show: false }, axisLabel: { fontSize: 11 } },
      ],
      series: series.map((s) => ({
        name: s.name,
        type: 'line' as const,
        yAxisIndex: s.yAxis,
        data: rows.map((r: any) => s.get(r)),
        showSymbol: false,
        lineStyle: { width: 2, color: s.color },
        itemStyle: { color: s.color },
        connectNulls: true,
      })),
    }
  }, [historyRows, historyRange, t])

  /* 工作模式文案（BMS 口径枚举） */
  const workModeCfg = useMemo(() => {
    const modes: Record<number, { label: string; color: string }> = {
      0: { label: t('deviceDetail.bms.modeIdle'), color: '#9ca3af' },
      1: { label: t('deviceDetail.bms.modeChg'), color: ENERGY_COLORS.energyGreen },
      2: { label: t('deviceDetail.bms.modeDsg'), color: '#F59E0B' },
      3: { label: t('deviceDetail.bms.modeInit'), color: '#3b82f6' },
      4: { label: t('deviceDetail.bms.modeBackChg'), color: '#8B5CF6' },
    }
    return bms?.workMode != null ? modes[bms.workMode] ?? modes[0] : null
  }, [bms, t])

  /* ═══════════ 渲染 ═══════════ */

  if (error) {
    return <QueryErrorAlert error={error} onRetry={() => void refetch()} />
  }

  const loading = isLoading

  /* 空态 1：设备离线/数据过期 */
  if (!loading && !fresh) {
    const lastTs = parseRtTimestamp(envelope?.dataTime)
    return (
      <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW }} bodyStyle={{ padding: '64px 24px' }}>
        <Empty
          image={Empty.PRESENTED_IMAGE_SIMPLE}
          description={
            <div>
              <div style={{ fontSize: 15, fontWeight: 600, color: ENERGY_COLORS.dark }}>
                {t('deviceDetail.bms.offlineTitle')}
              </div>
              <Text type="secondary" style={{ display: 'block', marginTop: 6 }}>
                {t('deviceDetail.bms.offlineEmpty')}
              </Text>
              {Number.isFinite(lastTs) && (
                <Text type="secondary" style={{ display: 'block', marginTop: 4, fontSize: 12 }}>
                  {t('deviceDetail.energy.lastDataTime')}: {formatInTimezone(new Date(lastTs).toISOString(), timezone, 'YYYY-MM-DD HH:mm:ss')}
                </Text>
              )}
            </div>
          }
        />
      </ProCard>
    )
  }

  /* 空态 2：在线但无 BMS 组（未接储能电池 / 旧固件） */
  if (!bms) {
    return (
      <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW }} bodyStyle={{ padding: '64px 24px' }}>
        <Empty
          image={Empty.PRESENTED_IMAGE_SIMPLE}
          description={
            <div>
              <div style={{ fontSize: 15, fontWeight: 600, color: ENERGY_COLORS.dark }}>
                {t('deviceDetail.bms.notConnectedTitle')}
              </div>
              <Text type="secondary" style={{ display: 'block', marginTop: 6 }}>
                {t('deviceDetail.bms.notConnectedEmpty')}
              </Text>
            </div>
          }
        />
      </ProCard>
    )
  }

  /* 空态 3：BMS 组在但 bms_online=0（接了电池但通讯离线） */
  if (!bms.online) {
    return (
      <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW }} bodyStyle={{ padding: '64px 24px' }}>
        <Empty
          image={Empty.PRESENTED_IMAGE_SIMPLE}
          description={
            <div>
              <WarningOutlined style={{ fontSize: 28, color: '#F59E0B' }} />
              <div style={{ fontSize: 15, fontWeight: 600, color: ENERGY_COLORS.dark, marginTop: 8 }}>
                {t('deviceDetail.bms.bmsOfflineTitle')}
              </div>
              <Text type="secondary" style={{ display: 'block', marginTop: 6 }}>
                {t('deviceDetail.bms.bmsOfflineEmpty')}
              </Text>
            </div>
          }
        />
      </ProCard>
    )
  }

  const soc = bms.soc ?? 0
  const soh = bms.soh
  const capPct = bms.designCap != null && bms.designCap > 0 && bms.remainCap != null
    ? Math.min(100, (bms.remainCap / bms.designCap) * 100) : null
  const balancingCount = bms.cells.reduce<number>((acc, v, i) =>
    acc + (((bms.balance >> i) & 1) === 1 && v != null && v > 0 ? 1 : 0), 0)
  const lastTs = parseRtTimestamp(envelope?.dataTime)

  return (
    <Spin spinning={loading}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        {/* ── 状态行 ── */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <Tag icon={<CheckCircleOutlined />} color="success" style={{ borderRadius: 8 }}>
            {t('deviceDetail.bms.bmsOnline')}
          </Tag>
          {workModeCfg && (
            <Tag color={workModeCfg.color} style={{ borderRadius: 8, fontWeight: 600 }}>
              {workModeCfg.label}
            </Tag>
          )}
          {(bms.vDiff ?? 0) > 50 && (
            <Tag color="warning" style={{ borderRadius: 8 }}>
              {t('deviceDetail.bms.diffHigh')}: {bms.vDiff} mV
            </Tag>
          )}
          {Number.isFinite(lastTs) && (
            <Text type="secondary" style={{ fontSize: 12, marginLeft: 'auto' }}>
              {t('deviceDetail.energy.lastDataTime')}: {formatInTimezone(new Date(lastTs).toISOString(), timezone, 'YYYY-MM-DD HH:mm:ss')}
            </Text>
          )}
        </div>

        {/* ── SOC / SOH 双环 + 核心指标 ── */}
        <Row gutter={[16, 16]}>
          <Col xs={24} md={8}>
            <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW, height: '100%' }} bodyStyle={{ display: 'flex', alignItems: 'center', justifyContent: 'space-around', padding: 20 }}>
              <Gauge
                percent={soc}
                label="SOC"
                sub={workModeCfg?.label ?? ''}
                size={148}
                color={soc <= 15 ? { '0%': '#f97316', '100%': '#ef4444' } : { '0%': ENERGY_COLORS.smartBlue, '100%': ENERGY_COLORS.energyGreen }}
              />
              {soh != null && (
                <Gauge
                  percent={soh}
                  label="SOH"
                  sub={t('deviceDetail.bms.health')}
                  size={96}
                color={soh != null && soh < 80 ? { '0%': '#F59E0B', '100%': '#ef4444' } : { '0%': '#8B5CF6', '100%': ENERGY_COLORS.smartBlue }}
                />
              )}
            </ProCard>
          </Col>
          <Col xs={24} md={16}>
            <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW, height: '100%' }} bodyStyle={{ padding: 20 }}>
              <Row gutter={[12, 12]}>
                {[
                  { label: t('deviceDetail.bms.packVoltage'), value: m.battVoltage != null ? `${m.battVoltage.toFixed(2)} V` : '--', sub: 'BatVolt' },
                  { label: t('deviceDetail.bms.current'), value: m.battCurrent != null ? `${m.battCurrent.toFixed(1)} A` : '--', sub: t('deviceDetail.bms.chgPositive') },
                  { label: t('deviceDetail.bms.chargePower'), value: m.batteryChargePower != null ? `${(m.batteryChargePower / 1000).toFixed(2)} kW` : '--', sub: t('deviceDetail.bms.charging') },
                  { label: t('deviceDetail.bms.dischargePower'), value: m.batteryDischargePower != null ? `${(m.batteryDischargePower / 1000).toFixed(2)} kW` : '--', sub: t('deviceDetail.bms.discharging') },
                ].map((it) => (
                  <Col xs={12} md={6} key={it.label}>
                    <div style={{ background: '#f9fafb', borderRadius: 10, padding: '12px 14px' }}>
                      <div style={{ fontSize: 12, color: '#6b7280' }}>{it.label}</div>
                      <div style={{ fontSize: 20, fontWeight: 700, color: ENERGY_COLORS.dark, marginTop: 2 }}>{it.value}</div>
                      <div style={{ fontSize: 10, color: '#c4c7cd', marginTop: 2 }}>{it.sub}</div>
                    </div>
                  </Col>
                ))}
              </Row>
              <div style={{ marginTop: 12 }}>
                <KvRow label={t('deviceDetail.bms.remainCapacity')}
                       value={bms.remainCap != null ? `${bms.remainCap.toFixed(1)} Ah` : '--'} />
                <div style={{ marginTop: 4 }}>
                  <Progress
                    percent={capPct != null ? Math.round(capPct) : 0}
                    showInfo={false}
                    size="small"
                    strokeColor={{ '0%': ENERGY_COLORS.smartBlue, '100%': ENERGY_COLORS.energyGreen }}
                  />
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, color: '#9ca3af' }}>
                    <span>0</span>
                    <span>{bms.fullCap != null ? `${bms.fullCap.toFixed(1)} Ah (FCC)` : '--'}</span>
                  </div>
                </div>
              </div>
            </ProCard>
          </Col>
        </Row>

        {/* ── 电芯电压柱状图 ── */}
        <ProCard
          style={{ borderRadius: 12, boxShadow: CARD_SHADOW }}
          title={
            <span style={{ fontWeight: 600 }}>
              <ThunderboltOutlined style={{ color: ENERGY_COLORS.energyGreen, marginRight: 6 }} />
              {t('deviceDetail.bms.cellVoltages')}
              {bms.vDiff != null && (
                <Tag style={{ marginLeft: 10, borderRadius: 8 }} color={bms.vDiff > 50 ? 'orange' : 'default'}>
                  Δ {bms.vDiff} mV
                </Tag>
              )}
            </span>
          }
          extra={
            <span style={{ fontSize: 12, color: '#6b7280' }}>
              <span style={{ color: '#ef4444' }}>■</span> {t('deviceDetail.bms.max')}
              <span style={{ color: '#3b82f6', marginLeft: 8 }}>■</span> {t('deviceDetail.bms.min')}
              <span style={{ color: '#F59E0B', marginLeft: 8 }}>▣</span> {t('deviceDetail.bms.balancing')}
              {balancingCount > 0 && ` (${balancingCount})`}
            </span>
          }
          size="small"
        >
          {cellChartOption ? (
            <ReactECharts option={cellChartOption} notMerge style={{ height: 260 }} />
          ) : (
            <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t('deviceDetail.bms.noCellData')} />
          )}
        </ProCard>

        {/* ── 温度 + MOS/均衡状态 ── */}
        <Row gutter={[16, 16]}>
          <Col xs={24} md={14}>
            <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW, height: '100%' }}
                     title={<span style={{ fontWeight: 600 }}>🌡️ {t('deviceDetail.bms.temperatures')}</span>} size="small">
              <Row gutter={[8, 8]}>
                <Col xs={8} md={4}><TempCard label={t('deviceDetail.bms.tempMax')} value={bms.tMax} icon="🔺" /></Col>
                <Col xs={8} md={4}><TempCard label={t('deviceDetail.bms.tempMin')} value={bms.tMin} icon="🔻" /></Col>
                <Col xs={8} md={4}><TempCard label="MOS" value={bms.mosTemp} icon="🔧" /></Col>
                <Col xs={8} md={4}><TempCard label={t('deviceDetail.bms.tempEnv')} value={bms.envTemp} icon="🌍" /></Col>
                <Col xs={8} md={4}><TempCard label="PCB" value={bms.pcbTemp} icon="💾" /></Col>
              </Row>
            </ProCard>
          </Col>
          <Col xs={24} md={10}>
            <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW, height: '100%' }}
                     title={<span style={{ fontWeight: 600 }}><ApiOutlined style={{ marginRight: 6 }} />{t('deviceDetail.bms.switchStatus')}</span>} size="small">
              <Descriptions size="small" column={1}>
                <Descriptions.Item label={t('deviceDetail.bms.chargeMos')}>
                  {bms.mosStatus != null && (bms.mosStatus & 0x01)
                    ? <Tag color="green" style={{ borderRadius: 8 }}>{t('deviceDetail.bms.on')}</Tag>
                    : <Tag style={{ borderRadius: 8 }}>{t('deviceDetail.bms.off')}</Tag>}
                </Descriptions.Item>
                <Descriptions.Item label={t('deviceDetail.bms.dischargeMos')}>
                  {bms.mosStatus != null && (bms.mosStatus & 0x02)
                    ? <Tag color="green" style={{ borderRadius: 8 }}>{t('deviceDetail.bms.on')}</Tag>
                    : <Tag style={{ borderRadius: 8 }}>{t('deviceDetail.bms.off')}</Tag>}
                </Descriptions.Item>
                <Descriptions.Item label={t('deviceDetail.bms.balancingCells')}>
                  {balancingCount > 0
                    ? <Tag color="orange" style={{ borderRadius: 8 }}>⚡ {balancingCount}</Tag>
                    : <Tag style={{ borderRadius: 8 }}>0</Tag>}
                </Descriptions.Item>
                <Descriptions.Item label={t('deviceDetail.bms.chargeRequest')}>
                  {bms.chgReqCur != null ? `${bms.chgReqCur.toFixed(1)} A` : '--'} / {bms.chgReqVolt != null ? `${bms.chgReqVolt.toFixed(1)} V` : '--'}
                </Descriptions.Item>
                <Descriptions.Item label={t('deviceDetail.bms.cycleCount')}>
                  {bms.cycle ?? '--'}
                </Descriptions.Item>
              </Descriptions>
            </ProCard>
          </Col>
        </Row>

        {/* ── 告警 / 故障面板 ── */}
        <ProCard
          style={{ borderRadius: 12, boxShadow: CARD_SHADOW }}
          title={<span style={{ fontWeight: 600 }}><WarningOutlined style={{ color: '#F59E0B', marginRight: 6 }} />{t('deviceDetail.bms.alarmPanel')}</span>}
          size="small"
        >
          {activeAlarms.length === 0 && activeFaults.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '16px 0', color: '#22c55e' }}>
              <CheckCircleOutlined style={{ fontSize: 20, marginRight: 6 }} />
              {t('deviceDetail.bms.noAlarms')}
            </div>
          ) : (
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {activeFaults.map((f) => (
                <Tooltip key={`f${f.bit}`} title={`${t('deviceDetail.bms.faultBit')} ${f.bit}`}>
                  <Tag icon={<ThunderboltFilled />} color="error" style={{ borderRadius: 8, fontWeight: 600 }}>
                    {t(`deviceDetail.bms.fault.${f.key}`)}
                  </Tag>
                </Tooltip>
              ))}
              {activeAlarms.map((a) => (
                <Tooltip key={a.key} title={`${t('deviceDetail.bms.alarmLevel')} ${a.level}`}>
                  <Tag color={a.level >= 3 ? 'volcano' : a.level === 2 ? 'orange' : 'gold'} style={{ borderRadius: 8 }}>
                    {t(`deviceDetail.bms.alarm.${a.key}`)} · L{a.level}
                  </Tag>
                </Tooltip>
              ))}
            </div>
          )}
          <div style={{ marginTop: 10, display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
            <Text type="secondary" style={{ fontSize: 11 }}>
              {t('deviceDetail.bms.totalCapacityTip')}: {bms.totalChg != null ? `${bms.totalChg.toFixed(0)} Ah` : '--'} / {bms.totalDsg != null ? `${bms.totalDsg.toFixed(0)} Ah` : '--'}
            </Text>
            <Text type="secondary" style={{ fontSize: 11 }}>
              {t('deviceDetail.bms.rawBitmaps')}: fault={bms.fault ?? '--'} alarm=[{bms.alarms.join(', ')}]
            </Text>
          </div>
        </ProCard>

        {/* ── 历史曲线 ── */}
        <ProCard
          style={{ borderRadius: 12, boxShadow: CARD_SHADOW }}
          title={<span style={{ fontWeight: 600 }}>📈 {t('deviceDetail.bms.historyTitle')}</span>}
          extra={
            <Segmented
              size="small"
              value={historyRange}
              onChange={(v) => setHistoryRange(v as '24h' | '7d')}
              options={[
                { label: t('deviceDetail.bms.h24'), value: '24h' },
                { label: t('deviceDetail.bms.d7'), value: '7d' },
              ]}
            />
          }
          size="small"
        >
          {historyOption ? (
            <ReactECharts option={historyOption} notMerge style={{ height: 300 }} />
          ) : (
            <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t('deviceDetail.bms.noHistory')} />
          )}
          {historyLoading && <Spin size="small" style={{ position: 'absolute', top: 60, right: 32 }} />}
        </ProCard>
      </div>
    </Spin>
  )
}

export default BmsTab
