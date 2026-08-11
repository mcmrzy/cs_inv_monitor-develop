import React, { useState } from 'react'
import { Empty, Typography, Space, App, Collapse } from 'antd'
import {
  ReloadOutlined, SettingOutlined, ThunderboltOutlined,
  ToolOutlined, ArrowUpOutlined, ArrowDownOutlined,
  ApiOutlined, ExperimentOutlined,
} from '@ant-design/icons'
import { useQuery } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import DeviceSelector from './components/DeviceSelector'
import GeneralSection from './components/GeneralSection'
import ApplicationSection from './components/ApplicationSection'
import GridConnectionSection from './components/GridConnectionSection'
import ChargeSection from './components/ChargeSection'
import DischargeSection from './components/DischargeSection'
import OtherSection from './components/OtherSection'
import BatterySection from './components/BatterySection'
import ResetSection from './components/ResetSection'
import SchemaGroupPanel from './components/SchemaGroupPanel'
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
  const { t } = useTranslation()
  const [selectedSn, setSelectedSn] = useState<string | null>(() => {
    return localStorage.getItem('remote-settings-device-sn')
  })
  const [reading, setReading] = useState(false)
  const [activeKeys, setActiveKeys] = useState<string[]>(['general', 'application', 'gridConnection', 'charge', 'discharge', 'other', 'battery', 'reset'])

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
  const selectedDevice = devices.find((d) => d.sn === selectedSn) ?? null

  // CS-L10-6K2（V2 协议型号）使用动态命令面板（由 device_model_commands 配置驱动）；
  // 其余旧型号（如 CS-I10-6k2）保留静态 Section。
  // 型号比较不区分大小写：数据库中存在 CS-L10-6K2 与 CS-l10-6k2 两种写法，均走动态面板。
  const isDynamicModel = selectedDevice?.model?.toUpperCase() === 'CS-L10-6K2'

  const handleRead = () => {
    setReading(true)
    message.info(t('remote.readingConfig'))
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
        <div>
          {isDynamicModel && selectedDevice ? (
            // CS-L10-6K2：V2.1 起弃用命令卡片平铺，改为 V1 风格 schema 驱动分组面板
            // （通用/应用/混合/并联四分组，见 V2.1 文档 11.3 与 device_config_schema）
            <SchemaGroupPanel sn={selectedSn} />
          ) : (
          <Collapse
            activeKey={activeKeys}
            onChange={(keys) => setActiveKeys(keys as string[])}
            style={{ background: 'transparent', border: 'none' }}
            ghost
          >
            <Collapse.Panel
              key="general"
              header={<SectionHeader icon={<SettingOutlined />} title={t('remote.generalSettings')} color={SECTION_COLORS.general} />}
              style={panelStyle(SECTION_COLORS.general)}
            >
              <GeneralSection deviceInfo={selectedDevice} />
            </Collapse.Panel>

            <Collapse.Panel
              key="application"
              header={<SectionHeader icon={<ThunderboltOutlined />} title={t('remote.appSettings')} color={SECTION_COLORS.application} />}
              style={panelStyle(SECTION_COLORS.application)}
            >
              <ApplicationSection />
            </Collapse.Panel>

            <Collapse.Panel
              key="gridConnection"
              header={<SectionHeader icon={<ApiOutlined />} title={t('remote.gridSettings')} color={SECTION_COLORS.gridConnection} />}
              style={panelStyle(SECTION_COLORS.gridConnection)}
            >
              <GridConnectionSection deviceInfo={selectedDevice} />
            </Collapse.Panel>

            <Collapse.Panel
              key="charge"
              header={<SectionHeader icon={<ArrowUpOutlined />} title={t('remote.chargeSettings')} color={SECTION_COLORS.charge} />}
              style={panelStyle(SECTION_COLORS.charge)}
            >
              <ChargeSection />
            </Collapse.Panel>

            <Collapse.Panel
              key="discharge"
              header={<SectionHeader icon={<ArrowDownOutlined />} title={t('remote.dischargeSettings')} color={SECTION_COLORS.discharge} />}
              style={panelStyle(SECTION_COLORS.discharge)}
            >
              <DischargeSection />
            </Collapse.Panel>

            <Collapse.Panel
              key="other"
              header={<SectionHeader icon={<ToolOutlined />} title={t('remote.otherSettings')} color={SECTION_COLORS.other} />}
              style={panelStyle(SECTION_COLORS.other)}
            >
              <OtherSection />
            </Collapse.Panel>

            <Collapse.Panel
              key="battery"
              header={<SectionHeader icon={<ExperimentOutlined />} title={t('remote.battery')} color={SECTION_COLORS.battery} />}
              style={panelStyle(SECTION_COLORS.battery)}
            >
              <BatterySection />
            </Collapse.Panel>

            <Collapse.Panel
              key="reset"
              header={<SectionHeader icon={<ReloadOutlined />} title={t('remote.resetOps')} color={SECTION_COLORS.reset} />}
              style={panelStyle(SECTION_COLORS.reset)}
            >
              <ResetSection />
            </Collapse.Panel>
          </Collapse>
          )}
        </div>
      ) : (
        <div style={{ borderRadius: 12, marginTop: 24, textAlign: 'center', padding: 48, background: '#fff' }}>
          <Empty description={t('remote.pleaseSelectDeviceFirst')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
        </div>
      )}
    </div>
  )
}

export default RemoteSettingsPage
