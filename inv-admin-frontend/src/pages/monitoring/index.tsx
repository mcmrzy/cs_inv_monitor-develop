import { useState, useMemo, useCallback, useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Row, Col, Card, Statistic, Table, Select, DatePicker, Button, Tabs, Tag,
  Typography, Space, Spin, Empty, Grid, Badge, Segmented, Timeline, Modal, Checkbox,
} from 'antd'
import {
  DashboardOutlined, ThunderboltOutlined, LineChartOutlined,
  TableOutlined, ReloadOutlined, ExperimentOutlined, AlertOutlined,
  EnvironmentOutlined, SwapOutlined, CloudOutlined,
  RiseOutlined, FallOutlined, BulbOutlined, FieldTimeOutlined,
  DownloadOutlined, ApartmentOutlined, BarChartOutlined, FilterOutlined,
} from '@ant-design/icons'
import ReactECharts from 'echarts-for-react'
import dayjs from 'dayjs'
import api from '@/services/api'
import { deviceApi } from '@/services/deviceApi'
import { dashboardApi } from '@/services/dashboardApi'
import { alertApi } from '@/services/alertApi'
import { DEVICE_STATUS_MAP, ALARM_LEVEL_MAP, CHART_COLORS, HERO_GRADIENTS, getAlarmLevelDisplay } from '@/utils/constants'
import { safeNum, fmt } from '@/utils/format'
import useTranslation from '@/hooks/useTranslation'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import { useModelFields } from '@/components/dyna/useModelFields'
import type { DeviceModelFieldItem } from '@/services/modelApi'
import type { ColumnsType } from 'antd/es/table'

const { Title, Text } = Typography
const { RangePicker } = DatePicker

/* ==================== 类型定义 ==================== */

interface Station {
  id: number
  name: string
  location?: string
  capacity?: number
  deviceCount?: number
  address?: string
  [key: string]: any
}

interface DeviceItem {
  id: string
  sn: string
  model: string
  rated_power?: number
  status: number
  last_online_at?: string
  stationId?: string
  [key: string]: any
}

interface RealtimeData {
  pv1_voltage?: number
  pv2_voltage?: number
  pv1_power?: number
  pv2_power?: number
  pv_total_power?: number
  ac_voltage?: number
  ac_current?: number
  ac_power?: number
  ac_frequency?: number
  power_factor?: number
  battery_soc?: number
  battery_voltage?: number
  charge_power?: number
  discharge_power?: number
  backup_voltage?: number
  backup_frequency?: number
  backup_power?: number
  backup_apparent_power?: number
  vbus1?: number
  vbus2?: number
  inverter_temp?: number
  [key: string]: any
}

interface TelemetryRecord {
  time?: string
  timestamp?: string
  [key: string]: any
}

interface HistoryRecord {
  time?: string
  timestamp?: string
  [key: string]: any
}

interface AlarmRecord {
  id: string | number
  device_sn?: string
  alarm_level?: number | string
  fault_code?: string
  fault_message?: string
  occurred_at?: string
  status?: string
  [key: string]: any
}

/* ==================== 常量 ==================== */

const getTimeRange = (range: string): { start: string; end: string } => {
  const end = dayjs()
  let start: dayjs.Dayjs
  switch (range) {
    case '1h': start = end.subtract(1, 'hour'); break
    case '6h': start = end.subtract(6, 'hour'); break
    case '24h': start = end.subtract(1, 'day'); break
    case '7d': start = end.subtract(7, 'day'); break
    default: start = end.subtract(1, 'hour')
  }
  return { start: start.toISOString(), end: end.toISOString() }
}

/* ==================== 主组件 ==================== */

