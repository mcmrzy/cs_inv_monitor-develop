import React, { useState, useMemo } from 'react'
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
  'pv_total_power', 'ac_power', 'battery_soc', 'battery_power', 'inverter_temp',
]

/** 字段标签映射 */
const FIELD_LABELS: Record<string, string> = {
  pv_total_power: 'PV总功率 (W)',
  ac_power: 'AC功率 (W)',
  battery_soc: '电池SOC (%)',
  battery_power: '电池功率 (W)',
  inverter_temp: '逆变器温度 (°C)',
  pv1_power: 'PV1功率 (W)',
  pv2_power: 'PV2功率 (W)',
  grid_power: '电网功率 (W)',
  load_power: '负载功率 (W)',
  daily_pv: '日发电量 (kWh)',
  daily_charge: '日充电量 (kWh)',
  daily_discharge: '日放电量 (kWh)',
  daily_load: '日负载用电 (kWh)',
}

const StationHistoryTab: React.FC<StationHistoryTabProps> = ({ stationId, timezone }) => {
  const { t } = useTranslation()
  const [selectedSn, setSelectedSn] = useState<string | undefined>(undefined)
  const [dateRange, setDateRange] = useState<[dayjs.Dayjs, dayjs.Dayjs]>([
    dayjs().subtract(1, 'day'),
    dayjs(),
  ])
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
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
      return { items: d?.items ?? (Array.isArray(d) ? d : []), total: d?.total ?? 0 }
    }),
    enabled: !!selectedSn && !!dateRange[0] && !!dateRange[1],
  })

  const items = historyRes?.items ?? []
  const total = historyRes?.total ?? 0

  // 从数据中提取所有可用字段
  const allFields = useMemo(() => {
    const fieldSet = new Set<string>()
    items.forEach((item: any) => {
      Object.keys(item).forEach(key => {
        if (key !== 'id' && key !== 'time' && key !== 'created_at' && key !== 'updated_at') {
          fieldSet.add(key)
        }
      })
    })
    return Array.from(fieldSet)
  }, [items])

  // 构建表格列
  const columns: ColumnsType<any> = useMemo(() => {
    const timeCol = {
      title: '时间',
      dataIndex: 'time',
      key: 'time',
      width: 180,
      fixed: 'left' as const,
      render: (v: string) => formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm'),
    }
    const dataCols = visibleFields.map(field => ({
      title: FIELD_LABELS[field] || field,
      dataIndex: field,
      key: field,
      width: 140,
      render: (v: unknown) => {
        const n = safeNum(v)
        return n !== 0 ? n.toFixed(2) : '--'
      },
    }))
    return [timeCol, ...dataCols]
  }, [visibleFields])

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
                  label: FIELD_LABELS[f] || f,
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
