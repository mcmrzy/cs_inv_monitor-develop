import React, { useState } from 'react'
import { Button, Empty, Typography, Space, App, Collapse } from 'antd'
import {
  ReloadOutlined, SettingOutlined, ThunderboltOutlined,
  ToolOutlined, ArrowUpOutlined, ArrowDownOutlined,
  ControlOutlined,
} from '@ant-design/icons'
import { useQuery } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import DeviceSelector from './components/DeviceSelector'
import GeneralSection from './components/GeneralSection'
import ApplicationSection from './components/ApplicationSection'
import ParallelSection from './components/ParallelSection'
import PowerControlSection from './components/PowerControlSection'
import ChargeSection from './components/ChargeSection'
import DischargeSection from './components/DischargeSection'
import OtherSection from './components/OtherSection'
import ResetSection from './components/ResetSection'
import { SECTION_COLORS } from './components/shared-styles'
import type { DeviceItem } from './types'

const { Title, Text } = Typography

// 面板标题组件
const SectionHeader: React.FC<{ icon: React.ReactNode; title: string; color: string }> = ({ icon, title, color }) => (
  <Space size={8}>
    <span style={{ color, fontSize: 18 }}>{icon}</span>
    <span style={{ fontSize: 15, fontWeight: 600, color: '#333' }}>{title}</span>
  </Space>
)

const RemoteSettingsPage: React.FC = () => {
  const { message } = App.useApp()
  const [selectedSn, setSelectedSn] = useState<string | null>(() => {
    return localStorage.getItem('remote-settings-device-sn')
  })
  const [reading, setReading] = useState(false)
  const [activeKeys, setActiveKeys] = useState<string[]>(['general', 'application', 'parallel', 'powerControl', 'charge', 'discharge', 'other', 'reset'])

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
    message.info('正在读取设备配置参数')
    setTimeout(() => setReading(false), 1500)
  }

  const panelStyle = (color: string): React.CSSProperties => ({
    marginBottom: 12,
    background: '#fff',
    borderRadius: 12,
    borderLeft: `3px solid ${color}`,
    overflow: 'hidden',
    boxShadow: '0 1px 4px rgba(0,0,0,0.06)',
  })

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>远程参数设置</Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 24 }}>
        远程配置逆变器运行参数，支持实时下发与生效
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
        <div>
          <Collapse
            activeKey={activeKeys}
            onChange={(keys) => setActiveKeys(keys as string[])}
            style={{ background: 'transparent', border: 'none' }}
            ghost
          >
            <Collapse.Panel
              key="general"
              header={<SectionHeader icon={<SettingOutlined />} title="通用设置" color={SECTION_COLORS.general} />}
              style={panelStyle(SECTION_COLORS.general)}
            >
              <GeneralSection deviceInfo={selectedDevice} />
            </Collapse.Panel>

            <Collapse.Panel
              key="application"
              header={<SectionHeader icon={<ThunderboltOutlined />} title="应用设置" color={SECTION_COLORS.application} />}
              style={panelStyle(SECTION_COLORS.application)}
            >
              <ApplicationSection />
            </Collapse.Panel>

            <Collapse.Panel
              key="parallel"
              header={<SectionHeader icon={<ToolOutlined />} title="并联设置" color={SECTION_COLORS.parallel} />}
              style={panelStyle(SECTION_COLORS.parallel)}
            >
              <ParallelSection />
            </Collapse.Panel>

            <Collapse.Panel
              key="powerControl"
              header={<SectionHeader icon={<ControlOutlined />} title="功率控制" color={SECTION_COLORS.powerControl} />}
              style={panelStyle(SECTION_COLORS.powerControl)}
            >
              <PowerControlSection deviceInfo={selectedDevice} />
            </Collapse.Panel>

            <Collapse.Panel
              key="charge"
              header={<SectionHeader icon={<ArrowUpOutlined />} title="充电设置" color={SECTION_COLORS.charge} />}
              style={panelStyle(SECTION_COLORS.charge)}
            >
              <ChargeSection />
            </Collapse.Panel>

            <Collapse.Panel
              key="discharge"
              header={<SectionHeader icon={<ArrowDownOutlined />} title="放电设置" color={SECTION_COLORS.discharge} />}
              style={panelStyle(SECTION_COLORS.discharge)}
            >
              <DischargeSection />
            </Collapse.Panel>

            <Collapse.Panel
              key="other"
              header={<SectionHeader icon={<ToolOutlined />} title="其他设置" color={SECTION_COLORS.other} />}
              style={panelStyle(SECTION_COLORS.other)}
            >
              <OtherSection />
            </Collapse.Panel>

            <Collapse.Panel
              key="reset"
              header={<SectionHeader icon={<ReloadOutlined />} title="重置操作" color={SECTION_COLORS.reset} />}
              style={panelStyle(SECTION_COLORS.reset)}
            >
              <ResetSection />
            </Collapse.Panel>
          </Collapse>
        </div>
      ) : (
        <div style={{ borderRadius: 12, marginTop: 24, textAlign: 'center', padding: 48, background: '#fff' }}>
          <Empty description="请选择设备" image={Empty.PRESENTED_IMAGE_SIMPLE} />
        </div>
      )}
    </div>
  )
}

export default RemoteSettingsPage
