import React, { useState, useMemo, useEffect, useRef } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Row, Col, Select, DatePicker, Button, Space, Alert, Popover, Input, Empty, Tooltip, Typography, Segmented } from 'antd'
import { ProTable, ProCard } from '@ant-design/pro-components'
import type { ProColumns } from '@ant-design/pro-components'
import { ReloadOutlined, DownloadOutlined, SettingOutlined, UpOutlined, DownOutlined, CheckOutlined, SearchOutlined, HolderOutlined, LineChartOutlined } from '@ant-design/icons'

import dayjs from 'dayjs'
import { deviceApi } from '@/services/deviceApi'
import { modelApi, type ModelFieldCapability } from '@/services/modelApi'
import { safeNum } from '@/utils/format'
import { formatInTimezone } from '@/utils/timezone'
import { humanizeFieldKey } from '@/utils/fieldI18n'
import { loadStationHistoryPrefs, saveStationHistoryPrefs } from '@/utils/stationHistoryPrefs'
import ReactECharts from '@/lib/echarts'
import useTranslation from '@/hooks/useTranslation'

const { RangePicker } = DatePicker
const { Text } = Typography

interface StationHistoryTabProps {
  stationId: number
  timezone: string
}

interface DeviceItem {
  id: string
  sn: string
  model: string
  model_id?: number
  [key: string]: any
}

/** 从 field-capabilities 响应中解包数组 */
function unwrapCaps(res: any): ModelFieldCapability[] {
  const d = res?.data?.data ?? res?.data
  return Array.isArray(d) ? d : (d?.items ?? [])
}

/** 从分页响应中解包 items/total */
function unwrapPage(res: any): { items: any[]; total: number } {
  const d = res?.data?.data ?? res?.data
  if (Array.isArray(d)) return { items: d, total: d.length }
  return { items: d?.items ?? [], total: d?.total ?? 0 }
}

/** 表格/曲线统一的数据粒度 */
type Granularity = 'raw' | 'hour' | 'day'
const GRANULARITY_OPTIONS: Granularity[] = ['raw', 'hour', 'day']
const isGranularity = (value: unknown): value is Granularity =>
  typeof value === 'string' && (GRANULARITY_OPTIONS as string[]).includes(value)

/** 曲线最多画几条（再多图例和配色都不够用） */
const MAX_CURVE_SERIES = 8
/** 曲线取点上限；配合自动粒度，长区间也不会请求上千个点 */
const MAX_CURVE_POINTS = 1000
/** 曲线配色（沿用功率趋势的色板） */
const CURVE_COLORS = ['#f59e0b', '#22c55e', '#3b82f6', '#8b5cf6', '#ef4444', '#06b6d4', '#eab308', '#ec4899']

/**
 * 按区间长度挑选曲线粒度：2 天内用原始行（≤960 点），14 天内按小时（≤336 点），
 * 更长按天。表格仍按用户选择的分辨率分页，两者互不影响。
 */
function curveGranularityFor(start?: dayjs.Dayjs, end?: dayjs.Dayjs): Granularity {
  if (!start || !end) return 'raw'
  const hours = end.diff(start, 'hour', true)
  if (hours <= 48) return 'raw'
  if (hours <= 24 * 14) return 'hour'
  return 'day'
}

