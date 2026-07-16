import React, { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Tabs, Empty, Typography, ConfigProvider } from 'antd'
import { SettingOutlined, ControlOutlined, UnorderedListOutlined, HddOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import { modelApi } from '@/services/modelApi'
import type { RemoteSettingsTab } from './types'
import { DS } from './types'
import ModelSelector from './components/ModelSelector'
import CommandTab from './components/CommandTab'
import FieldConfigTab from './components/FieldConfigTab'
import DeviceListTab from './components/DeviceListTab'

const { Title, Text } = Typography

const pageStyle = `
.rs-page {
  min-height: 100%;
  background: ${DS.bgPage};
  padding: 32px 36px;
}
.rs-header {
  background: linear-gradient(135deg, #4f46e5 0%, #7c3aed 50%, #a855f7 100%);
  border-radius: 18px;
  padding: 32px 40px;
  margin-bottom: 28px;
  display: flex;
  align-items: center;
  gap: 22px;
  position: relative;
  overflow: hidden;
  box-shadow: 0 4px 24px rgba(79,70,229,0.18), 0 1px 3px rgba(0,0,0,0.06);
}
.rs-header::before {
  content: '';
  position: absolute;
  top: -40%;
  right: -10%;
  width: 220px;
  height: 220px;
  border-radius: 50%;
  background: rgba(255,255,255,0.07);
}
.rs-header::after {
  content: '';
  position: absolute;
  bottom: -30%;
  right: 10%;
  width: 140px;
  height: 140px;
  border-radius: 50%;
  background: rgba(255,255,255,0.05);
}
.rs-header-deco {
  position: absolute;
  top: 20%;
  right: 25%;
  width: 80px;
  height: 80px;
  border-radius: 50%;
  background: rgba(255,255,255,0.03);
}
.rs-header-icon {
  width: 60px;
  height: 60px;
  border-radius: 16px;
  background: rgba(255,255,255,0.20);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  backdrop-filter: blur(6px);
  box-shadow: 0 2px 8px rgba(0,0,0,0.12);
}
.rs-tabs-wrapper {
  background: #fff;
  border-radius: 16px;
  padding: 8px 24px 24px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.06), 0 4px 16px rgba(0,0,0,0.03);
}
.rs-tabs-wrapper .ant-tabs-nav::before {
  border-bottom: none !important;
}
.rs-tabs-wrapper .ant-tabs-nav {
  margin-bottom: 24px !important;
  padding: 4px 0 !important;
}
.rs-tabs-wrapper .ant-tabs-nav-list {
  gap: 4px;
}
.rs-tabs-wrapper .ant-tabs-tab {
  border-radius: 10px !important;
  padding: 8px 22px !important;
  background: transparent !important;
  border: none !important;
  margin: 0 !important;
  transition: all 0.22s ease !important;
  font-weight: 500;
  color: ${DS.textSecondary} !important;
}
.rs-tabs-wrapper .ant-tabs-tab::before {
  display: none !important;
}
.rs-tabs-wrapper .ant-tabs-tab:hover {
  background: ${DS.primaryLight} !important;
  color: ${DS.primary} !important;
}
.rs-tabs-wrapper .ant-tabs-tab-active {
  background: ${DS.primary} !important;
  color: #fff !important;
  box-shadow: 0 2px 8px rgba(79,70,229,0.25) !important;
}
.rs-tabs-wrapper .ant-tabs-tab-active .ant-tabs-tab-btn {
  color: #fff !important;
}
.rs-tabs-wrapper .ant-tabs-tab .ant-tabs-tab-btn {
  color: ${DS.textSecondary};
  transition: color 0.22s ease;
}
.rs-tabs-wrapper .ant-tabs-tab:hover .ant-tabs-tab-btn {
  color: ${DS.primary};
}
.rs-tabs-wrapper .ant-tabs-ink-bar {
  display: none !important;
}
.rs-tabs-wrapper .ant-tabs-content-holder {
  background: transparent;
}
.rs-empty-wrapper {
  text-align: center;
  padding: 100px 40px;
  background: #fff;
  border-radius: 18px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.06), 0 4px 16px rgba(0,0,0,0.03);
  border: 1px dashed ${DS.border};
}
`

const RemoteSettingsPage: React.FC = () => {
  const { t } = useTranslation()
  const [selectedModelId, setSelectedModelId] = useState<number | null>(null)
  const [activeTab, setActiveTab] = useState<RemoteSettingsTab>('fields')

  const { data: configData } = useQuery({
    queryKey: ['models', 'config', selectedModelId],
    queryFn: () => modelApi.getModelConfig(selectedModelId!).then(r => r.data),
    enabled: !!selectedModelId,
    staleTime: 60000,
  })

  return (
    <ConfigProvider
      theme={{
        token: {
          colorPrimary: DS.primary,
          borderRadius: DS.radiusCard,
        },
      }}
    >
      <div className="rs-page">
        <style>{pageStyle}</style>

        {/* Gradient header */}
        <div className="rs-header">
          <div className="rs-header-deco" />
          <div className="rs-header-icon">
            <SettingOutlined style={{ fontSize: 28, color: '#fff' }} />
          </div>
          <div style={{ position: 'relative', zIndex: 1 }}>
            <Title level={3} style={{ margin: 0, color: '#fff', fontSize: 23, fontWeight: 700, letterSpacing: '0.01em' }}>
              {t('remoteSettings.pageTitle')}
            </Title>
            <Text style={{ color: 'rgba(255,255,255,0.82)', fontSize: 14, marginTop: 5, display: 'block' }}>
              {t('remoteSettings.pageDescription')}
            </Text>
          </div>
        </div>

        {/* Model selector */}
        <div style={{ marginBottom: 28 }}>
          <ModelSelector
            selectedModelId={selectedModelId}
            onModelChange={setSelectedModelId}
            fieldCount={(configData as any)?.fields?.length}
          />
        </div>

        {/* Tabs content */}
        {selectedModelId && (
          <div className="rs-tabs-wrapper">
            <Tabs
              activeKey={activeTab}
              onChange={(key) => setActiveTab(key as RemoteSettingsTab)}
              items={[
                {
                  key: 'commands',
                  label: (
                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7 }}>
                      <ControlOutlined />
                      {t('remoteSettings.tabCommands')}
                    </span>
                  ),
                  children: <CommandTab modelId={selectedModelId} />,
                },
                {
                  key: 'fields',
                  label: (
                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7 }}>
                      <UnorderedListOutlined />
                      {t('remoteSettings.tabFields')}
                    </span>
                  ),
                  children: <FieldConfigTab modelId={selectedModelId} />,
                },
                {
                  key: 'devices',
                  label: (
                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7 }}>
                      <HddOutlined />
                      {t('remoteSettings.tabDevices')}
                    </span>
                  ),
                  children: <DeviceListTab modelId={selectedModelId} />,
                },
              ]}
            />
          </div>
        )}

        {/* Empty state when no model selected */}
        {!selectedModelId && (
          <div className="rs-empty-wrapper">
            <Empty
              image={Empty.PRESENTED_IMAGE_SIMPLE}
              description={
                <Text style={{ color: DS.textSecondary, fontSize: 14 }}>
                  {t('remoteSettings.selectModelHint')}
                </Text>
              }
            />
          </div>
        )}
      </div>
    </ConfigProvider>
  )
}

export default RemoteSettingsPage
