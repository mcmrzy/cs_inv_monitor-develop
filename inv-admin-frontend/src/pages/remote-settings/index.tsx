import React, { useState } from 'react'
import { Empty, Typography, App } from 'antd'
import { useQuery } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import DeviceSelector from './components/DeviceSelector'
import SchemaGroupPanel from './components/SchemaGroupPanel'
import type { DeviceItem } from './types'

const { Title, Text } = Typography

const RemoteSettingsPage: React.FC = () => {
  const { message } = App.useApp()
  const { t } = useTranslation()
  const [selectedSn, setSelectedSn] = useState<string | null>(() => {
    return localStorage.getItem('remote-settings-device-sn')
  })
  const [reading, setReading] = useState(false)

  const { data: devicesData } = useQuery({
    queryKey: queryKeys.devices.list({ page: 1, page_size: 200 }),
    queryFn: () =>
      deviceApi.getDevices({ page: 1, page_size: 200 }).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (Array.isArray(d?.items) ? d.items : (Array.isArray(d) ? d : [])) as DeviceItem[]
      }),
    staleTime: 60_000,
  })

  const devices = devicesData ?? []

  const handleRead = () => {
    setReading(true)
    message.info(t('remote.readingConfig'))
    setTimeout(() => setReading(false), 1500)
  }

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>{t('remote.title')}</Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 24 }}>
        {t('remote.pageDescription')}
      </Text>

      <DeviceSelector selectedSn={selectedSn} onDeviceChange={(sn) => {
        setSelectedSn(sn || null)
        if (sn) {
          localStorage.setItem('remote-settings-device-sn', sn)
        } else {
          localStorage.removeItem('remote-settings-device-sn')
        }
      }} onRead={handleRead} reading={reading} />

      {selectedSn ? (
        /* 统一老款分组样式：设备信息头部（DeviceSelector）+ 通用/应用/混合/并联四分组 + 命令历史
         * （由 device_config_schema 驱动：通用 12 / 应用 8 / 混合 21（充电/放电/SOC/发电机）/ 并联 1） */
        <SchemaGroupPanel sn={selectedSn} />
      ) : (
        <div style={{ borderRadius: 12, marginTop: 24, textAlign: 'center', padding: 48, background: '#fff' }}>
          <Empty description={t('remote.pleaseSelectDeviceFirst')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
        </div>
      )}
    </div>
  )
}

export default RemoteSettingsPage
