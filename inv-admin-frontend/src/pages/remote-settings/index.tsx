// 远程设置 —— 三层结构：快捷设置首页（卡片）→ 功能分类页 → 高级参数（工程师模式）

import React, { useState } from 'react'
import { Empty, Typography, App } from 'antd'
import { useQueryClient } from '@tanstack/react-query'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import DeviceSelector from './components/DeviceSelector'
import SettingsHome from './components/SettingsHome'
import ModulePage from './components/ModulePage'
import AdvancedPanel from './components/AdvancedPanel'
import { useDeviceConfig } from './hooks/useDeviceConfig'
import { MODULES } from './config/fields'

const { Title, Text } = Typography

type View = { name: 'home' } | { name: 'module'; moduleId: string } | { name: 'advanced' }

const RemoteSettingsPage: React.FC = () => {
  const { t } = useTranslation()
  const [selectedSn, setSelectedSn] = useState<string | null>(() => {
    return localStorage.getItem('remote-settings-device-sn')
  })

  const handleDeviceChange = (sn: string) => {
    setSelectedSn(sn || null)
    if (sn) {
      localStorage.setItem('remote-settings-device-sn', sn)
    } else {
      localStorage.removeItem('remote-settings-device-sn')
    }
  }

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>{t('remote.title')}</Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 24 }}>
        {t('remote.pageDescription')}
      </Text>

      {selectedSn ? (
        <SettingsWorkspace sn={selectedSn} onDeviceChange={handleDeviceChange} />
      ) : (
        <>
          <DeviceSelector selectedSn={null} onDeviceChange={handleDeviceChange} onRead={() => undefined} reading={false} />
          <div style={{ borderRadius: 16, marginTop: 8, textAlign: 'center', padding: 48, background: '#fff' }}>
            <Empty description={t('remote.pleaseSelectDeviceFirst')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
          </div>
        </>
      )}
    </div>
  )
}

interface SettingsWorkspaceProps {
  sn: string
  onDeviceChange: (sn: string) => void
}

/** 选中设备后的工作区：设备选择器 + 三层视图切换 */
const SettingsWorkspace: React.FC<SettingsWorkspaceProps> = ({ sn, onDeviceChange }) => {
  const { message } = App.useApp()
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const cfg = useDeviceConfig(sn)
  const [view, setView] = useState<View>({ name: 'home' })
  const [reading, setReading] = useState(false)

  const handleRead = () => {
    setReading(true)
    message.info(t('remote.readingConfig'))
    cfg.refetchAll()
    void queryClient.invalidateQueries({ queryKey: queryKeys.devices.controlState(sn) })
    setTimeout(() => setReading(false), 1200)
  }

  const activeModule = view.name === 'module' ? MODULES.find((m) => m.id === view.moduleId) : undefined

  return (
    <>
      <DeviceSelector
        selectedSn={sn}
        onDeviceChange={(next) => {
          setView({ name: 'home' })
          onDeviceChange(next)
        }}
        onRead={handleRead}
        reading={reading}
      />

      {view.name === 'home' && (
        <SettingsHome
          cfg={cfg}
          loading={cfg.schemaLoading && cfg.stateLoading}
          onOpenModule={(moduleId) => setView({ name: 'module', moduleId })}
          onOpenAdvanced={() => setView({ name: 'advanced' })}
        />
      )}
      {view.name === 'module' && activeModule && (
        <ModulePage module={activeModule} cfg={cfg} onBack={() => setView({ name: 'home' })} />
      )}
      {view.name === 'advanced' && <AdvancedPanel cfg={cfg} onBack={() => setView({ name: 'home' })} />}
    </>
  )
}

export default RemoteSettingsPage
