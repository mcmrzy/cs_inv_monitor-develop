import React, { useState } from 'react'
import { Tabs, Empty, Card, Typography } from 'antd'
import useTranslation from '@/hooks/useTranslation'
import DeviceSelector from './components/DeviceSelector'
import RuntimeControlTab from './components/RuntimeControlTab'
import BatteryTab from './components/BatteryTab'
import ConfigStatusTab from './components/ConfigStatusTab'
import ParallelTab from './components/ParallelTab'
import type { RemoteSettingsTab } from './types'

const { Title, Text } = Typography

const RemoteSettingsPage: React.FC = () => {
  const { t } = useTranslation()
  const [selectedSn, setSelectedSn] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState<RemoteSettingsTab>('runtime')

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        {t('remoteSettings.pageTitle')}
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 24 }}>
        {t('remoteSettings.pageDescription')}
      </Text>

      <DeviceSelector selectedSn={selectedSn} onDeviceChange={setSelectedSn} />

      {selectedSn ? (
        <Tabs
          activeKey={activeTab}
          onChange={(key) => setActiveTab(key as RemoteSettingsTab)}
          style={{ marginTop: 16 }}
          items={[
            {
              key: 'runtime',
              label: t('remoteSettings.tabRuntime'),
              children: <RuntimeControlTab sn={selectedSn} />,
            },
            {
              key: 'battery',
              label: t('remoteSettings.tabBattery'),
              children: <BatteryTab sn={selectedSn} />,
            },
            {
              key: 'status',
              label: t('remoteSettings.tabStatus'),
              children: <ConfigStatusTab sn={selectedSn} />,
            },
            {
              key: 'parallel',
              label: t('remoteSettings.tabParallel'),
              children: <ParallelTab sn={selectedSn} />,
            },
          ]}
        />
      ) : (
        <Card
          bordered={false}
          style={{ borderRadius: 12, marginTop: 24, textAlign: 'center', padding: 48 }}
        >
          <Empty
            description={t('remoteSettings.selectDeviceHint')}
            image={Empty.PRESENTED_IMAGE_SIMPLE}
          />
        </Card>
      )}
    </div>
  )
}

export default RemoteSettingsPage