/** 曲线取值：空值保留为 null，让曲线断开而不是掉到 0 */
function toCurveNum(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

/** 默认可见的数据字段：现在只作为「添加常用字段」的一键候选，页面默认不选任何字段 */
const DEFAULT_VISIBLE_FIELDS = [
  'pv_total_power', 'ac_active_power', 'battery_soc', 'battery_power', 'inverter_temperature',
]

/** 遥测行里属于元数据、不作为可选数据字段展示的键 */
const EXCLUDE_FIELDS = new Set([
  'id', 'time', 'created_at', 'updated_at', 'event_time', 'received_at',
  'protocol_version', 'sequence_no', 'quality_flags', 'topic', 'data_hash', 'raw_envelope',
  'device_sn',
])

/**
 * 旧版字段标签映射（无型号字段能力时的兜底）。
 * 仅覆盖 V1 常用字段；当设备已注册 type 字段能力表（field_capabilities）时，
 * 标签由 display_name_key + fields.* 字典动态解析，无需在此维护。
 */
const FIELD_LABEL_KEYS: Record<string, string> = {
  // ── AC 侧 ──
  ac_voltage: 'station.field_ac_voltage',
  ac_current: 'station.field_ac_current',
  ac_active_power: 'station.field_ac_active_power',
  ac_apparent_power: 'station.field_ac_apparent_power',
  ac_frequency: 'station.field_ac_frequency',
  ac_power_factor: 'station.field_ac_power_factor',
  ac_power: 'station.field_ac_power',
  load_percent: 'station.field_load_percent',
  ac_voltage_thd: 'station.field_ac_voltage_thd',

  // ── 电池 ──
  battery_soc: 'station.field_battery_soc',
  battery_soh: 'station.field_battery_soh',
  battery_voltage: 'station.field_battery_voltage',
  battery_current: 'station.field_battery_current',
  battery_power: 'station.field_battery_power',
  battery_capacity_remain: 'station.field_battery_capacity_remain',
  battery_capacity_total: 'station.field_battery_capacity_total',
  battery_cycle_count: 'station.field_battery_cycle_count',
  battery_temp_max: 'station.field_battery_temp_max',
  battery_temp_min: 'station.field_battery_temp_min',
  cell_voltage_max: 'station.field_cell_voltage_max',
  cell_voltage_min: 'station.field_cell_voltage_min',
  cell_voltage_diff: 'station.field_cell_voltage_diff',
  battery_state: 'station.field_battery_state',
  battery_protect_status: 'station.field_battery_protect_status',
  bms_fault_code: 'station.field_bms_fault_code',
  max_charge_current: 'station.field_max_charge_current',
  max_discharge_current: 'station.field_max_discharge_current',
  charge_voltage_ref: 'station.field_charge_voltage_ref',
  discharge_cutoff_voltage: 'station.field_discharge_cutoff_voltage',
  battery_temperature: 'station.field_battery_temperature',

  // ── PV ──
  pv1_voltage: 'station.field_pv1_voltage',
  pv1_current: 'station.field_pv1_current',
  pv1_power: 'station.field_pv1_power',
  pv1_voltage_max: 'station.field_pv1_voltage_max',
  pv1_power_max: 'station.field_pv1_power_max',
  pv2_voltage: 'station.field_pv2_voltage',
  pv2_current: 'station.field_pv2_current',
  pv2_power: 'station.field_pv2_power',
  pv2_voltage_max: 'station.field_pv2_voltage_max',
  pv2_power_max: 'station.field_pv2_power_max',
  pv_total_power: 'station.field_pv_total_power',
  mppt_state: 'station.field_mppt_state',

  // ── 系统 ──
  work_state: 'station.field_work_state',
  fault_code: 'station.field_fault_code',
  alarm_code: 'station.field_alarm_code',
  inverter_temperature: 'station.field_inverter_temperature',
  inverter_temp: 'station.field_inverter_temp',
  mos_temperature: 'station.field_mos_temperature',
  ambient_temperature: 'station.field_ambient_temperature',
  dc_bus_voltage: 'station.field_dc_bus_voltage',
  runtime_hours: 'station.field_runtime_hours',
  fan_speed_percent: 'station.field_fan_speed_percent',
  efficiency: 'station.field_efficiency',
  system_mode: 'station.field_system_mode',

  // ── 能量统计 ──
  daily_pv_energy: 'station.field_daily_pv',
  total_pv_energy: 'station.field_total_pv',
  daily_charge_energy: 'station.field_daily_charge',
  total_charge_energy: 'station.field_total_charge',
  daily_discharge_energy: 'station.field_daily_discharge',
  total_discharge_energy: 'station.field_total_discharge',
  daily_load_energy: 'station.field_daily_load',
  total_load_energy: 'station.field_total_load',
  total_charge_capacity: 'station.field_total_charge_capacity',
  total_discharge_capacity: 'station.field_total_discharge_capacity',
  total_charge_time: 'station.field_total_charge_time',
  total_discharge_time: 'station.field_total_discharge_time',

  // ── BMS 请求参数 ──
  charge_request_current_x10: 'station.field_charge_request_current_x10',
  charge_request_voltage_x10: 'station.field_charge_request_voltage_x10',

  // ── V2 混合/储能机扩展字段（无型号字段能力时的兜底） ──
  ac_input_power: 'station.field_ac_input_power',
  ac_input_apparent_power: 'station.field_ac_input_apparent_power',
  ac_charge_power: 'station.field_ac_charge_power',
  ac_charge_apparent_power: 'station.field_ac_charge_apparent_power',
  ac_charge_current: 'station.field_ac_charge_current',
  ac_bypass_power: 'station.field_ac_bypass_power',
  ac_bypass_apparent_power: 'station.field_ac_bypass_apparent_power',
  battery_charge_power: 'station.field_battery_charge_power',
  battery_discharge_power: 'station.field_battery_discharge_power',
  ac_charge_energy_daily: 'station.field_ac_charge_energy_daily',
  ac_charge_energy_total: 'station.field_ac_charge_energy_total',
  ac_bypass_energy_daily: 'station.field_ac_bypass_energy_daily',
  ac_bypass_energy_total: 'station.field_ac_bypass_energy_total',
  gen_energy_daily: 'station.field_gen_energy_daily',
  gen_energy_total: 'station.field_gen_energy_total',
  output_energy_daily: 'station.field_output_energy_daily',
  output_energy_total: 'station.field_output_energy_total',
  boost_temperature: 'station.field_boost_temperature',
  transformer_temperature: 'station.field_transformer_temperature',
  pv_temperature: 'station.field_pv_temperature',
  buck1_current: 'station.field_buck1_current',
  buck2_current: 'station.field_buck2_current',
  battery_overcharge: 'station.field_battery_overcharge',
  work_time_total: 'station.field_work_time_total',
  inv_current: 'station.field_inv_current',
  parallel_charge_current: 'station.field_parallel_charge_current',
  mppt_fan_speed: 'station.field_mppt_fan_speed',
  inv_fan_speed: 'station.field_inv_fan_speed',
  paired_socket: 'station.field_paired_socket',
  online_socket: 'station.field_online_socket',
  on_socket: 'station.field_on_socket',

  // ── 兼容旧字段名（部分 API / Redis 可能使用短名） ──
  daily_pv: 'station.field_daily_pv',
  daily_charge: 'station.field_daily_charge',
  daily_discharge: 'station.field_daily_discharge',
  daily_load: 'station.field_daily_load',
  total_pv: 'station.field_total_pv',
  total_charge: 'station.field_total_charge',
  total_discharge: 'station.field_total_discharge',
  total_load: 'station.field_total_load',
  soc: 'station.field_soc',
  soh: 'station.field_soh',
  charge_power: 'station.field_charge_power',
  discharge_power: 'station.field_discharge_power',
  grid_power: 'station.field_grid_power',
  grid_voltage: 'station.field_grid_voltage',
  grid_frequency: 'station.field_grid_frequency',
  meter_voltage: 'station.field_meter_voltage',
  meter_frequency: 'station.field_meter_frequency',
  load_power: 'station.field_load_power',
  total_active_power: 'station.field_total_active_power',
  run_status: 'station.field_run_status',
}

const StationHistoryTab: React.FC<StationHistoryTabProps> = ({ stationId, timezone }) => {
  const { t } = useTranslation()
  const [selectedSn, setSelectedSn] = useState<string | undefined>(undefined)
  const [dateRange, setDateRange] = useState<[dayjs.Dayjs, dayjs.Dayjs]>([
    dayjs().subtract(1, 'day'),
    dayjs(),
  ])
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [granularity, setGranularity] = useState<Granularity>('raw')
  // 默认不显示任何字段，由用户自己添加；选择结果按型号记忆
  const [visibleFields, setVisibleFields] = useState<string[]>([])
  const [fieldPickerOpen, setFieldPickerOpen] = useState(false)
  const [fieldSearch, setFieldSearch] = useState('')
  const [dragKey, setDragKey] = useState<string | null>(null)
  const [overKey, setOverKey] = useState<string | null>(null)
  const [showCurve, setShowCurve] = useState(false)
  const [refreshToken, setRefreshToken] = useState(0)
  const prefsScopeRef = useRef<string | number | undefined>(undefined)

  // 获取电站下设备列表
  const { data: devices } = useQuery({
    queryKey: ['history-devices', stationId],
    queryFn: () => deviceApi.getDevices({ station_id: stationId, page_size: 200 })
      .then(r => {
        const d = r.data?.data ?? r.data
        return d?.items ?? (Array.isArray(d) ? d : [])
      }),
    enabled: !!stationId,
  })

  // 自动选中第一台设备
  useEffect(() => {
    if (devices && devices.length > 0 && !selectedSn) {
      setSelectedSn((devices[0] as any).sn)
    }
  }, [devices, selectedSn])

  const selectedDevice = useMemo<DeviceItem | undefined>(
    () => (devices as DeviceItem[])?.find((d) => d.sn === selectedSn),
    [devices, selectedSn],
  )

  // ── 按所选设备的型号拉取字段能力表（动态、按型号）──
  const { data: fieldCaps, error: capsError } = useQuery({
    queryKey: ['history-model-field-caps', selectedDevice?.model_id],
    queryFn: () => modelApi.getFieldCapabilities(selectedDevice!.model_id!).then(unwrapCaps),
    enabled: Boolean(selectedDevice?.model_id),
    staleTime: 60_000,
  })

  const capByKey = useMemo(() => {
    const m = new Map<string, ModelFieldCapability>()
    for (const c of fieldCaps ?? []) m.set(c.field_key, c)
    return m
  }, [fieldCaps])

  // ── 统一字段标签解析 ──
  // 优先级：field_capabilities(display_name_key→fields.* → humanize) > 旧 legacy映射 > fields.* > humanize
  const resolveFieldLabel = React.useCallback((key: string): string => {
    const cap = capByKey.get(key)
    if (cap) {
      const nameKey = cap.display_name_key || `fields.${cap.field_key}`
      const name = t(nameKey)
      const label = name !== nameKey ? name : humanizeFieldKey(key)
      const unit = cap.display_unit || cap.base_unit
      return unit ? `${label} (${unit})` : label
    }
    const legacyKey = FIELD_LABEL_KEYS[key]
    if (legacyKey) return t(legacyKey)
    const fieldsKey = `fields.${key}`
    const fieldsTrans = t(fieldsKey)
    if (fieldsTrans !== fieldsKey) return fieldsTrans
    return humanizeFieldKey(key)
  }, [capByKey, t])

  // 切换设备/型号时载入该型号记忆的字段与粒度；没有记忆时保持「什么都不显示」
  const prefsScope = selectedDevice ? (selectedDevice.model_id ?? 'default') : undefined
  useEffect(() => {
    if (prefsScope === undefined || prefsScopeRef.current === prefsScope) return
    prefsScopeRef.current = prefsScope
    const prefs = loadStationHistoryPrefs(prefsScope)
    setVisibleFields(prefs.fields)
    setGranularity(isGranularity(prefs.granularity) ? prefs.granularity : 'raw')
  }, [prefsScope])

  // 字段顺序与粒度变化即记忆（同一型号下次打开自动沿用）
  useEffect(() => {
    if (prefsScopeRef.current === undefined) return
    saveStationHistoryPrefs(prefsScopeRef.current, { fields: visibleFields, granularity })
  }, [visibleFields, granularity])

  const startIso = dateRange[0]?.toISOString()
  const endIso = dateRange[1]?.toISOString()

  // 获取历史遥测数据（分页与聚合都在服务端完成，total 是区间内的真实条数/桶数）
  const { data: historyRes, isLoading } = useQuery({
    queryKey: ['station-history', selectedSn, page, pageSize, granularity, startIso, endIso, refreshToken],
    queryFn: () => deviceApi.getTelemetry(selectedSn!, {
      page,
      page_size: pageSize,
      startTime: startIso,
      endTime: endIso,
      granularity,
      tz: timezone,
      sort: 'desc',
    }).then(unwrapPage),
    enabled: !!selectedSn && !!startIso && !!endIso,
  })

  const items = useMemo(() => historyRes?.items ?? [], [historyRes])
  const total = historyRes?.total ?? 0

  // 从数据中提取所有可用字段（排除元数据字段）
  /**
   * 可选字段 = 型号字段能力表 ∪ 当前页出现过的字段。
   * 只用当前页推导会让字段列表随翻页变化（翻到别的时段就找不到字段），
   * 因此以型号能力表为主，数据里多出来的键追加在后面兜底。
   */
  const availableFields = useMemo(() => {
    const keys: string[] = []
    const seen = new Set<string>()
    const push = (key: string) => {
      if (!key || seen.has(key) || EXCLUDE_FIELDS.has(key)) return
      seen.add(key)
      keys.push(key)
    }
    for (const cap of fieldCaps ?? []) {
      if (cap.is_supported === false || cap.is_visible === false) continue
      push(cap.field_key)
    }
    for (const item of items) {
      Object.keys(item as Record<string, unknown>).forEach(push)
    }
    return keys
  }, [fieldCaps, items])

  // 「常用字段」一键候选：型号配置里标记 show_history 的字段，否则退回基础默认
  const recommendedFields = useMemo(() => {
    const fromCaps = (fieldCaps ?? [])
      .filter((f) => f.show_history && f.is_supported !== false && f.is_visible !== false)
      .map((f) => f.field_key)
    const source = fromCaps.length > 0 ? fromCaps : DEFAULT_VISIBLE_FIELDS
    const available = new Set(availableFields)
    return source.filter((key) => available.has(key))
  }, [fieldCaps, availableFields])

  // 构建表格列
  const columns: ProColumns<any>[] = useMemo(() => {
    const timeCol = {
      title: t('common.time'),
      dataIndex: 'time',
      key: 'time',
      width: 180,
      fixed: 'left' as const,
      render: (_: any, record: any) => formatInTimezone(record.time, timezone, 'YYYY-MM-DD HH:mm'),
    }
    const dataCols = visibleFields.map(field => ({
      title: resolveFieldLabel(field),
      dataIndex: field,
      key: field,
      width: 140,
      render: (_: any, record: any) => {
        const v = record[field]
        if (v === null || v === undefined || v === '') return '--'
        const n = safeNum(v)
        if (!Number.isFinite(n)) return '--'
        return n !== 0 ? n.toFixed(2) : '0.00'
      },
    }))
    return [timeCol, ...dataCols]
  }, [visibleFields, resolveFieldLabel, t, timezone])

  // ── 运行数据曲线 ──
  const curveFields = useMemo(() => visibleFields.slice(0, MAX_CURVE_SERIES), [visibleFields])
  const curveGranularity = useMemo(() => curveGranularityFor(dateRange[0], dateRange[1]), [dateRange])

  const { data: curveRes, isLoading: curveLoading } = useQuery({
    queryKey: ['station-history-curve', selectedSn, curveGranularity, startIso, endIso, curveFields.join(','), refreshToken],
    queryFn: () => deviceApi.getTelemetry(selectedSn!, {
      page: 1,
      page_size: MAX_CURVE_POINTS,
      startTime: startIso,
      endTime: endIso,
      granularity: curveGranularity,
      tz: timezone,
      fields: curveFields.join(','),
      sort: 'asc',
    }).then(unwrapPage),
    enabled: showCurve && !!selectedSn && !!startIso && !!endIso && curveFields.length > 0,
  })

  const curveRows = useMemo(() => curveRes?.items ?? [], [curveRes])

  const curveOption = useMemo(() => {
    if (curveRows.length === 0) return null
    const timeFormat = curveGranularity === 'day' ? 'YYYY-MM-DD' : 'MM-DD HH:mm'
    const times = curveRows.map((row: any) => formatInTimezone(row.time, timezone, timeFormat))
    const series = curveFields.flatMap((field, index) => {
      const data = curveRows.map((row: any) => toCurveNum(row[field]))
      // 该字段在区间内没有任何读数时不画，避免出现一条全空的图例
      if (!data.some((value) => value !== null)) return []
      const color = CURVE_COLORS[index % CURVE_COLORS.length]
      return [{
        name: resolveFieldLabel(field),
        type: 'line' as const,
        smooth: true,
        symbol: 'none',
        connectNulls: true,
        data,
        lineStyle: { color, width: 2 },
        itemStyle: { color },
      }]
    })
    if (series.length === 0) return null
    return {
      tooltip: {
        trigger: 'axis' as const,
        axisPointer: { type: 'cross' as const },
        formatter: (params: any) => {
          const list = Array.isArray(params) ? params : [params]
          let html = `<div style="font-weight:600;margin-bottom:4px">${list[0]?.axisValue ?? ''}</div>`
          list.forEach((p: any) => {
            if (p.value === null || p.value === undefined) return
            html += `<div>${p.marker} ${p.seriesName}: ${Number(p.value).toFixed(2)}</div>`
          })
          return html
        },
      },
      legend: { type: 'scroll' as const, top: 0, itemGap: 16, data: series.map((s) => s.name) },
      grid: { left: '3%', right: '4%', bottom: '14%', top: 45, containLabel: true },
      xAxis: { type: 'category' as const, data: times, axisLabel: { fontSize: 11, hideOverlap: true } },
      yAxis: { type: 'value' as const, axisLabel: { fontSize: 11 } },
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        { type: 'slider', start: 0, end: 100, height: 20, bottom: 8 },
      ],
      series,
    }
  }, [curveRows, curveFields, curveGranularity, resolveFieldLabel, timezone])

  // 点击卡片切换显示：未选→追加到末尾；已选→移除
  const toggleField = React.useCallback((key: string) => {
    setVisibleFields(prev => (prev.includes(key) ? prev.filter(k => k !== key) : [...prev, key]))
  }, [])

  // 上移/下移：调整显示顺序
  const moveField = React.useCallback((index: number, dir: -1 | 1) => {
    setVisibleFields(prev => {
      const next = [...prev]
      const target = index + dir
      if (target < 0 || target >= next.length) return prev
      ;[next[index], next[target]] = [next[target], next[index]]
      return next
    })
  }, [])

  // ── 分组定义：小标题复用已有 station.* 双语 key ──
  const GROUP_META: { id: string; labelKey: string; test: (k: string) => boolean }[] = [
    { id: 'pv', labelKey: 'station.pvParams', test: (k) => /^(pv|mppt)/i.test(k) },
    { id: 'bat', labelKey: 'station.batteryParams', test: (k) => /^(batt|bat|bms|cell|soc|soh|overcharge)/i.test(k) || /^battery_/i.test(k) },
    { id: 'ac', labelKey: 'station.acParams', test: (k) => /^(ac|grid|meter|load|output|feed|charge|bypass)/i.test(k) },
    { id: 'sys', labelKey: 'station.systemStatus', test: (k) => /^(work_|inv_|fan_|temp_|effic|runtime|fault|alarm|sys|boost|transform|transform|buck|paired|online_socket|on_socket|dc_bus|mos_|ambient|parallel_charge)/i.test(k) },
    { id: 'eng', labelKey: 'station.energyStats', test: (k) => /(energy|daily_|total_|gen_)/i.test(k) },
    { id: 'other', labelKey: 'mon.other', test: () => true },
  ]
  const fieldGroupOf = (key: string): string => {
    const cap = capByKey.get(key)
    if (cap?.group_code) {
      const g = cap.group_code.toLowerCase()
      if (['pv', 'mppt'].includes(g)) return 'pv'
      if (['bat', 'battery'].includes(g)) return 'bat'
      if (['ac'].includes(g)) return 'ac'
      if (['sys', 'diag', 'system'].includes(g)) return 'sys'
      if (['eng', 'energy'].includes(g)) return 'eng'
    }
    for (const m of GROUP_META) {
      if (m.id !== 'other' && m.test(key)) return m.id
    }
    return 'other'
  }
  const GROUP_ORDER = ['pv', 'bat', 'ac', 'sys', 'eng', 'other']
  const groupLabel = (id: string) => t(GROUP_META.find((g) => g.id === id)!.labelKey)

  // 拖拽排序：把 fromKey 移动到 toKey 所在位置（drop 到目标卡片前）
  const reorderField = (fromKey: string, toKey: string) => {
    setVisibleFields(prev => {
      if (!fromKey || fromKey === toKey) return prev
      const arr = [...prev]
      const from = arr.indexOf(fromKey)
      if (from < 0) return prev
      arr.splice(from, 1)
      const to = arr.indexOf(toKey)
      arr.splice(to, 0, fromKey)
      return arr
    })
  }

  // 卡片式字段选择面板：搜索 + 已选列表（可调顺序）+ 未选卡片网格
  const renderFieldPicker = () => {
    const kw = fieldSearch.trim().toLowerCase()
    const filtered = kw
      ? availableFields.filter(k => resolveFieldLabel(k).toLowerCase().includes(kw) || k.toLowerCase().includes(kw))
      : availableFields
    const selectedKeys = filtered.filter(k => visibleFields.includes(k))
    const unselectedKeys = filtered.filter(k => !visibleFields.includes(k))
    return (
      <div style={{ width: 520, padding: 4 }}>
        <Input
          allowClear
          prefix={<SearchOutlined />}
          placeholder={t('station.fieldSearchPlaceholder')}
          value={fieldSearch}
          onChange={(e) => setFieldSearch(e.target.value)}
          style={{ marginBottom: 12 }}
        />
        <Space style={{ marginBottom: 12 }}>
          <Button
            size="small"
            disabled={recommendedFields.length === 0}
            onClick={() => setVisibleFields(recommendedFields)}
          >
            {t('station.addRecommendedFields')}
          </Button>
          <Button size="small" disabled={visibleFields.length === 0} onClick={() => setVisibleFields([])}>
            {t('station.clearFields')}
          </Button>
        </Space>
        <div style={{ maxHeight: 400, overflowY: 'auto', paddingRight: 4 }}>
          {selectedKeys.length > 0 && (
            <div style={{ marginBottom: 12 }}>
              <Text style={{ fontSize: 12, fontWeight: 600, color: '#666' }}>{t('station.fieldSelected', { count: visibleFields.length })}</Text>
              <div style={{ marginTop: 8 }}>
                {selectedKeys.map((key) => {
                  const vIdx = visibleFields.indexOf(key)
                  const isOver = overKey === key
                  return (
                    <div
                      key={key}
                      draggable
                      data-field-key={key}
                      onDragStart={(e) => { setDragKey(key); e.dataTransfer.effectAllowed = 'move' }}
                      onDragOver={(e) => { e.preventDefault(); setOverKey(key) }}
                      onDrop={(e) => { e.preventDefault(); setOverKey(null); reorderField(dragKey!, key) }}
                      onDragEnd={() => { setDragKey(null); setOverKey(null) }}
                      style={{
                        display: 'flex', alignItems: 'center', gap: 6, marginBottom: 6, padding: '5px 8px',
                        border: isOver ? '1px dashed #1677ff' : '1px solid #1677ff',
                        borderRadius: 8, background: isOver ? '#f0f7ff' : '#e6f4ff',
                        cursor: dragKey === key ? 'grabbing' : 'pointer',
                      }}
                      onClick={() => toggleField(key)}
                    >
                      <HolderOutlined style={{ color: '#91caff', cursor: 'grab' }} onClick={(e) => e.stopPropagation()} />
                      <Tooltip title={t('station.fieldMoveUp')}>
                        <Button size="small" type="text" icon={<UpOutlined />} disabled={vIdx === 0} onClick={(e) => { e.stopPropagation(); moveField(vIdx, -1) }} />
                      </Tooltip>
                      <Tooltip title={t('station.fieldMoveDown')}>
                        <Button size="small" type="text" icon={<DownOutlined />} disabled={vIdx === visibleFields.length - 1} onClick={(e) => { e.stopPropagation(); moveField(vIdx, 1) }} />
                      </Tooltip>
                      <CheckOutlined style={{ color: '#1677ff' }} onClick={(e) => e.stopPropagation()} />
                      <Text style={{ flex: 1, fontSize: 13 }}>{resolveFieldLabel(key)}</Text>
                    </div>
                  )
                })}              </div>
            </div>
          )}
          {unselectedKeys.length > 0 && (
            <div>
              <Text style={{ fontSize: 12, fontWeight: 600, color: '#666' }}>{t('station.fieldUnselected')}</Text>
              <div style={{ marginTop: 8 }}>
                {GROUP_ORDER.map((gid) => {
                  const gFields = unselectedKeys.filter((k) => fieldGroupOf(k) === gid)
                  if (gFields.length === 0) return null
                  return (
                    <div key={gid} style={{ marginBottom: 14 }}>
                      <Text style={{ fontSize: 12, color: '#8c8c8c', fontWeight: 600, display: 'block', marginBottom: 6 }}>
                        {groupLabel(gid)}
                      </Text>
                      <Row gutter={[8, 8]}>
                        {gFields.map((key) => (
                          <Col span={12} key={key}>
                            <div
                              data-field-key={key}
                              style={{
                                padding: '8px 10px', border: '1px solid #d9d9d9', borderRadius: 8, cursor: 'pointer',
                                background: '#fff', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                              }}
                              onClick={() => toggleField(key)}
                            >
                              <Text style={{ fontSize: 13 }}>{resolveFieldLabel(key)}</Text>
                            </div>
                          </Col>
                        ))}
                      </Row>
                    </div>
                  )
                })}
              </div>
            </div>
          )}
          {filtered.length === 0 && (
            <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t('common.noData')} style={{ padding: '16px 0' }} />
          )}
        </div>
      </div>
    )
  }

  // 导出
  const handleExport = async (format: 'csv' | 'excel') => {
    if (!selectedSn || !dateRange[0] || !dateRange[1]) return
    try {
      const res = await deviceApi.exportTelemetry(selectedSn, format, {
        startTime: dateRange[0].toISOString(),
        endTime: dateRange[1].toISOString(),
      })
      const blob = res.data as Blob
      const url = window.URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = url
      const ext = format === 'excel' ? 'xlsx' : 'csv'
      link.download = `${selectedSn}_history_${Date.now()}.${ext}`
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)
      window.URL.revokeObjectURL(url)
    } catch {
      /* silent */
    }
  }

  return (
    <>
      {/* 工具栏 */}
      <ProCard style={{ borderRadius: 12, marginBottom: 16 }}>
        <Row gutter={[12, 12]} align="middle">
          <Col>
            <Select
              placeholder={t('station.selectDevice')}
              value={selectedSn}
              onChange={(v) => { setSelectedSn(v); setPage(1) }}
              style={{ minWidth: 220 }}
              options={(devices || []).map((d: any) => ({
                label: `${d.sn} (${d.model || '-'})`,
                value: d.sn,
              }))}
            />
          </Col>
          <Col>
            <RangePicker
              value={dateRange}
              onChange={(dates) => {
                if (dates && dates[0] && dates[1]) {
                  setDateRange([dates[0], dates[1]])
                  setPage(1)
                }
              }}
              presets={[
                { label: t('station.recent7Days'), value: [dayjs().subtract(7, 'day'), dayjs()] },
                { label: t('station.recent30Days'), value: [dayjs().subtract(30, 'day'), dayjs()] },
              ]}
            />
          </Col>
          <Col>
            <Button icon={<ReloadOutlined />} onClick={() => { setPage(1); setRefreshToken(n => n + 1) }}>
              {t('station.query')}
            </Button>
          </Col>
          <Col>
            <Space>
              <Button icon={<DownloadOutlined />} onClick={() => handleExport('csv')}>
                {t('station.exportCSV')}
              </Button>
              <Button icon={<DownloadOutlined />} onClick={() => handleExport('excel')}>
                {t('station.exportExcel')}
              </Button>
            </Space>
          </Col>
        </Row>

        <Row gutter={[12, 12]} align="middle" style={{ marginTop: 12 }}>
          <Col>
            <Space size={8}>
              <Text type="secondary" style={{ fontSize: 12 }}>{t('station.granularity')}</Text>
              <Segmented
                value={granularity}
                onChange={(value) => { setGranularity(value as Granularity); setPage(1) }}
                options={[
                  { label: t('station.granularityRaw'), value: 'raw' },
                  { label: t('station.granularityHour'), value: 'hour' },
                  { label: t('station.granularityDay'), value: 'day' },
                ]}
              />
            </Space>
          </Col>
          <Col>
            <Tooltip title={t('station.curveHint', { count: MAX_CURVE_SERIES })}>
              <Button
                icon={<LineChartOutlined />}
                type={showCurve ? 'primary' : 'default'}
                disabled={visibleFields.length === 0}
                onClick={() => setShowCurve(v => !v)}
              >
                {showCurve ? t('station.hideCurve') : t('station.showCurve')}
              </Button>
            </Tooltip>
          </Col>
          <Col flex="auto">
            <Text type="secondary" style={{ fontSize: 12 }}>{t('station.granularityHint')}</Text>
          </Col>
        </Row>

        {capsError && selectedDevice?.model_id && (
          <Alert
            type="warning"
            showIcon
            style={{ marginTop: 12 }}
            message={t('station.fieldCapsLoadFailed')}
          />
        )}

        {/* 字段选择器（卡片式） */}
        {availableFields.length > 0 && (
          <Row style={{ marginTop: 12 }} align="middle">
            <Col>
              <Popover
                trigger="click"
                open={fieldPickerOpen}
                onOpenChange={setFieldPickerOpen}
                placement="bottomLeft"
                content={renderFieldPicker}
                destroyTooltipOnHide
              >
                <Button icon={<SettingOutlined />}>
                  {t('station.selectFields')} ({visibleFields.length})
                </Button>
              </Popover>
            </Col>
            <Col style={{ marginLeft: 12 }}>
              <Text type="secondary" style={{ fontSize: 12 }}>{t('station.fieldPickerHint')}</Text>
            </Col>
          </Row>
        )}
      </ProCard>

      {/* 运行数据曲线 */}
      {showCurve && (
        <ProCard
          title={<Space><LineChartOutlined style={{ color: '#1677ff' }} /><span>{t('station.runningCurve')}</span></Space>}
          style={{ borderRadius: 12, marginBottom: 16 }}
          extra={
            <Text type="secondary" style={{ fontSize: 12 }}>
              {t('station.curveResolution', {
                value: t(curveGranularity === 'raw' ? 'station.granularityRaw'
                  : curveGranularity === 'hour' ? 'station.granularityHour' : 'station.granularityDay'),
              })}
            </Text>
          }
        >
          {visibleFields.length > MAX_CURVE_SERIES && (
            <Alert
              type="info"
              showIcon
              style={{ marginBottom: 12 }}
              message={t('station.curveTooManyFields', { selected: visibleFields.length, count: MAX_CURVE_SERIES })}
            />
          )}
          {curveLoading && <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t('common.loading')} style={{ padding: '32px 0' }} />}
          {!curveLoading && curveOption && (
            <ReactECharts option={curveOption} style={{ height: 340, width: '100%' }} notMerge />
          )}
          {!curveLoading && !curveOption && (
            <Empty
              image={Empty.PRESENTED_IMAGE_SIMPLE}
              description={
                // 有数据却画不出线 = 所选字段都不是数值；没有数据才是空区间
                curveFields.length === 0 || curveRows.length > 0
                  ? t('station.curveNoNumericFields')
                  : t('common.noData')
              }
              style={{ padding: '32px 0' }}
            />
          )}
        </ProCard>
      )}

      {/* 数据表格 */}
      <ProCard style={{ borderRadius: 12 }}>
        {visibleFields.length === 0 ? (
          <Empty
            image={Empty.PRESENTED_IMAGE_SIMPLE}
            description={
              <Space direction="vertical" size={4}>
                <Text strong>{t('station.historyNoFields')}</Text>
                <Text type="secondary" style={{ fontSize: 12 }}>{t('station.historyNoFieldsHint')}</Text>
                <Text type="secondary" style={{ fontSize: 12 }}>
                  {t('common.total', { total })}
                </Text>
              </Space>
            }
            style={{ padding: '32px 0' }}
          >
            <Space>
              <Button
                type="primary"
                icon={<SettingOutlined />}
                disabled={availableFields.length === 0}
                onClick={() => setFieldPickerOpen(true)}
              >
                {t('station.selectFields')}
              </Button>
              <Button
                disabled={recommendedFields.length === 0}
                onClick={() => setVisibleFields(recommendedFields)}
              >
                {t('station.addRecommendedFields')}
              </Button>
            </Space>
          </Empty>
        ) : (
          <>
            <div style={{ marginBottom: 8 }}>
              <Text type="secondary" style={{ fontSize: 12 }}>{t('common.total', { total })}</Text>
            </div>
            <ProTable
              columns={columns}
              dataSource={items}
              loading={isLoading}
              rowKey={(r: any) => `${r.time ?? ''}|${r.data_hash ?? ''}`}
              search={false}
              options={{ density: true, reload: false, setting: true }}
              pagination={{
                current: page,
                pageSize,
                total,
                showSizeChanger: true,
                pageSizeOptions: ['10', '20', '50', '100'],
                onChange: (p, ps) => { setPage(p); setPageSize(ps) },
              }}
              scroll={{ x: 1200 }}
              size="small"
            />
          </>
        )}
      </ProCard>
    </>
  )
}

export default StationHistoryTab
