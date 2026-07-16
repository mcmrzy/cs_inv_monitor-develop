import React, { useState } from 'react'
import { Button, Card, Empty, Typography, Space, App } from 'antd'
import { ReloadOutlined } from '@ant-design/icons'
import { useQuery } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import DeviceSelector from './components/DeviceSelector'
import GeneralSection from './components/GeneralSection'
import ApplicationSection from './components/ApplicationSection'
import ParallelSection from './components/ParallelSection'
import ChargeSection from './components/ChargeSection'
import DischargeSection from './components/DischargeSection'
import OtherSection from './components/OtherSection'
import ResetSection from './components/ResetSection'
import type { DeviceItem } from './types'

const { Title, Text } = Typography

const RemoteSettingsPage: React.FC = () => {
  const { message } = App.useApp()
  const [selectedSn, setSelectedSn] = useState<string | null>(null)
  const [reading, setReading] = useState(false)

  const { data: devicesData } = useQuery({
    queryKey: queryKeys.devices.list({ page: 1, page_size: 200 }),
    queryFn: () =>
      deviceApi.getDevices({ page: 1, page_size: 200 }).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (d?.items ?? (Array.isArray(d) ? d : [])) as DeviceItem[]
      }),
    staleTime: 60_000,
  })

  const devices = devicesData ?? []
  const selectedDevice = devices.find((d) => d.sn === selectedSn) ?? null

  const handleRead = () => {
    setReading(true)
    message.info('正在读取设备当前设置...')
    setTimeout(() => setReading(false), 1500)
  }

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        远程参数设置
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 24 }}>
        远程配置逆变器运行参数，支持实时下发与生效
      </Text>

      <DeviceSelector selectedSn={selectedSn} onDeviceChange={setSelectedSn} />

      {selectedDevice && (
        <div style={{ marginTop: 16, marginBottom: 24 }}>
          <Button
            type="primary"
            icon={<ReloadOutlined />}
            onClick={handleRead}
            loading={reading}
          >
            读取当前设置
          </Button>
        </div>
      )}

      {selectedSn ? (
        <div style={{ maxWidth: 1200, margin: '0 auto' }}>
          <GeneralSection deviceInfo={selectedDevice} />
          <ApplicationSection />
          <ParallelSection />
          <ChargeSection />
          <DischargeSection />
          <OtherSection />
          <ResetSection />
        </div>
      ) : (
        <Card
          bordered={false}
          style={{ borderRadius: 12, marginTop: 24, textAlign: 'center', padding: 48 }}
        >
          <Empty
            description="请先选择一个设备"
            image={Empty.PRESENTED_IMAGE_SIMPLE}
          />
        </Card>
      )}
    </div>
  )
}

export default RemoteSettingsPage
