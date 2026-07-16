import React from 'react'
import { Select, Spin, Card, Tag, Row, Col, Typography } from 'antd'
import { useQuery } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import type { DeviceItem } from '../types'

const { Text } = Typography

interface DeviceSelectorProps {
  selectedSn: string | null
  onDeviceChange: (sn: string) => void
}

const PRIMARY = '#4f6ef7'

const DeviceSelector: React.FC<DeviceSelectorProps> = ({ selectedSn, onDeviceChange }) => {
  const { data, isLoading } = useQuery({
    queryKey: queryKeys.devices.list({ page: 1, page_size: 200 }),
    queryFn: () =>
      deviceApi.getDevices({ page: 1, page_size: 200 }).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (d?.items ?? (Array.isArray(d) ? d : [])) as DeviceItem[]
      }),
    staleTime: 60_000,
  })

  const devices = data ?? []
  const selectedDevice = devices.find((d) => d.sn === selectedSn) ?? null
  const isOnline = selectedDevice ? selectedDevice.status === 1 : false

  return (
    <div>
      <Select
        showSearch
        allowClear
        placeholder="选择设备 (SN)"
        value={selectedSn}
        onChange={(v) => onDeviceChange(v ?? '')}
        loading={isLoading}
        notFoundContent={isLoading ? <Spin size="small" /> : '暂无设备'}
        style={{ minWidth: 320 }}
        filterOption={(input, option) =>
          (option?.label as string)?.toLowerCase().includes(input.toLowerCase()) ?? false
        }
        options={devices.map((d) => ({
          value: d.sn,
          label: `${d.sn}  (${d.model || d.device_type || ''})`,
        }))}
      />

      {selectedDevice && (
        <Card bordered={false} style={{ borderRadius: 12, marginTop: 16 }}>
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
            <Col>
              <Text type="secondary" style={{ fontSize: 12 }}>固件版本</Text>
              <div style={{ color: PRIMARY }}>
                {selectedDevice.main_version || selectedDevice.firmware_arm || '-'}
              </div>
            </Col>
          </Row>
        </Card>
      )}
    </div>
  )
}

export default DeviceSelector
