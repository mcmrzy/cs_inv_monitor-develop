import React, { useState, useMemo, useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Row, Col, Card, Select, DatePicker, Button, Table, Space } from 'antd'
import { ReloadOutlined, DownloadOutlined } from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import dayjs from 'dayjs'
import { deviceApi } from '@/services/deviceApi'
import { safeNum } from '@/utils/format'
import { formatInTimezone } from '@/utils/timezone'
import useTranslation from '@/hooks/useTranslation'

const { RangePicker } = DatePicker

interface StationHistoryTabProps {
  stationId: number
  timezone: string
}

/** 默认可见的数据字段 */
const DEFAULT_VISIBLE_FIELDS = [
  'pv_total_power', 'ac_active_power', 'battery_soc', 'battery_power', 'inverter_temperature',
]

/** 字段标签映射 key —— 覆盖 device_telemetry_3min 所有数据列 */
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
  const [visibleFields, setVisibleFields] = useState<string[]>(DEFAULT_VISIBLE_FIELDS)

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

  // 获取历史遥测数据
  const { data: historyRes, isLoading } = useQuery({
    queryKey: ['station-history', selectedSn, page, pageSize, dateRange[0]?.toISOString(), dateRange[1]?.toISOString()],
    queryFn: () => deviceApi.getTelemetry(selectedSn!, {
      page,
      page_size: pageSize,
      startTime: dateRange[0].toISOString(),
      endTime: dateRange[1].toISOString(),
      granularity: 'hour',
      sort: 'desc',
    }).then(r => {
      const d = r.data?.data ?? r.data
      if (Array.isArray(d)) return { items: d, total: d.length }
      return { items: d?.items ?? [], total: d?.total ?? 0 }
    }),
    enabled: !!selectedSn && !!dateRange[0] && !!dateRange[1],
  })

  const items = historyRes?.items ?? []
  const total = historyRes?.total ?? 0

  // 从数据中提取所有可用字段（排除元数据字段）
  const EXCLUDE_FIELDS = new Set([
    'id', 'time', 'created_at', 'updated_at', 'event_time', 'received_at',
    'protocol_version', 'sequence_no', 'quality_flags', 'topic', 'data_hash', 'raw_envelope',
    'device_sn',
  ])
  const allFields = useMemo(() => {
    const fieldSet = new Set<string>()
    items.forEach((item: any) => {
      Object.keys(item).forEach(key => {
        if (!EXCLUDE_FIELDS.has(key)) {
          fieldSet.add(key)
        }
      })
    })
    return Array.from(fieldSet)
  }, [items])

  // 构建表格列
  const columns: ColumnsType<any> = useMemo(() => {
    const timeCol = {
      title: t('common.time'),
      dataIndex: 'time',
      key: 'time',
      width: 180,
      fixed: 'left' as const,
      render: (v: string) => formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm'),
    }
    const dataCols = visibleFields.map(field => ({
      title: FIELD_LABEL_KEYS[field] ? t(FIELD_LABEL_KEYS[field]) : field,
      dataIndex: field,
      key: field,
      width: 140,
      render: (v: unknown) => {
        if (v === null || v === undefined || v === '') return '--'
        const n = safeNum(v)
        if (!Number.isFinite(n)) return '--'
        return n !== 0 ? n.toFixed(2) : '0.00'
      },
    }))
    return [timeCol, ...dataCols]
  }, [visibleFields, t, timezone])

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
      <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}>
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
            <Button icon={<ReloadOutlined />} onClick={() => setPage(1)}>
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

        {/* 字段选择器 */}
        {allFields.length > 0 && (
          <Row style={{ marginTop: 12 }}>
            <Col span={24}>
              <span style={{ marginRight: 8, fontSize: 13, color: '#666' }}>{t('station.selectFields')}:</span>
              <Select
                mode="multiple"
                value={visibleFields}
                onChange={setVisibleFields}
                style={{ minWidth: 400 }}
                maxTagCount={5}
                options={allFields.map(f => ({
                  label: FIELD_LABEL_KEYS[f] ? t(FIELD_LABEL_KEYS[f]) : f,
                  value: f,
                }))}
              />
            </Col>
          </Row>
        )}
      </Card>

      {/* 数据表格 */}
      <Card bordered={false} style={{ borderRadius: 12 }}>
        <Table
          columns={columns}
          dataSource={items}
          loading={isLoading}
          rowKey={(r: any) => r.id || r.time}
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
      </Card>
    </>
  )
}

export default StationHistoryTab
