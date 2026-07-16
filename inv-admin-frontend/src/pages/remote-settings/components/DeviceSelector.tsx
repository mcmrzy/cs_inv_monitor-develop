import React, { useState } from 'react'
import { Select, Spin, Card, Tag, Row, Col, Typography, Button } from 'antd'
import { ReloadOutlined } from '@ant-design/icons'
import { useQuery } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import api from '@/services/api'
import type { DeviceItem } from '../types'

const { Text } = Typography

interface DeviceSelectorProps {
  selectedSn: string | null
  onDeviceChange: (sn: string) => void
  onRead: () => void
  reading: boolean
}

interface StationItem {
  id: number
  name: string
}

const DeviceSelector: React.FC<DeviceSelectorProps> = ({ selectedSn, onDeviceChange, onRead, reading }) => {
  const [selectedStationId, setSelectedStationId] = useState<number | null>(null)

  // 电站列表
  const { data: stationsData, isLoading: stationsLoading } = useQuery({
    queryKey: ['stations', 'all'],
    queryFn: () =>
      api.get('/stations', { params: { all: true } }).then((r) => {
        const d = r.data?.data ?? r.data
        return (d?.items ?? (Array.isArray(d) ? d : [])) as StationItem[]
      }),
    staleTime: 120_000,
  })
  const stations = stationsData ?? []

  // 设备列表（按电站过滤）
  const { data: devicesData, isLoading: devicesLoading } = useQuery({
    queryKey: ['devices', 'by-station', selectedStationId],
    queryFn: () =>
      deviceApi.getDevices({
        page: 1,
        page_size: 200,
        ...(selectedStationId ? { station_id: selectedStationId } : {}),
      }).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (d?.items ?? (Array.isArray(d) ? d : [])) as DeviceItem[]
      }),
    staleTime: 60_000,
    enabled: selectedStationId !== null,
  })
  const devices = devicesData ?? []
  const selectedDevice = devices.find((d) => d.sn === selectedSn) ?? null
  const isOnline = selectedDevice ? selectedDevice.status === 1 : false

  const handleStationChange = (val: string | undefined) => {
    if (val) {
      const id = Number(val.split(':')[0])
      setSelectedStationId(id)
    } else {
      setSelectedStationId(null)
    }
    onDeviceChange('')
  }

  return (
    <div>
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col>
          <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 4 }}>先选择电站</Text>
          <Select
            showSearch
            allowClear
            placeholder="选择电站"
            value={selectedStationId !== null ? stations.find(s => s.id === selectedStationId) ? `${selectedStationId}:${stations.find(s => s.id === selectedStationId)!.name}` : undefined : undefined}
            onChange={handleStationChange}
            loading={stationsLoading}
            notFoundContent={stationsLoading ? <Spin size="small" /> : '暂无电站'}
            style={{ minWidth: 240 }}
            filterOption={(input, option) =>
              (option?.label as string)?.toLowerCase().includes(input.toLowerCase()) ?? false
            }
            options={stations.map((s) => ({
              value: `${s.id}:${s.name}`,
              label: s.name,
            }))}
          />
        </Col>
        <Col>
          <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 4 }}>再选择设备</Text>
          <Select
            showSearch
            allowClear
            placeholder={selectedStationId ? '选择设备 (SN)' : '请先选择电站'}
            value={selectedSn}
            onChange={(v) => onDeviceChange(v ?? '')}
            loading={devicesLoading}
            disabled={selectedStationId === null}
            notFoundContent={devicesLoading ? <Spin size="small" /> : '暂无设备'}
            style={{ minWidth: 280 }}
            filterOption={(input, option) =>
              (option?.label as string)?.toLowerCase().includes(input.toLowerCase()) ?? false
            }
            options={devices.map((d) => ({
              value: d.sn,
              label: `${d.sn}  (${d.model || d.device_type || ''})`,
            }))}
          />
        </Col>
      </Row>

      {selectedDevice && (
        <Card bordered={false} style={{ borderRadius: 12 }}>
          <Row align="middle" justify="space-between">
            <Col>
              <Row gutter={24}>
                <Col>
                  <Text type="secondary" style={{ fontSize: 12 }}>SN</Text>
                  <div style={{ fontWeight: 600 }}>{selectedDevice.sn}</div>
                </Col>
                <Col>
                  <Text type="secondary" style={{ fontSize: 12 }}>在线状态</Text>
                  <div>
                    <Tag color={isOnline ? '#22c55e' : '#8c8c8c'}>
                      {isOnline ? '在线' : '离线'}
                    </Tag>
                  </div>
                </Col>
                <Col>
                  <Text type="secondary" style={{ fontSize: 12 }}>型号</Text>
                  <div>{selectedDevice.model || selectedDevice.device_type || '-'}</div>
                </Col>
              </Row>
            </Col>
            <Col>
              <Button type="primary" icon={<ReloadOutlined />} onClick={onRead} loading={reading}>
                读取当前设置
              </Button>
            </Col>
          </Row>
        </Card>
      )}
    </div>
  )
}

export default DeviceSelector
