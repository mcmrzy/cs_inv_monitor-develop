import React, { useState } from 'react'
import { Tabs, Empty, Card, Typography } from 'antd'
import useTranslation from '@/hooks/useTranslation'
import DeviceSelector from './components/DeviceSelector'
import GeneralSettingsTab from './components/GeneralSettingsTab'
import ApplicationSettingsTab from './components/ApplicationSettingsTab'
import ConfigStatusTab from './components/ConfigStatusTab'
import ParallelTab from './components/ParallelTab'
import GridSettingsTab from './components/GridSettingsTab'
import PowerControlTab from './components/PowerControlTab'
import ChargeSettingsTab from './components/ChargeSettingsTab'
import DischargeSettingsTab from './components/DischargeSettingsTab'
import OtherSettingsTab from './components/OtherSettingsTab'
import ResetTab from './components/ResetTab'
import type { RemoteSettingsTab } from './types'

const { Title, Text } = Typography

const RemoteSettingsPage: React.FC = () => {
  const { t } = useTranslation()
  const [selectedSn, setSelectedSn] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState<RemoteSettingsTab>('general')

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
          destroyInactiveTabPane
          style={{ marginTop: 16 }}
          items={[
            {
              key: 'general',
              label: t('remoteSettings.tabGeneral'),
              children: <GeneralSettingsTab sn={selectedSn} />,
            },
            {
              key: 'application',
              label: t('remoteSettings.tabApplication'),
              children: <ApplicationSettingsTab sn={selectedSn} />,
            },
            {
              key: 'parallel',
              label: t('remoteSettings.tabParallel'),
              children: <ParallelTab sn={selectedSn} />,
            },
            {
              key: 'grid',
              label: t('remoteSettings.tabGrid'),
              children: <GridSettingsTab sn={selectedSn} />,
            },
            {
              key: 'power',
              label: t('remoteSettings.tabPower'),
              children: <PowerControlTab sn={selectedSn} />,
            },
            {
              key: 'charge',
              label: t('remoteSettings.tabCharge'),
              children: <ChargeSettingsTab sn={selectedSn} />,
            },
            {
              key: 'discharge',
              label: t('remoteSettings.tabDischarge'),
              children: <DischargeSettingsTab sn={selectedSn} />,
            },
            {
              key: 'other',
              label: t('remoteSettings.tabOther'),
              children: <OtherSettingsTab sn={selectedSn} />,
            },
            {
              key: 'reset',
              label: t('remoteSettings.tabReset'),
              children: <ResetTab sn={selectedSn} />,
            },
            {
              key: 'status',
              label: t('remoteSettings.tabStatus'),
              children: <ConfigStatusTab sn={selectedSn} />,
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
