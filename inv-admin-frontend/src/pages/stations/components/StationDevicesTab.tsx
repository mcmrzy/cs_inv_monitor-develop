import React, { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Row, Col, Card, Input, Select, Button, Tag, Space, Spin, Empty, Typography, Badge } from 'antd'
import { SearchOutlined, ReloadOutlined, DesktopOutlined } from '@ant-design/icons'
import { deviceApi } from '@/services/deviceApi'
import { DEVICE_STATUS_MAP } from '@/utils/constants'
import { safeNum } from '@/utils/format'
import { formatInTimezone } from '@/utils/timezone'
import DeviceRealtimeModal from './DeviceRealtimeModal'

const { Text } = Typography

interface StationDevicesTabProps {
  stationId: number
  timezone: string
}

interface DeviceItem {
  id: string
  sn: string
  model: string
  model_id?: number
  rated_power?: number
  status: number | string
  last_online_at?: string
  firmware_version?: string
  firmware_dsp?: string
  firmware_bms?: string
  stationId?: string
  [key: string]: any
}

const StationDevicesTab: React.FC<StationDevicesTabProps> = ({ stationId, timezone }) => {
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<string | undefined>(undefined)
  const [modalSn, setModalSn] = useState<string | null>(null)

  const { data: devices, isLoading, refetch } = useQuery({
    queryKey: ['station-devices-list', stationId],
    queryFn: () => deviceApi.getDevices({ station_id: stationId, page_size: 200 }).then(r => {
      const d = r.data?.data ?? r.data
      return (d?.items ?? (Array.isArray(d) ? d : [])) as DeviceItem[]
    }),
    enabled: !!stationId,
  })

  const { data: realtimeData } = useQuery({
    queryKey: ['station-devices-rt', stationId],
    queryFn: async () => {
      const results: Record<string, any> = {}
      await Promise.allSettled(
        (devices ?? []).map(async (dev) => {
          try {
            const res = await deviceApi.getRealtime(dev.sn)
            results[dev.sn] = res.data?.data ?? res.data ?? {}
          } catch { /* ignore */ }
        }),
      )
      return results
    },
    enabled: !!devices?.length,
    refetchInterval: 15000,
  })

  const filteredDevices = useMemo(() => {
    if (!devices) return []
    return devices.filter(dev => {
      const matchSearch = !search
        || dev.sn.toLowerCase().includes(search.toLowerCase())
        || (dev.model ?? '').toLowerCase().includes(search.toLowerCase())
      const matchStatus = statusFilter === undefined
        || String(dev.status) === statusFilter
      return matchSearch && matchStatus
    })
  }, [devices, search, statusFilter])

  const getRealtimePower = (sn: string): number | null => {
    const rt = realtimeData?.[sn]
    if (!rt) return null
    // 尝试多种字段路径
    const acPower = rt?.ac?.data?.power ?? rt?.ac_power ?? rt?.power
    const pvPower = rt?.pv?.data?.pv_total_power ?? rt?.pv_total_power
    return safeNum(acPower || pvPower) || null
  }

  const getStatusCfg = (status: number | string) => {
    const key = String(status)
    return DEVICE_STATUS_MAP[key] ?? DEVICE_STATUS_MAP['0']
  }

  return (
    <>
      {/* 工具栏 */}
      <Row justify="space-between" align="middle" style={{ marginBottom: 16 }}>
        <Col>
          <Space>
            <Input
              placeholder="搜索 SN / 型号"
              prefix={<SearchOutlined />}
              allowClear
              value={search}
              onChange={e => setSearch(e.target.value)}
              style={{ width: 220 }}
              size="small"
            />
            <Select
              placeholder="状态"
              allowClear
              style={{ width: 120 }}
              size="small"
              value={statusFilter}
              onChange={v => setStatusFilter(v)}
              options={[
                { label: '在线', value: '1' },
                { label: '离线', value: '0' },
                { label: '故障', value: '2' },
              ]}
            />
          </Space>
        </Col>
        <Col>
          <Button icon={<ReloadOutlined />} size="small" onClick={() => refetch()}>刷新</Button>
        </Col>
      </Row>

      <Spin spinning={isLoading}>
        {filteredDevices.length === 0 && !isLoading ? (
          <Card bordered={false} style={{ borderRadius: 12, textAlign: 'center', padding: '48px 24px' }}>
            <Empty description="暂无关联设备" />
          </Card>
        ) : (
          <Row gutter={[12, 12]}>
            {filteredDevices.map(dev => {
              const statusCfg = getStatusCfg(dev.status)
              const rtPower = getRealtimePower(dev.sn)
              const fw = dev.firmware_version || dev.firmware_dsp || '-'
              return (
                <Col xs={24} sm={12} md={8} key={dev.sn}>
                  <Card
                    hoverable
                    bordered={false}
                    style={{ borderRadius: 12, cursor: 'pointer', height: '100%' }}
                    styles={{ body: { padding: '16px' } }}
                    onClick={() => setModalSn(dev.sn)}
                  >
                    <Row justify="space-between" align="middle" style={{ marginBottom: 8 }}>
                      <Col>
                        <Text strong style={{ fontFamily: 'monospace', fontSize: 14 }}>{dev.sn}</Text>
                      </Col>
                      <Col>
                        <Badge
                          status={dev.status === 1 || dev.status === 'online' ? 'processing' : dev.status === 2 || dev.status === 'fault' ? 'error' : 'default'}
                        />
                        <Tag color={statusCfg.color} style={{ marginLeft: 4 }}>{statusCfg.label}</Tag>
                      </Col>
                    </Row>
                    <div style={{ marginBottom: 4 }}>
                      <Tag>{dev.model || '-'}</Tag>
                      {dev.rated_power != null && <Tag color="blue">{dev.rated_power}W</Tag>}
                    </div>
                    <div style={{ fontSize: 12, color: '#999', marginBottom: 4 }}>
                      <DesktopOutlined /> 固件: {fw}
                    </div>
                    <div style={{ fontSize: 12, color: '#999' }}>
                      最后在线: {formatInTimezone(dev.last_online_at, timezone, 'MM-DD HH:mm:ss')}
                    </div>
                    {rtPower !== null && (
                      <div style={{ marginTop: 8, fontSize: 13, color: '#1677ff', fontWeight: 600 }}>
                        实时功率: {rtPower.toFixed(0)} W
                      </div>
                    )}
                  </Card>
                </Col>
              )
            })}
          </Row>
        )}
      </Spin>

      <DeviceRealtimeModal
        open={!!modalSn}
        deviceSn={modalSn}
        onClose={() => setModalSn(null)}
      />
    </>
  )
}

export default StationDevicesTab
