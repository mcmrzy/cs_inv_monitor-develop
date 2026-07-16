import React, { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Modal, Card, Row, Col, Statistic, Spin, Empty, Typography, Tag } from 'antd'
import {
  ThunderboltOutlined, SwapOutlined, CloudOutlined,
  ExperimentOutlined, AlertOutlined, FieldTimeOutlined,
  BarChartOutlined,
} from '@ant-design/icons'
import { deviceApi } from '@/services/deviceApi'
import { safeNum } from '@/utils/format'

const { Text } = Typography

interface DeviceRealtimeModalProps {
  open: boolean
  deviceSn: string | null
  onClose: () => void
}

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

interface FieldDef {
  key: string
  label: string
  unit?: string
  precision?: number
}

const GROUP_FIELDS: Record<string, { label: string; aliases: string[]; fields: FieldDef[] }> = {
  ac: {
    label: '交流参数',
    aliases: ['ac', 'AC', 'ac_phase'],
    fields: [
      { key: 'voltage', label: '电压', unit: 'V', precision: 1 },
      { key: 'current', label: '电流', unit: 'A', precision: 2 },
      { key: 'power', label: '功率', unit: 'W', precision: 0 },
      { key: 'frequency', label: '频率', unit: 'Hz', precision: 2 },
      { key: 'load_percent', label: '负载率', unit: '%', precision: 1 },
      { key: 'power_factor', label: '功率因数', precision: 3 },
    ],
  },
  batt: {
    label: '电池参数',
    aliases: ['batt', 'battery', 'bat', 'BAT'],
    fields: [
      { key: 'soc', label: 'SOC', unit: '%', precision: 1 },
      { key: 'voltage', label: '电压', unit: 'V', precision: 2 },
      { key: 'current', label: '电流', unit: 'A', precision: 2 },
      { key: 'power', label: '功率', unit: 'W', precision: 0 },
      { key: 'temperature', label: '温度', unit: '°C', precision: 1 },
      { key: 'cycle_count', label: '循环次数', precision: 0 },
      { key: 'capacity', label: '容量', unit: '%', precision: 1 },
    ],
  },
  pv: {
    label: '光伏参数',
    aliases: ['pv', 'PV', 'solar'],
    fields: [
      { key: 'pv1_voltage', label: 'PV1电压', unit: 'V', precision: 1 },
      { key: 'pv2_voltage', label: 'PV2电压', unit: 'V', precision: 1 },
      { key: 'pv1_power', label: 'PV1功率', unit: 'W', precision: 0 },
      { key: 'pv2_power', label: 'PV2功率', unit: 'W', precision: 0 },
      { key: 'pv_total_power', label: 'PV总功率', unit: 'W', precision: 0 },
    ],
  },
  sys: {
    label: '系统状态',
    aliases: ['sys', 'system', 'SYS', 'inverter'],
    fields: [
      { key: 'inverter_temp', label: '逆变器温度', unit: '°C', precision: 1 },
      { key: 'efficiency', label: '效率', unit: '%', precision: 1 },
      { key: 'run_status', label: '运行状态' },
      { key: 'fault_code', label: '故障码' },
      { key: 'total_run_time', label: '累计运行时间', unit: 'h', precision: 0 },
    ],
  },
}

const getNestedValue = (data: any, category: string, field: string): any => {
  if (!data) return undefined
  const cat = data[category]
  if (cat?.data?.[field] !== undefined) return cat.data[field]
  if (cat?.[field] !== undefined) return cat[field]
  if (data[field] !== undefined) return data[field]
  return undefined
}

const findGroupData = (data: any, aliases: string[]): Record<string, any> | null => {
  if (!data) return null
  for (const alias of aliases) {
    const cat = data[alias]
    if (cat) {
      if (cat.data && typeof cat.data === 'object') return cat.data
      if (typeof cat === 'object' && !Array.isArray(cat)) return cat
    }
  }
  return null
}

const DeviceRealtimeModal: React.FC<DeviceRealtimeModalProps> = ({ open, deviceSn, onClose }) => {
  const { data: rtData, isLoading } = useQuery({
    queryKey: ['device-realtime-modal', deviceSn],
    queryFn: () => deviceApi.getRealtime(deviceSn!).then(res => res.data?.data ?? res.data ?? {}),
    enabled: !!deviceSn && open,
    refetchInterval: open ? 10000 : false,
  })

  const groupedDisplay = useMemo(() => {
    if (!rtData) return []
    const result: { groupKey: string; label: string; fields: { def: FieldDef; value: any }[] }[] = []

    for (const [groupKey, groupDef] of Object.entries(GROUP_FIELDS)) {
      const groupData = findGroupData(rtData, groupDef.aliases)
      const fieldValues = groupDef.fields
        .map(def => {
          let value = getNestedValue(rtData, groupKey, def.key)
          if (value === undefined && groupData) {
            value = groupData[def.key]
          }
          return { def, value }
        })
        .filter(f => f.value !== undefined && f.value !== null && f.value !== '')

      if (fieldValues.length > 0) {
        result.push({ groupKey, label: groupDef.label, fields: fieldValues })
      }
    }
    return result
  }, [rtData])

  return (
    <Modal
      title={
        <span>
          <ThunderboltOutlined style={{ marginRight: 8 }} />
          设备实时数据 {deviceSn && <Tag style={{ marginLeft: 8, fontFamily: 'monospace' }}>{deviceSn}</Tag>}
        </span>
      }
      open={open}
      onCancel={onClose}
      footer={null}
      width={720}
      destroyOnHidden
    >
      <Spin spinning={isLoading}>
        {groupedDisplay.length === 0 && !isLoading ? (
          <Empty description="暂无实时数据" style={{ padding: '24px 0' }} />
        ) : (
          <Row gutter={[16, 16]}>
            {groupedDisplay.map((group, groupIdx) => {
              const palette = GROUP_COLOR_PALETTE[groupIdx % GROUP_COLOR_PALETTE.length]
              return (
                <Col xs={24} sm={12} key={group.groupKey}>
                  <Card
                    bordered={false}
                    size="small"
                    title={<span style={{ color: palette.color }}>{palette.icon} {group.label}</span>}
                    style={{ borderRadius: 12, background: palette.bg, height: '100%' }}
                  >
                    <Row gutter={[12, 12]}>
                      {group.fields.map(({ def, value }) => (
                        <Col span={Math.floor(24 / Math.min(group.fields.length, 3))} key={def.key}>
                          <Statistic
                            title={<Text style={{ fontSize: 12 }}>{def.label}</Text>}
                            value={typeof value === 'number' ? value : safeNum(value) || value}
                            precision={def.precision ?? (typeof value === 'number' ? 1 : undefined)}
                            suffix={def.unit}
                            valueStyle={{ color: palette.color, fontSize: 18 }}
                          />
                        </Col>
                      ))}
                    </Row>
                  </Card>
                </Col>
              )
            })}
          </Row>
        )}
      </Spin>
    </Modal>
  )
}

export default DeviceRealtimeModal