const MonitoringPage: React.FC = () => {
  const { t } = useTranslation()
  const screens = Grid.useBreakpoint()
  const isMobile = !screens.md
  const { timezone } = useTimezoneStore()

  const TIME_RANGES = [
    { label: t('mon.oneHour'), value: '1h' },
    { label: t('mon.sixHours'), value: '6h' },
    { label: t('mon.twentyFourHours'), value: '24h' },
    { label: t('mon.sevenDays'), value: '7d' },
    { label: t('mon.custom'), value: 'custom' },
  ]

  /* ---------- 电站选择 ---------- */
  const [selectedStationId, setSelectedStationId] = useState<string>('')
  const [selectedDeviceSn, setSelectedDeviceSn] = useState<string>('')

  const { data: stationsRaw } = useQuery({
    queryKey: ['monitoring', 'stations'],
    queryFn: () => api.get('/stations', { params: { page_size: 100, all: true } }).then((r) => r.data),
    staleTime: 60_000,
    refetchOnMount: true,
  })

  const stationList: Station[] = useMemo(() => {
    if (!stationsRaw) return []
    const d = stationsRaw?.data ?? stationsRaw ?? {}
    const items = Array.isArray(d) ? d : (d?.items ?? d?.list ?? [])
    return Array.isArray(items) ? items : []
  }, [stationsRaw])

  const selectedStation = stationList.find((s) => String(s.id) === selectedStationId)

  /* ---------- 电站下设备列表 ---------- */
  const { data: devicesRes } = useQuery({
    queryKey: ['monitoring', 'devices', selectedStationId],
    queryFn: () => deviceApi.getDevices({ station_id: selectedStationId, page_size: 200 }).then((r) => {
      const d = r.data?.data ?? r.data
      return (d?.items ?? []) as DeviceItem[]
    }),
    enabled: !!selectedStationId,
  })

  const deviceList = devicesRes ?? []

  useEffect(() => {
    if (deviceList.length > 0 && !selectedDeviceSn) {
      setSelectedDeviceSn(deviceList[0].sn)
    }
    if (deviceList.length === 0) {
      setSelectedDeviceSn('')
    }
  }, [deviceList, selectedDeviceSn])

  const selectedDevice = deviceList.find((d) => d.sn === selectedDeviceSn)

  /* ---------- 型号字段配置 ---------- */
  const modelFields = useModelFields(selectedDevice?.model)
  const showFields = modelFields.cache?.showFields ?? []
  const fieldGroups = useMemo(() => {
    const groups: Record<string, DeviceModelFieldItem[]> = {}
    for (const f of showFields) {
      const g = f.group_name || t('mon.other')
      if (!groups[g]) groups[g] = []
      groups[g].push(f)
    }
    return groups
  }, [showFields])
  const fieldLabelMap = useMemo(() => {
    const map: Record<string, string> = {}
    for (const f of showFields) {
      map[f.field_key] = f.unit ? `${f.field_name}(${f.unit})` : f.field_name
    }
    return map
  }, [showFields])
  const paramOptions = useMemo(() =>
    showFields.map((f) => ({
      label: f.unit ? `${f.field_name} (${f.unit})` : f.field_name,
      value: f.field_key,
      unit: f.unit || '',
      group: f.group_name || t('mon.other'),
    })),
  [showFields])

  /* ============================================================
   *  实时数据 (15秒自动刷新)
   * ============================================================ */

  const { data: realtimeRes, isLoading: realtimeLoading } = useQuery({
    queryKey: ['monitoring', 'realtime', selectedDeviceSn],
    queryFn: () => deviceApi.getRealtime(selectedDeviceSn).then((r) => {
      const raw = r.data?.data ?? r.data ?? {}
      return (raw?.realtime ?? raw) as RealtimeData
    }),
    enabled: !!selectedDeviceSn,
    refetchInterval: 15000,
  })

  const rt = realtimeRes ?? {} as RealtimeData

  // 灵活查找字段值：支持扁平key(ac_voltage)和嵌套key(ac.voltage)和嵌套对象(ac.voltage)
  const getFieldValue = (data: any, fieldKey: string): any => {
    if (data == null) return undefined
    // 1. 直接扁平 key
    if (data[fieldKey] !== undefined) return data[fieldKey]
    // 2. 嵌套路径: "ac_voltage" -> 尝试 data.ac.voltage
    const parts = fieldKey.split('_')
    for (let i = 1; i < parts.length; i++) {
      const prefix = parts.slice(0, i).join('_')
      const suffix = parts.slice(i).join('_')
      if (data[prefix] && typeof data[prefix] === 'object' && data[prefix][suffix] !== undefined) {
        return data[prefix][suffix]
      }
    }
    // 3. 遍历所有嵌套对象查找
    for (const key of Object.keys(data)) {
      if (data[key] && typeof data[key] === 'object' && !Array.isArray(data[key])) {
        if (data[key][fieldKey] !== undefined) return data[key][fieldKey]
        // 再试一层嵌套
        for (const subKey of Object.keys(data[key])) {
          if (data[key][subKey] && typeof data[key][subKey] === 'object') {
            if (data[key][subKey][fieldKey] !== undefined) return data[key][subKey][fieldKey]
          }
        }
      }
    }
    return undefined
  }

  /* ============================================================
   *  Tab 1: 运行参数
   * ============================================================ */

  const GROUP_COLOR_PALETTE = [
    { color: '#f97316', bg: '#fff7ed', icon: <ThunderboltOutlined style={{ color: '#f97316' }} /> },
    { color: '#1677ff', bg: '#eff6ff', icon: <SwapOutlined style={{ color: '#1677ff' }} /> },
    { color: '#52c41a', bg: '#f0fdf4', icon: <ThunderboltOutlined style={{ color: '#52c41a' }} /> },
    { color: '#722ed1', bg: '#faf5ff', icon: <CloudOutlined style={{ color: '#722ed1' }} /> },
    { color: '#13c2c2', bg: '#f0fdfa', icon: <ExperimentOutlined style={{ color: '#13c2c2' }} /> },
    { color: '#eb2f96', bg: '#fdf2f8', icon: <BarChartOutlined style={{ color: '#eb2f96' }} /> },
    { color: '#faad14', bg: '#fffbe6', icon: <FieldTimeOutlined style={{ color: '#faad14' }} /> },
    { color: '#f5222d', bg: '#fff1f0', icon: <AlertOutlined style={{ color: '#f5222d' }} /> },
  ]
  const getGroupColor = (groupName: string, idx: number) => GROUP_COLOR_PALETTE[idx % GROUP_COLOR_PALETTE.length]

  const renderRunningParams = () => {
    if (!selectedDeviceSn) {
      return <Empty description={selectedStationId ? t('mon.noDeviceInStation') : t('mon.pleaseSelectStationFirst')} />
    }

    const deviceStatus = selectedDevice?.status
    const statusCfg = DEVICE_STATUS_MAP[deviceStatus ?? 0] ?? DEVICE_STATUS_MAP[0]
    const hasModelFields = showFields.length > 0

    return (
      <Spin spinning={realtimeLoading}>
        {/* 设备状态栏 */}
        <Card size="small" bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
          <Row align="middle" justify="space-between">
            <Col>
              <Space>
                <Text strong style={{ fontSize: 15 }}>{selectedDeviceSn}</Text>
                <Tag color={statusCfg.color}>{statusCfg.label}</Tag>
                {selectedDevice?.model && <Tag>{selectedDevice.model}</Tag>}
                {selectedDevice?.rated_power != null && <Tag color="blue">{selectedDevice.rated_power}W</Tag>}
                {modelFields.loading && <Tag color="processing">{t('mon.loadingFieldConfig')}</Tag>}
              </Space>
            </Col>
            <Col>
              <Badge status={deviceStatus === 1 ? 'processing' : deviceStatus === 2 ? 'error' : 'default'}
                text={                <Text type="secondary" style={{ fontSize: 12 }}>
                  {t('mon.lastCommunication')}: {formatInTimezone(selectedDevice?.last_online_at, selectedStation?.timezone, 'MM-DD HH:mm:ss')}
                </Text>}
              />
            </Col>
          </Row>
        </Card>

        {hasModelFields ? (
          <>
            {/* Hero 概览卡片 — 取前6个显示字段 */}
            <Row gutter={[12, 12]} style={{ marginBottom: 16 }}>
              {showFields.slice(0, 6).map((field, idx) => {
                const value = getFieldValue(rt, field.field_key)
                const numValue = safeNum(value)
                return (
                  <Col xs={12} sm={8} lg={4} key={field.id}>
                    <Card bordered={false} style={{ background: HERO_GRADIENTS[idx % HERO_GRADIENTS.length], borderRadius: 12 }}
                      styles={{ body: { padding: isMobile ? '12px 10px' : '20px 16px' } }}
                    >
                      <div style={{ color: '#fff', fontSize: 13, opacity: 0.9, marginBottom: 8 }}>
                        {field.field_name}
                      </div>
                      <div style={{ color: '#fff', fontSize: isMobile ? 22 : 28, fontWeight: 700, lineHeight: 1 }}>
                        {field.field_type === 'float' ? numValue.toFixed(1) : Math.round(numValue)}
                        {field.unit && <span style={{ fontSize: 14, fontWeight: 400, marginLeft: 4 }}>{field.unit}</span>}
                      </div>
                    </Card>
                  </Col>
                )
              })}
            </Row>

            {/* 按 group_name 分组的参数卡片 */}
            <Row gutter={[16, 16]}>
              {Object.entries(fieldGroups).map(([groupName, fields], groupIdx) => {
                const gc = getGroupColor(groupName, groupIdx)
                const isWide = fields.length > 4
                return (
                  <Col xs={24} lg={isWide ? 12 : 8} key={groupName}>
                    <Card
                      bordered={false}
                      title={<span>{gc.icon} {groupName}</span>}
                      style={{ borderRadius: 12, height: '100%' }}
                    >
                      <Row gutter={[16, 16]}>
                        {fields.map((field) => {
                          const value = getFieldValue(rt, field.field_key)
                          const precision = field.field_type === 'float' ? (field.unit === '%' ? 1 : 2) : 0
                          return (
                            <Col span={Math.floor(24 / Math.min(fields.length, 4))} key={field.id}>
                              <Statistic
                                title={field.field_name}
                                value={value}
                                precision={precision}
                                suffix={field.unit || undefined}
                                valueStyle={{ color: gc.color, fontSize: 20 }}
                              />
                            </Col>
                          )
                        })}
                      </Row>
                    </Card>
                  </Col>
                )
              })}
            </Row>
          </>
        ) : (
          <Card bordered={false} style={{ borderRadius: 12, textAlign: 'center', padding: '48px 24px' }}>
            <Empty
              description={
                <span>
                  {t('mon.noModelField')}<br />
                  <Text type="secondary">{t('mon.gotoModelMgmt')}</Text>
                </span>
              }
            />
          </Card>
        )}
      </Spin>
    )
  }

  /* ============================================================
   *  Tab 2: 曲线对比
   * ============================================================ */

  const [curveRange, setCurveRange] = useState<string>('24h')
  const [curveCustomRange, setCurveCustomRange] = useState<[dayjs.Dayjs, dayjs.Dayjs] | null>(null)
  const [curveParams, setCurveParams] = useState<string[]>(['pv_total_power', 'ac_power'])
  const [curveData, setCurveData] = useState<TelemetryRecord[]>([])
  const [curveLoading, setCurveLoading] = useState(false)

  const fetchCurveData = useCallback(async () => {
    if (!selectedDeviceSn) return
    setCurveLoading(true)
    try {
      let params: any = {}
      if (curveRange === 'custom' && curveCustomRange) {
        params.startTime = curveCustomRange[0].toISOString()
        params.endTime = curveCustomRange[1].toISOString()
      } else {
        const { start, end } = getTimeRange(curveRange)
        params.startTime = start
        params.endTime = end
      }
      params.page_size = 1000
      const res = await deviceApi.getTelemetry(selectedDeviceSn, params)
      const payload = res.data?.data ?? res.data
      const items = Array.isArray(payload) ? payload : (payload?.items ?? [])
      setCurveData(items)
    } catch {
      setCurveData([])
    } finally {
      setCurveLoading(false)
    }
  }, [selectedDeviceSn, curveRange, curveCustomRange])

  useEffect(() => {
    if (selectedDeviceSn) fetchCurveData()
  }, [fetchCurveData])

  const curveChartOption = useMemo(() => {
    if (!curveData || curveData.length === 0 || curveParams.length === 0) return {}

    const times = curveData.map((r: any) =>
      formatInTimezone(r.time ?? r.timestamp ?? r.created_at, timezone, 'MM-DD HH:mm'),
    )

    const series = curveParams.map((paramKey, idx) => {
      const paramDef = paramOptions.find((p) => p.value === paramKey)
      return {
        name: paramDef?.label ?? paramKey,
        type: 'line' as const,
        data: curveData.map((r: any) => safeNum(r[paramKey] ?? r.data?.[paramKey])),
        smooth: true,
        symbol: 'none' as const,
        lineStyle: { color: CHART_COLORS[idx % CHART_COLORS.length], width: 2 },
        itemStyle: { color: CHART_COLORS[idx % CHART_COLORS.length] },
        areaStyle: {
          color: {
            type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: `${CHART_COLORS[idx % CHART_COLORS.length]}33` },
              { offset: 1, color: `${CHART_COLORS[idx % CHART_COLORS.length]}05` },
            ],
          },
        },
      }
    })

    // Determine if we need dual Y axes
    const hasDifferentUnits = curveParams.length > 1 && (() => {
      const units = curveParams.map((p) => paramOptions.find((o) => o.value === p)?.unit).filter(Boolean)
      return new Set(units).size > 1
    })()

    const yAxis: any = hasDifferentUnits
      ? curveParams.slice(0, 2).map((p, idx) => ({
          type: 'value' as const,
          name: paramOptions.find((o) => o.value === p)?.unit || '',
          position: idx === 0 ? 'left' as const : 'right' as const,
          axisLabel: { formatter: '{value}' },
        }))
      : { type: 'value' as const }

    const seriesWithAxis = hasDifferentUnits
      ? series.map((s, idx) => ({ ...s, yAxisIndex: Math.min(idx, 1) }))
      : series

    return {
      tooltip: {
        trigger: 'axis' as const,
        axisPointer: { type: 'cross' as const },
      },
      legend: { data: series.map((s) => s.name), top: 0 },
      grid: { left: '3%', right: hasDifferentUnits ? '6%' : '3%', bottom: '12%', top: '45', containLabel: true },
      xAxis: { type: 'category' as const, data: times, boundaryGap: false },
      yAxis,
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        { type: 'slider', start: 0, end: 100, height: 20, bottom: 8 },
      ],
      series: seriesWithAxis,
    }
  }, [curveData, curveParams])

  const renderCurveComparison = () => {
    if (!selectedDeviceSn) {
      return <Empty description={selectedStationId ? t('mon.noDeviceInStation') : t('mon.pleaseSelectStationFirst')} />
    }
    if (paramOptions.length === 0) {
      return <Empty description={<span>{t('mon.noFieldConfig')}</span>} />
    }

    return (
      <>
        <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}>
          <Row gutter={[12, 12]} align="middle">
            <Col xs={24} sm={12} md={8}>
              <Text strong style={{ marginRight: 8 }}>{t('mon.paramSelectLabel')}</Text>
              <Select
                mode="multiple"
                style={{ minWidth: 300, maxWidth: '100%' }}
                value={curveParams}
                onChange={setCurveParams}
                options={paramOptions}
                maxTagCount={3}
                placeholder={t('mon.selectCompareParams')}
                optionFilterProp="label"
              />
            </Col>
            <Col xs={24} sm={12} md={10}>
              <Text strong style={{ marginRight: 8 }}>{t('mon.timeRangeLabel')}</Text>
              <Segmented
                value={curveRange}
                onChange={(v) => setCurveRange(v as string)}
                options={TIME_RANGES}
              />
              {curveRange === 'custom' && (
                <RangePicker
                  showTime
                  style={{ marginLeft: 8 }}
                  value={curveCustomRange}
                  onChange={(dates) => {
                    if (dates && dates[0] && dates[1]) {
                      setCurveCustomRange([dates[0], dates[1]])
                    }
                  }}
                />
              )}
            </Col>
            <Col>
              <Button icon={<ReloadOutlined />} onClick={fetchCurveData} loading={curveLoading}>
                {t('common.refresh')}
              </Button>
            </Col>
          </Row>
        </Card>

        <Card bordered={false} style={{ borderRadius: 12 }}>
          {curveLoading ? (
            <div style={{ height: 400, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Spin tip={t('mon.loadingCurve')} />
            </div>
          ) : curveData.length > 0 && curveParams.length > 0 ? (
            <ReactECharts option={curveChartOption} style={{ height: 450 }} />
          ) : (
            <Empty description={t('mon.pleaseSelectParam')} style={{ padding: 80 }} />
          )}
        </Card>
      </>
    )
  }

  /* ============================================================
   *  Tab 3: 历史数据
   * ============================================================ */

  const [historyPage, setHistoryPage] = useState(1)
  const [historyPageSize, setHistoryPageSize] = useState(20)
  const [historyRange, setHistoryRange] = useState<[dayjs.Dayjs, dayjs.Dayjs]>([
    dayjs().subtract(7, 'day'),
    dayjs(),
  ])
  const [selectedHistoryFields, setSelectedHistoryFields] = useState<string[]>([])
  const [fieldPanelOpen, setFieldPanelOpen] = useState(false)

  const { data: historyRes, isLoading: historyLoading } = useQuery({
    queryKey: ['monitoring', 'history', selectedDeviceSn, historyPage, historyPageSize, historyRange],
    queryFn: () => {
      const params: any = {
        page: historyPage,
        page_size: historyPageSize,
        startTime: historyRange[0].toISOString(),
        endTime: historyRange[1].toISOString(),
        granularity: 'hour',
        sort: 'desc',
      }
      return deviceApi.getTelemetry(selectedDeviceSn, params).then((r) => {
        const d = r.data?.data ?? r.data
        return {
          items: (d?.items ?? (Array.isArray(d) ? d : [])) as HistoryRecord[],
          total: d?.total ?? 0,
        }
      })
    },
    enabled: !!selectedDeviceSn,
  })

  const historyItems = historyRes?.items ?? []
  const historyTotal = historyRes?.total ?? 0

  const FIELD_LABEL_MAP = fieldLabelMap

  // 从历史数据中收集所有可用字段
  const historyAvailableFields = useMemo(() => {
    const skipKeys = new Set(['time', 'timestamp', 'created_at', 'device_sn', 'topic'])
    const fieldSet = new Set<string>()
    for (const item of historyRes?.items ?? []) {
      if (item && typeof item === 'object') {
        Object.keys(item).forEach((k) => { if (!skipKeys.has(k)) fieldSet.add(k) })
      }
    }
    return Array.from(fieldSet)
  }, [historyRes])

  // 后端字段 key → 中文标签的默认映射（型号配置未覆盖时使用）
  const DEFAULT_FIELD_LABELS: Record<string, string> = {
    // 交流参数
    ac_voltage: '输出电压(V)',
    ac_current: '输出电流(A)',
    ac_power: '有功功率(W)',
    ac_frequency: '输出频率(Hz)',
    power_factor: '功率因数',
    apparent_power: '视在功率(VA)',
    load_rate: '负载率(%)',
    voltage_thd: '电压THD(%)',
    // 电池参数
    battery_soc: '电池SOC(%)',
    battery_voltage: '电池电压(V)',
    battery_current: '电池电流(A)',
    battery_capacity: '电池容量(%)',
    battery_health: '电池健康度(%)',
    charge_discharge_power: '充放电功率(W)',
    remaining_capacity: '剩余容量(Ah)',
    rated_capacity: '额定容量(Ah)',
    cycle_count: '循环次数',
    cell_max_temp: '电芯最高温度(℃)',
    cell_min_temp: '电芯最低温度(℃)',
    cell_max_voltage: '单体最高电压(V)',
    cell_min_voltage: '单体最低电压(V)',
    cell_voltage_diff: '电芯压差(V)',
    charge_status: '充放电状态',
    battery_avg_temp: '电池平均温度(℃)',
    bms_fault_code: 'BMS故障码',
    protect_status: '保护状态',
    max_chg_current: '最大充电电流(A)',
    max_dischg_current: '最大放电电流(A)',
    charge_volt_ref: '充电参考电压(V)',
    dischg_cut_volt: '放电截止电压(V)',
    // 光伏参数
    pv1_voltage: 'PV1电压(V)',
    pv2_voltage: 'PV2电压(V)',
    pv1_current: 'PV1电流(A)',
    pv2_current: 'PV2电流(A)',
    pv1_power: 'PV1功率(W)',
    pv2_power: 'PV2功率(W)',
    pv_total_power: 'PV总功率(W)',
    mppt_status: 'MPPT状态',
    pv1_voltage_max: 'PV1历史最高电压(V)',
    pv1_power_max: 'PV1历史最高功率(W)',
    pv2_voltage_max: 'PV2历史最高电压(V)',
    pv2_power_max: 'PV2历史最高功率(W)',
    // 系统状态
    run_status: '运行状态',
    fault_code: '故障码',
    alarm_code: '告警码',
    inverter_temp: '逆变器温度(℃)',
    heatsink_temp: '散热器温度(℃)',
    ambient_temp: '环境温度(℃)',
    dc_bus_voltage: '直流母线电压(V)',
    vbus1: '母线电压1(V)',
    vbus2: '母线电压2(V)',
    efficiency: '转换效率(%)',
    total_run_time: '累计运行时长(h)',
    fan_speed: '风扇转速(%)',
    // 能量统计
    energy: '当日发电量(kWh)',
    total_energy: '累计发电量(kWh)',
    daily_charge: '当日充电量(kWh)',
    total_charge: '累计充电量(kWh)',
    discharge: '当日放电量(kWh)',
    total_discharge: '累计放电量(kWh)',
    daily_consumption: '当日用电量(kWh)',
    total_consumption: '累计用电量(kWh)',
    run_time: '运行时间(h)',
    // 控制参数
    power_limit: '功率上限(W)',
    charge_enable: '充电使能',
    discharge_enable: '放电使能',
    grid_charge_enable: '电网充电使能',
    max_charge_current: '最大充电电流(A)',
    max_discharge_current: '最大放电电流(A)',
  }

  // 型号字段 key → 数据 key 的映射（处理命名差异如 batt_soc → battery_soc）
  const modelToDataKeyMap = useMemo(() => {
    const map: Record<string, string> = {}

    // 构建数据 key → 标准化名称的反向索引，用于名称匹配
    const dataKeyByName: Record<string, string> = {}
    for (const dk of historyAvailableFields) {
      const label = DEFAULT_FIELD_LABELS[dk]
      if (label) {
        // 提取名称部分（去掉单位），如 "输出电压(V)" → "输出电压"
        const namePart = label.replace(/\(.*\)$/, '').trim().toLowerCase()
        dataKeyByName[namePart] = dk
      }
    }

    const prefixMap: Record<string, string> = {
      pv_: '', batt_: 'battery_', sys_: '', energy_: '', ctrl_: '', info_: '',
    }

    for (const fields of Object.values(fieldGroups)) {
      for (const f of fields) {
        const mk = f.field_key

        // 1) 直接匹配
        if (historyAvailableFields.includes(mk)) {
          map[mk] = mk
          continue
        }

        // 2) 前缀转换匹配
        let matched = false
        for (const [prefix, replace] of Object.entries(prefixMap)) {
          if (mk.startsWith(prefix)) {
            const stripped = mk.replace(prefix, replace)
            if (historyAvailableFields.includes(stripped)) {
              map[mk] = stripped
              matched = true
              break
            }
          }
        }
        if (matched) continue

        // 3) 字段名称匹配（型号配置的 field_name 对比 DEFAULT_FIELD_LABELS 的中文名）
        const modelName = f.field_name.replace(/\(.*\)$/, '').trim().toLowerCase()
        if (dataKeyByName[modelName]) {
          map[mk] = dataKeyByName[modelName]
          continue
        }

        // 4) 模糊 key 匹配（标准化后对比）
        const normalizedMk = mk.replace(/[_\-\.]/g, '').toLowerCase()
        for (const dk of historyAvailableFields) {
          const normalizedDk = dk.replace(/[_\-\.]/g, '').toLowerCase()
          if (normalizedMk === normalizedDk) {
            map[mk] = dk
            break
          }
        }
      }
    }
    return map
  }, [fieldGroups, historyAvailableFields])

  // 反向映射：数据 key → 型号字段（用于标签显示）
  const dataKeyToModelField = useMemo(() => {
    const m: Record<string, { field_name: string; unit?: string }> = {}
    for (const fields of Object.values(fieldGroups)) {
      for (const f of fields) {
        const dataKey = modelToDataKeyMap[f.field_key]
        if (dataKey) m[dataKey] = f
      }
    }
    return m
  }, [fieldGroups, modelToDataKeyMap])

  // 字段标签映射（带模糊匹配）
  const historyFieldLabel = (key: string): string => {
    // 优先使用反向映射（数据 key → 型号字段标签）
    const mf = dataKeyToModelField[key]
    if (mf) return mf.unit ? `${mf.field_name}(${mf.unit})` : mf.field_name
    if (FIELD_LABEL_MAP[key]) return FIELD_LABEL_MAP[key]
    for (const fields of Object.values(fieldGroups)) {
      const found = fields.find((f) => f.field_key === key)
      if (found) return found.unit ? `${found.field_name}(${found.unit})` : found.field_name
    }
    for (const fields of Object.values(fieldGroups)) {
      const found = fields.find((f) =>
        f.field_key.includes(key) || key.includes(f.field_key) ||
        f.field_key.replace(/[._]/g, '') === key.replace(/[._]/g, '')
      )
      if (found) return found.unit ? `${found.field_name}(${found.unit})` : found.field_name
    }
    if (DEFAULT_FIELD_LABELS[key]) return DEFAULT_FIELD_LABELS[key]
    return key.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
  }

  // 字段选择器选项（型号配置字段优先，再补充数据中的其他字段）
  const historyFieldOptions = useMemo(() => {
    const seen = new Set<string>()
    const opts: { label: string; value: string }[] = []
    // 型号配置的字段排在前面
    for (const f of showFields) {
      if (historyAvailableFields.includes(f.field_key)) {
        seen.add(f.field_key)
        opts.push({
          label: f.unit ? `${f.field_name}(${f.unit})` : f.field_name,
          value: f.field_key,
        })
      }
    }
    // 补充数据中存在但不在型号配置中的字段
    for (const key of historyAvailableFields) {
      if (!seen.has(key)) {
        opts.push({ label: historyFieldLabel(key), value: key })
      }
    }
    return opts
  }, [historyAvailableFields, showFields, fieldGroups])

  // 当前要显示的字段（优先使用用户选择，否则显示全部字段）
  const displayHistoryFields = useMemo(() => {
    if (selectedHistoryFields.length > 0) {
      return selectedHistoryFields.filter((k) => historyAvailableFields.includes(k))
    }
    // 默认：显示所有数据字段，优先按型号配置顺序排列
    const modelDataKeys = Object.values(modelToDataKeyMap)
    const ordered = [...new Set([...modelDataKeys, ...historyAvailableFields])]
    return ordered.filter((k) => historyAvailableFields.includes(k))
  }, [selectedHistoryFields, historyAvailableFields, modelToDataKeyMap])

  // 历史数据列
  const historyColumns: ColumnsType<any> = useMemo(() => {
    const timeCol: ColumnsType<any>[0] = {
      title: t('common.time'), dataIndex: 'time', key: 'time', width: 160, fixed: 'left' as const,
      render: (_: any, record: any) => {
        const t = record.time ?? record.timestamp ?? record.created_at
        return t ? formatInTimezone(t, timezone, 'YYYY-MM-DD HH:mm:ss') : '--'
      },
    }

    const dataCols: ColumnsType<any> = displayHistoryFields.map((key) => ({
      title: historyFieldLabel(key),
      dataIndex: key,
      key,
      width: 120,
      render: (v: any) => fmt(v),
    }))

    return [timeCol, ...dataCols]
  }, [displayHistoryFields, historyItems, fieldGroups])

  const handleExportHistory = async (format: 'csv' | 'excel') => {
    if (!selectedDeviceSn) return
    try {
      const res = await deviceApi.exportTelemetry(selectedDeviceSn, format, {
        startTime: historyRange[0].toISOString(),
        endTime: historyRange[1].toISOString(),
      })
      const blob = res.data as Blob
      const url = window.URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = url
      const ext = format === 'excel' ? 'xlsx' : 'csv'
      link.download = `${selectedDeviceSn}_history_${Date.now()}.${ext}`
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)
      window.URL.revokeObjectURL(url)
    } catch {
      // silent
    }
  }

  const renderHistoryData = () => {
    if (!selectedDeviceSn) {
      return <Empty description={selectedStationId ? t('mon.noDeviceInStation') : t('mon.pleaseSelectStationFirst')} />
    }

    return (
      <>
        <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}>
          <Row gutter={[12, 12]} align="middle">
            <Col xs={24} sm={12} md={6}>
              <Text strong style={{ marginRight: 8 }}>{t('mon.dateRangeLabel')}</Text>
              <RangePicker
                value={historyRange}
                onChange={(dates) => {
                  if (dates && dates[0] && dates[1]) {
                    setHistoryRange([dates[0], dates[1]])
                    setHistoryPage(1)
                  }
                }}
                style={{ width: '100%', maxWidth: 340 }}
              />
            </Col>
            <Col xs={24} sm={12} md={10}>
              <Text strong style={{ marginRight: 8 }}>{t('mon.displayFields')}</Text>
              <Button icon={<FilterOutlined />} onClick={() => setFieldPanelOpen(true)}>
                {selectedHistoryFields.length > 0
                  ? `${t('mon.displayFields')} (${selectedHistoryFields.length})`
                  : t('mon.allFields')}
              </Button>
            </Col>
            <Col>
              <Space>
                <Button icon={<ReloadOutlined />} onClick={() => setHistoryPage(1)}>
                  {t('mon.query')}
                </Button>
                <Button icon={<DownloadOutlined />} onClick={() => handleExportHistory('csv')}>
                  {t('mon.exportCSV')}
                </Button>
                <Button icon={<DownloadOutlined />} onClick={() => handleExportHistory('excel')}>
                  {t('mon.exportExcel')}
                </Button>
              </Space>
            </Col>
          </Row>
        </Card>

        <Card bordered={false} style={{ borderRadius: 12 }}>
          <Table
            columns={historyColumns}
            dataSource={historyItems}
            loading={historyLoading}
            rowKey={(_, idx) => String(idx)}
            pagination={{
              current: historyPage,
              pageSize: historyPageSize,
              total: historyTotal,
              showSizeChanger: true,
              pageSizeOptions: ['10', '20', '50', '100'],
                  showTotal: (total) => t('common.total', { total }),
              onChange: (p, ps) => { setHistoryPage(p); setHistoryPageSize(ps) },
            }}
            scroll={{ x: 1200 }}
            size="small"
          />
        </Card>

        {/* 字段选择弹窗 */}
        <Modal
          title={<Space><FilterOutlined />{t('mon.displayFields')}</Space>}
          open={fieldPanelOpen}
          onCancel={() => setFieldPanelOpen(false)}
          width={860}
          styles={{ body: { maxHeight: '65vh', overflowY: 'auto', padding: '12px 16px' } }}
          footer={
            <Space>
              <Button onClick={() => setSelectedHistoryFields([])}>{t('mon.allFields')}</Button>
              <Button type="primary" onClick={() => setFieldPanelOpen(false)}>{t('common.confirm') || '确定'}</Button>
            </Space>
          }
        >
          {(() => {
            const allDataKeys = historyAvailableFields
            const isAllSelected = selectedHistoryFields.length === 0

            // 按型号配置分组（显示所有分组，即使某些字段在数据中暂无值）
            const groupEntries: { name: string; fields: { modelKey: string; dataKey: string; label: string }[] }[] = []
            for (const [groupName, fields] of Object.entries(fieldGroups)) {
              const items: { modelKey: string; dataKey: string; label: string }[] = []
              for (const f of fields) {
                const dataKey = modelToDataKeyMap[f.field_key]
                items.push({
                  modelKey: f.field_key,
                  dataKey: dataKey || f.field_key,
                  label: f.unit ? `${f.field_name}(${f.unit})` : f.field_name,
                })
              }
              if (items.length > 0) {
                groupEntries.push({ name: groupName, fields: items })
              }
            }

            // 不在型号配置中的数据字段
            const mappedDataKeys = new Set(
              groupEntries.flatMap((g) => g.fields.map((f) => f.dataKey))
            )
            const otherItems: { modelKey: string; dataKey: string; label: string }[] = []
            for (const key of allDataKeys) {
              if (!mappedDataKeys.has(key)) {
                otherItems.push({ modelKey: key, dataKey: key, label: historyFieldLabel(key) })
              }
            }
            if (otherItems.length > 0) {
              groupEntries.push({ name: '其他字段', fields: otherItems })
            }

            return (
              <>
                <div style={{ marginBottom: 16, paddingBottom: 12, borderBottom: '1px solid #f0f0f0' }}>
                  <Checkbox
                    checked={isAllSelected}
                    onChange={(e) => { if (e.target.checked) setSelectedHistoryFields([]) }}
                  >
                    <Text strong>{t('mon.allFields')}</Text>
                  </Checkbox>
                </div>
                <Row gutter={[12, 12]}>
                {groupEntries.map((group, groupIdx) => {
                  const gc = getGroupColor(group.name, groupIdx)
                  const groupDataKeys = group.fields.map((f) => f.dataKey)
                  const groupAllSelected = isAllSelected || groupDataKeys.every((k) => selectedHistoryFields.includes(k))
                  const groupSomeSelected = !groupAllSelected && groupDataKeys.some((k) => selectedHistoryFields.includes(k))
                  return (
                    <Col span={12} key={group.name}>
                    <Card
                      bordered={false}
                      size="small"
                      title={
                        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                          <Space>
                            {gc.icon}
                            <Text strong style={{ fontSize: 14 }}>{group.name}</Text>
                            <Text type="secondary" style={{ fontSize: 12 }}>{group.fields.length}</Text>
                          </Space>
                          <Checkbox
                            checked={groupAllSelected}
                            indeterminate={groupSomeSelected}
                            onChange={(e) => {
                              if (isAllSelected) {
                                const exclude = new Set(groupDataKeys)
                                setSelectedHistoryFields(allDataKeys.filter((k) => !exclude.has(k)))
                              } else if (e.target.checked) {
                                const addKeys = groupDataKeys.filter((k) => !selectedHistoryFields.includes(k))
                                setSelectedHistoryFields([...selectedHistoryFields, ...addKeys])
                              } else {
                                const removeKeys = new Set(groupDataKeys)
                                setSelectedHistoryFields(selectedHistoryFields.filter((k) => !removeKeys.has(k)))
                              }
                            }}
                          >
                            <Text type="secondary" style={{ fontSize: 11 }}>全选</Text>
                          </Checkbox>
                        </div>
                      }
                      style={{ borderRadius: 10, height: '100%' }}
                      styles={{ body: { padding: '8px 12px' } }}
                    >
                      <Space size={[6, 6]} wrap>
                        {group.fields.map((f) => {
                          const selected = isAllSelected || selectedHistoryFields.includes(f.dataKey)
                          return (
                            <Tag
                              key={f.dataKey}
                              color={selected ? gc.color : undefined}
                              style={{
                                cursor: 'pointer',
                                padding: '3px 10px',
                                fontSize: 12,
                                borderRadius: 4,
                                margin: 0,
                              }}
                              onClick={() => {
                                if (isAllSelected) {
                                  setSelectedHistoryFields(allDataKeys.filter((k) => k !== f.dataKey))
                                } else if (selectedHistoryFields.includes(f.dataKey)) {
                                  setSelectedHistoryFields(selectedHistoryFields.filter((k) => k !== f.dataKey))
                                } else {
                                  setSelectedHistoryFields([...selectedHistoryFields, f.dataKey])
                                }
                              }}
                            >
                              {f.label}
                            </Tag>
                          )
                        })}
                      </Space>
                    </Card>
                    </Col>
                  )
                })}
                </Row>
              </>
            )
          })()}
        </Modal>
       </>
     )
   }

  /* ============================================================
   *  Tab 5: 历史事件
   * ============================================================ */

  const [alarmLevel, setAlarmLevel] = useState<string>('')
  const [alarmPage, setAlarmPage] = useState(1)
  const [alarmPageSize, setAlarmPageSize] = useState(20)

  const { data: alarmsRes, isLoading: alarmsLoading } = useQuery({
    queryKey: ['monitoring', 'alarms', selectedDeviceSn, alarmLevel, alarmPage, alarmPageSize],
    queryFn: () => {
      const params: any = { page: alarmPage, page_size: alarmPageSize }
      if (alarmLevel) params.alarmLevel = alarmLevel
      return alertApi.list({ ...params, deviceSn: selectedDeviceSn }).then((r) => {
        const d = r.data?.data ?? r.data
        return {
          items: (d?.items ?? (Array.isArray(d) ? d : [])) as AlarmRecord[],
          total: d?.total ?? 0,
        }
      })
    },
    enabled: !!selectedDeviceSn,
  })

  const alarmItems = alarmsRes?.items ?? []
  const alarmTotal = alarmsRes?.total ?? 0

  const alarmColumns: ColumnsType<AlarmRecord> = [
    {
      title: t('common.time'), dataIndex: 'occurred_at', key: 'occurred_at', width: 170,
      render: (v: string) => v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss') : '--',
    },
    {
      title: t('mon.alertLevelLabel'), dataIndex: 'alarm_level', key: 'alarm_level', width: 80,
      render: (level: number | string, record: any) => {
        const cfg = getAlarmLevelDisplay(record.fault_code, level)
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    { title: t('mon.faultCode'), dataIndex: 'fault_code', key: 'fault_code', width: 100, render: (v: string) => v || '--' },
    { title: t('mon.faultMessageLabel'), dataIndex: 'fault_message', key: 'fault_message', ellipsis: true },
    {
      title: t('mon.deviceSnLabel'), dataIndex: 'device_sn', key: 'device_sn', width: 150,
      render: (v: string) => <Text code>{v || '--'}</Text>,
    },
    {
      title: t('mon.statusLabel'), dataIndex: 'status', key: 'status', width: 80,
      render: (status: string) => {
        const statusMap: Record<string, { label: string; color: string }> = {
          active: { label: t('mon.active'), color: 'red' },
          acknowledged: { label: t('mon.acknowledged'), color: 'orange' },
          resolved: { label: t('mon.resolved'), color: 'green' },
          pending: { label: t('mon.pending'), color: 'orange' },
        }
        const cfg = statusMap[status] ?? { label: status || '--', color: 'default' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
  ]

  const renderAlarmTimeline = () => {
    if (!selectedDeviceSn) {
      return <Empty description={selectedStationId ? t('mon.noDeviceInStation') : t('mon.pleaseSelectStationFirst')} />
    }

    return (
      <>
        <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}>
          <Row gutter={[12, 12]} align="middle">
            <Col>
              <Text strong style={{ marginRight: 8 }}>{t('mon.alertLevelLabel2')}</Text>
              <Select
                allowClear
                placeholder={t('mon.allLevels')}
                style={{ width: 130 }}
                value={alarmLevel || undefined}
                onChange={(v) => { setAlarmLevel(v || ''); setAlarmPage(1) }}
                options={[
                  { label: t('mon.critical'), value: '1' },
                  { label: t('mon.warning'), value: '2' },
                  { label: t('mon.info'), value: '3' },
                ]}
              />
            </Col>
            <Col>
              <Button icon={<ReloadOutlined />} onClick={() => setAlarmPage(1)}>{t('common.refresh')}</Button>
            </Col>
          </Row>
        </Card>

        {/* Timeline 视图 */}
        <Row gutter={[16, 16]}>
          <Col xs={24} lg={10}>
            <Card bordered={false} title={t('mon.eventTimeline')} style={{ borderRadius: 12 }}>
              {alarmItems.length > 0 ? (
                <Timeline
                  items={alarmItems.map((alarm) => {
                    const levelKey = typeof alarm.alarm_level === 'number' ? String(alarm.alarm_level) : (alarm.alarm_level ?? 'unknown')
                    const levelCfg = getAlarmLevelDisplay(alarm.fault_code, alarm.alarm_level ?? 'unknown')
                    return {
                      color: levelCfg.color,
                      children: (
                        <div>
                          <div style={{ marginBottom: 4 }}>
                            <Tag color={levelCfg.color}>{levelCfg.label}</Tag>
                            {alarm.fault_code && <Tag>{alarm.fault_code}</Tag>}
                          </div>
                          <Text style={{ display: 'block', marginBottom: 2 }}>
                            {alarm.fault_message || t('mon.noDescription')}
                          </Text>
                          <Text type="secondary" style={{ fontSize: 12 }}>
                            {alarm.occurred_at ? formatInTimezone(alarm.occurred_at, timezone, 'YYYY-MM-DD HH:mm:ss') : '--'}
                          </Text>
                        </div>
                      ),
                    }
                  })}
                />
              ) : (
                <Empty description={t('mon.noAlertEvents')} />
              )}
            </Card>
          </Col>

          {/* 表格视图 */}
          <Col xs={24} lg={14}>
            <Card bordered={false} title={t('mon.eventList')} style={{ borderRadius: 12 }}>
              <Table
                columns={alarmColumns}
                dataSource={alarmItems}
                loading={alarmsLoading}
                rowKey="id"
                pagination={{
                  current: alarmPage,
                  pageSize: alarmPageSize,
                  total: alarmTotal,
                  showSizeChanger: true,
                  pageSizeOptions: ['10', '20', '50'],
              showTotal: (total) => t('common.total', { total }),
                  onChange: (p, ps) => { setAlarmPage(p); setAlarmPageSize(ps) },
                }}
                scroll={{ x: 700 }}
                size="small"
              />
            </Card>
          </Col>
        </Row>
      </>
    )
  }

  /* ============================================================
   *  Tab 5: 发电统计 (功率趋势 + 电量概览)
   * ============================================================ */

  const [flowDate, setFlowDate] = useState(dayjs().tz(timezone).format('YYYY-MM-DD'))

  const { data: flowRes, isLoading: flowLoading } = useQuery({
    queryKey: ['monitoring', 'energyFlow', selectedStationId, selectedDeviceSn, flowDate],
    queryFn: () => dashboardApi.getEnergyFlow({
      date: flowDate,
      stationId: selectedStationId || undefined,
      deviceSn: selectedDeviceSn || undefined,
    }).then((r) => r.data?.data ?? r.data ?? []),
    enabled: !!selectedStationId,
    staleTime: 0,
    refetchOnMount: true,
  })
  const flowData = (Array.isArray(flowRes) ? flowRes : (flowRes?.data ?? [])) as any[]

  const energyFlowOption = useMemo(() => {
    if (!flowData || flowData.length === 0) return {}
    const times = flowData.map((d: any) => formatInTimezone(d.time, timezone, 'HH:mm'))
    const pvData = flowData.map((d: any) => safeNum(d.pvPower))
    const battChargeData = flowData.map((d: any) => safeNum(d.batteryCharge))
    const battDischargeData = flowData.map((d: any) => -safeNum(d.batteryDischarge))
    const loadData = flowData.map((d: any) => -safeNum(d.loadPower))
    return {
      tooltip: {
        trigger: 'axis' as const,
        axisPointer: { type: 'cross' as const },
        formatter: (params: any) => {
          let html = `<div style="font-weight:600;margin-bottom:4px">${params[0].axisValue}</div>`
          params.forEach((p: any) => {
            const val = Math.abs(p.value)
            html += `<div>${p.marker} ${p.seriesName}: ${val.toFixed(0)} W</div>`
          })
          return html
        },
      },
      legend: { data: [t('mon.pvPower'), t('mon.batteryCharge'), t('mon.batteryDischarge'), t('mon.loadPower')], top: 0, itemGap: 16 },
      grid: { left: '3%', right: '4%', bottom: '12%', top: '45', containLabel: true },
      xAxis: { type: 'category' as const, data: times, axisLabel: { fontSize: 11 } },
      yAxis: {
        type: 'value' as const, name: t('mon.powerUnit'),
        axisLabel: { formatter: (v: number) => Math.abs(v) >= 1000 ? (Math.abs(v) / 1000).toFixed(1) + 'k' : Math.abs(v).toString() },
      },
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        { type: 'slider', start: 0, end: 100, height: 20, bottom: 8 },
      ],
      series: [
        {
          name: t('mon.pvPower'), type: 'line' as const, data: pvData, smooth: true, symbol: 'none',
          lineStyle: { color: '#f59e0b', width: 2 }, itemStyle: { color: '#f59e0b' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(245,158,11,0.3)' }, { offset: 1, color: 'rgba(245,158,11,0.02)' }] } },
        },
        {
          name: t('mon.batteryCharge'), type: 'line' as const, data: battChargeData, smooth: true, symbol: 'none',
          lineStyle: { color: '#22c55e', width: 2 }, itemStyle: { color: '#22c55e' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(34,197,94,0.3)' }, { offset: 1, color: 'rgba(34,197,94,0.02)' }] } },
        },
        {
          name: t('mon.batteryDischarge'), type: 'line' as const, data: battDischargeData, smooth: true, symbol: 'none',
          lineStyle: { color: '#3b82f6', width: 2 }, itemStyle: { color: '#3b82f6' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(59,130,246,0.02)' }, { offset: 1, color: 'rgba(59,130,246,0.2)' }] } },
        },
        {
          name: t('mon.loadPower'), type: 'line' as const, data: loadData, smooth: true, symbol: 'none',
          lineStyle: { color: '#ef4444', width: 2 }, itemStyle: { color: '#ef4444' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(239,68,68,0.02)' }, { offset: 1, color: 'rgba(239,68,68,0.2)' }] } },
        },
      ],
      markLine: { silent: true, lineStyle: { color: '#94a3b8', type: 'solid' as const, width: 1 }, data: [{ yAxis: 0 }], label: { show: false } },
    }
  }, [flowData, timezone])

  const [energyOverviewPeriod, setEnergyOverviewPeriod] = useState('day')

  const { data: energyStatsRes, isLoading: energyStatsLoading } = useQuery({
    queryKey: ['monitoring', 'energyOverview', selectedStationId, selectedDeviceSn, energyOverviewPeriod],
    queryFn: () => dashboardApi.getEnergyStats({
      type: energyOverviewPeriod,
      stationId: selectedStationId ? Number(selectedStationId) : undefined,
    }).then((r) => r.data),
    enabled: !!selectedStationId,
    refetchInterval: 15000,
  })
  const energyStatsRaw = (energyStatsRes?.data ?? energyStatsRes ?? {}) as any

  const { data: energyTrendRes } = useQuery({
    queryKey: ['monitoring', 'energyTrend', selectedStationId, energyOverviewPeriod],
    queryFn: () => dashboardApi.getTrend(energyOverviewPeriod).then((r) => r.data),
    enabled: !!selectedStationId,
    refetchInterval: 15000,
  })
  const energyTrendData = Array.isArray(energyTrendRes?.data)
    ? energyTrendRes.data
    : (Array.isArray(energyTrendRes?.data?.data) ? energyTrendRes.data.data : []) as any[]

  // 30日发电趋势数据
  const { data: trend30DaysRes } = useQuery({
    queryKey: ['monitoring', 'trend30Days', selectedStationId],
    queryFn: () => dashboardApi.getTrend('30days').then((r) => r.data),
    enabled: !!selectedStationId,
  })
  const trend30DaysData = Array.isArray(trend30DaysRes?.data)
    ? trend30DaysRes.data
    : (Array.isArray(trend30DaysRes?.data?.data) ? trend30DaysRes.data.data : []) as any[]

  const energyOverviewOption = useMemo(() => {
    const es = energyStatsRaw
    const dates = es?.dates ?? []
    if (dates.length === 0) return {}
    const pvArr = es.pv ?? []
    const chargeArr = es.batteryCharge ?? []
    const dischargeArr = es.batteryDischarge ?? []
    const loadMap: Record<string, number> = {}
    for (const item of energyTrendData) {
      loadMap[item.date] = safeNum(item.load)
    }
    const seriesConfig = [
      { name: t('dash.pvEnergy'), color: '#f59e0b', data: pvArr },
      { name: t('dash.battChargeEnergy'), color: '#22c55e', data: chargeArr },
      { name: t('dash.battDischargeEnergy'), color: '#3b82f6', data: dischargeArr },
      { name: t('dash.loadConsumption'), color: '#ef4444', data: dates.map((d: string) => loadMap[d] ?? 0) },
    ]
    return {
      tooltip: { trigger: 'axis' as const, axisPointer: { type: 'shadow' as const } },
      legend: { data: seriesConfig.map((s) => s.name), top: 0, itemGap: 16 },
      grid: { left: '3%', right: '4%', bottom: '12%', top: '45', containLabel: true },
      xAxis: { type: 'category' as const, data: dates, axisLabel: { fontSize: 11 } },
      yAxis: { type: 'value' as const, name: 'kWh' },
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        { type: 'slider', start: 0, end: 100, height: 20, bottom: 8 },
      ],
      series: seriesConfig.map((s) => ({
        name: s.name, type: 'bar' as const,
        data: s.data.map((v: any) => parseFloat(safeNum(v).toFixed(2))),
        itemStyle: { color: s.color, borderRadius: [3, 3, 0, 0] },
        barMaxWidth: 20,
      })),
    }
  }, [energyStatsRaw, energyTrendData, t])

  // 30日发电趋势图表配置
  const trend30DaysOption = useMemo(() => {
    if (!trend30DaysData || trend30DaysData.length === 0) return {}
    return {
      tooltip: { trigger: 'axis' as const },
      grid: { left: '3%', right: '4%', bottom: '12%', top: '45', containLabel: true },
      xAxis: {
        type: 'category' as const,
        data: trend30DaysData.map((d: any) => dayjs(d.date).format('MM-DD')),
        axisLabel: { fontSize: 11, interval: 2 },
      },
      yAxis: { type: 'value' as const, name: 'kWh' },
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        { type: 'slider', start: 0, end: 100, height: 20, bottom: 8 },
      ],
      series: [{
        name: t('station.genEnergy'),
        type: 'line' as const,
        data: trend30DaysData.map((d: any) => safeNum(d.energy)),
        smooth: true,
        symbol: 'none',
        lineStyle: { color: '#f59e0b', width: 2 },
        itemStyle: { color: '#f59e0b' },
        areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(245,158,11,0.3)' }, { offset: 1, color: 'rgba(245,158,11,0.02)' }] } },
      }],
    }
  }, [trend30DaysData, t])

  const renderGenerationStats = () => {
    if (!selectedStationId) {
      return <Empty description={t('mon.pleaseSelectStationFirst')} />
    }
    return (
      <>
        <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}
          title={<Space><LineChartOutlined style={{ color: '#1677ff' }} /><span>{t('dash.powerTrend')}</span></Space>}
          extra={
            <Space>
              <DatePicker value={dayjs(flowDate)} onChange={(d) => d && setFlowDate(dayjs(d).tz(timezone).format('YYYY-MM-DD'))} allowClear={false} style={{ width: 150 }} />
              <Button size="small" onClick={() => setFlowDate(dayjs().tz(timezone).subtract(1, 'day').format('YYYY-MM-DD'))}>{t('mon.yesterday')}</Button>
              <Button size="small" onClick={() => setFlowDate(dayjs().tz(timezone).format('YYYY-MM-DD'))}>{t('mon.today')}</Button>
            </Space>
          }
        >
          {flowLoading ? (
            <div style={{ height: 400, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Spin /></div>
          ) : flowData.length > 0 ? (
            <ReactECharts option={energyFlowOption} style={{ height: 400 }} />
          ) : (
            <Empty description={t('dash.noEnergyData')} />
          )}
        </Card>

        {/* 30日发电趋势 */}
        <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}
          title={<Space><LineChartOutlined style={{ color: '#fa8c16' }} /><span>{t('station.genTrend30Days')}</span></Space>}
        >
          {trend30DaysData.length > 0 ? (
            <ReactECharts option={trend30DaysOption} style={{ height: 340 }} />
          ) : (
            <Empty description={t('dash.noEnergyData')} />
          )}
        </Card>

        <Card bordered={false} style={{ borderRadius: 12 }}
          title={<Space><BarChartOutlined style={{ color: '#722ed1' }} /><span>{t('dash.energyOverview')}</span></Space>}
          extra={
            <Segmented size="small" value={energyOverviewPeriod} onChange={(v) => setEnergyOverviewPeriod(v as string)}
              options={[
                { label: t('dash.last7Days'), value: 'day' },
                { label: t('dash.last30Days'), value: '30days' },
                { label: t('dash.last4Weeks'), value: 'week' },
                { label: t('dash.last12Months'), value: 'month' },
              ]}
            />
          }
        >
          {energyStatsLoading ? (
            <div style={{ height: 340, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Spin /></div>
          ) : (energyStatsRaw?.dates?.length ?? 0) > 0 ? (
            <ReactECharts option={energyOverviewOption} style={{ height: 340 }} />
          ) : (
            <Empty description={t('dash.noEnergyData')} />
          )}
        </Card>
      </>
    )
  }

  /* ============================================================
   *  Tab 配置
   * ============================================================ */

  const tabItems = [
    { key: 'params', label: <span><ExperimentOutlined /> {t('mon.runParams')}</span>, children: renderRunningParams() },
    { key: 'energy', label: <span><ThunderboltOutlined /> {t('dash.generationStats')}</span>, children: renderGenerationStats() },
    { key: 'curve', label: <span><LineChartOutlined /> {t('mon.curveCompare')}</span>, children: renderCurveComparison() },
    { key: 'history', label: <span><TableOutlined /> {t('mon.historyData')}</span>, children: renderHistoryData() },
    { key: 'alarms', label: <span><AlertOutlined /> {t('mon.historyEvents')}</span>, children: renderAlarmTimeline() },
  ]

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Col>
          <Title level={4} style={{ margin: 0 }}>
            <DashboardOutlined style={{ marginRight: 8 }} />
            {t('mon.title')}
          </Title>
        </Col>
        <Col>
          <Space>
            <Tag icon={<ReloadOutlined />} color="processing">{t('mon.autoRefresh')}</Tag>
          </Space>
        </Col>
      </Row>

      {/* 电站选择器 */}
      <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}>
        <Row gutter={[16, 12]} align="top">
          <Col xs={24} sm={12} md={8} lg={6}>
            <div>
              <Text strong>
                <ApartmentOutlined /> {t('mon.selectStation')}:
              </Text>
            </div>
            <Select
              showSearch
              optionFilterProp="label"
              placeholder={t('mon.selectStationPlaceholder')}
              style={{ width: '100%', maxWidth: 280, marginTop: 4 }}
              value={selectedStationId || undefined}
              onChange={(v) => {
                setSelectedStationId(v)
                setSelectedDeviceSn('')
              }}
              options={stationList.map((s) => ({
                label: s.name,
                value: String(s.id),
              }))}
              allowClear
            />
          </Col>
          {deviceList.length > 0 && (
            <Col xs={24} sm={12} md={8} lg={6}>
              <div>
                <Text strong>{t('mon.selectInverter')}:</Text>
              </div>
              <Select
                showSearch
                optionFilterProp="label"
                placeholder={t('mon.selectInverterPlaceholder')}
                style={{ width: '100%', maxWidth: 300, marginTop: 4 }}
                value={selectedDeviceSn || undefined}
                onChange={setSelectedDeviceSn}
                options={deviceList.map((d) => ({
                  label: `${d.sn} (${d.model || '-'})`,
                  value: d.sn,
                }))}
              />
            </Col>
          )}
          {selectedStation && (
            <>
              <Col>
                <Space split={<span style={{ color: '#d9d9d9' }}>|</span>}>
                  {selectedStation.location && (
                    <Text type="secondary">
                      <EnvironmentOutlined /> {selectedStation.location}
                    </Text>
                  )}
                  {selectedStation.address && (
                    <Text type="secondary">
                      <EnvironmentOutlined /> {selectedStation.address}
                    </Text>
                  )}
                  {selectedStation.capacity != null && (
                    <Text type="secondary">
                      {t('mon.capacity')}: <Text strong>{selectedStation.capacity} kW</Text>
                    </Text>
                  )}
                  <Text type="secondary">
                    {t('mon.deviceCount')}: <Text strong>{deviceList.length}</Text>
                  </Text>
                  <Text type="secondary">
                    {t('mon.onlineCount')}: <Text strong style={{ color: '#52c41a' }}>
                      {deviceList.filter((d) => d.status === 1).length}
                    </Text>
                  </Text>
                </Space>
              </Col>
            </>
          )}
        </Row>
      </Card>

      {!selectedStationId ? (
        <Card bordered={false} style={{ borderRadius: 12, padding: 60 }}>
          <Empty description={t('mon.pleaseSelectStation')} />
        </Card>
      ) : (
        <Tabs defaultActiveKey="params" items={tabItems} size="large" />
      )}
    </div>
  )
}

export default MonitoringPage
