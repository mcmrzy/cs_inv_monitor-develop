import { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Tabs, Button, Space, Typography, Tag, Grid } from 'antd'
import { ArrowLeftOutlined } from '@ant-design/icons'

import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import EnergyCenterTab from './EnergyCenterTab'
import StatusTab from './StatusTab'
import EnergyStatsTab from './EnergyStatsTab'
import StateCenterTab from './StateCenterTab'
import BmsTab from './BmsTab'
import HealthTab from './HealthTab'
import DiagnosticsTab from './DiagnosticsTab'
import StrategyTab from './StrategyTab'
import InstallTab from './InstallTab'
import ParallelTab from './ParallelTab'
import InfoTab from './InfoTab'

const { Text } = Typography

interface DeviceHeaderInfo {
  alias?: string
  model?: string
  status?: number | string
  last_online_at?: string
}

/**
 * 设备完整详情页（全屏路由，位于 MainLayout 之外）。
 *
 * 因为没有 ProLayout 容器，本页必须自建页面外壳：布局底色 + 内边距 + 头部信息栏，
 * 否则内容会紧贴视口边缘、底色透空（浏览器为白，宿主容器可能为深色）。
 * 头部展示设备别名/SN/型号/在线状态，方便直接判断当前查看的是哪台设备。
 */
const DeviceDetailPage: React.FC = () => {
  const { t } = useTranslation()
  const { sn } = useParams<{ sn: string }>()
  const navigate = useNavigate()
  const screens = Grid.useBreakpoint()
  const { timezone } = useTimezoneStore()
  const [activeTab, setActiveTab] = useState('energy')

  const { data: detail } = useQuery({
    queryKey: queryKeys.devices.detail(sn ?? ''),
    queryFn: () => deviceApi.getDeviceBySn(sn as string).then((r) => r.data?.data ?? null),
    enabled: Boolean(sn),
    staleTime: 60_000,
  })
  // 详情接口返回 { device, model_fields, ... }；兼容旧版直接返回设备对象
  const device: DeviceHeaderInfo | undefined = detail?.device ?? detail ?? undefined
  const online = device?.status === 1 || device?.status === 'online'

  if (!sn) {
    return (
      <div style={{ textAlign: 'center', padding: 48 }}>
        <Text type="secondary">{t('deviceDetail.deviceSn')}: N/A</Text>
      </div>
    )
  }

  return (
    <div
      style={{
        minHeight: '100vh',
        // 与 MainLayout 内容区（.ant-pro-layout-bg-list）同一「纸面」：白→浅灰渐变，
        // 本页在 ProLayout 之外，必须自行铺底，否则与其它页面的底色/质感不一致。
        background: 'linear-gradient(#ffffff, #f5f5f5 28%)',
        padding: screens.md ? 24 : 12,
      }}
    >
      {/* ── 页面标题行：与仪表盘/设备管理等页面一致的标题排布（非卡片） ── */}
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          flexWrap: 'wrap',
          gap: 12,
          marginBottom: 16,
        }}
      >
        <Space size={12} align="center" wrap>
          <Button icon={<ArrowLeftOutlined />} onClick={() => navigate(-1)}>
            {t('deviceDetail.back')}
          </Button>
          <span style={{ fontSize: 20, fontWeight: 600, lineHeight: 1.4 }}>
            {device?.alias || t('deviceDetail.title')}
          </span>
          <Text type="secondary" style={{ fontSize: 13, fontFamily: 'monospace' }}>
            {t('deviceDetail.deviceSn')}: {sn}
          </Text>
          {device?.model && <Tag style={{ marginInlineEnd: 0 }}>{device.model}</Tag>}
        </Space>

        <Space size={12} wrap>
          <Tag color={online ? 'green' : 'default'} style={{ marginInlineEnd: 0 }}>
            {online ? t('deviceDetail.header.online') : t('deviceDetail.header.offline')}
          </Tag>
          {device?.last_online_at && (
            <Text type="secondary" style={{ fontSize: 12 }}>
              {t('deviceDetail.header.lastOnline')}:{' '}
              {formatInTimezone(device.last_online_at, timezone, 'YYYY-MM-DD HH:mm')}
            </Text>
          )}
        </Space>
      </div>

      {/* ── 详情 Tab（窄屏自动收进「更多」下拉）── */}
      <Tabs
        activeKey={activeTab}
        onChange={setActiveTab}
        tabBarGutter={screens.md ? 28 : 16}
        items={[
          { key: 'energy', label: t('deviceDetail.tab.energy'), children: <EnergyCenterTab sn={sn} /> },
          { key: 'bms', label: t('deviceDetail.tab.bms'), children: <BmsTab sn={sn} /> },
          { key: 'realtime', label: t('deviceDetail.tab.realtime'), children: <StatusTab sn={sn} /> },
          { key: 'stats', label: t('deviceDetail.tab.stats'), children: <EnergyStatsTab sn={sn} /> },
          { key: 'state', label: t('deviceDetail.tab.state'), children: <StateCenterTab sn={sn} /> },
          { key: 'health', label: t('deviceDetail.tab.healthDevice'), children: <HealthTab sn={sn} /> },
          { key: 'diagnostics', label: t('deviceDetail.tab.diagnostics'), children: <DiagnosticsTab sn={sn} /> },
          { key: 'strategy', label: t('deviceDetail.tab.strategy'), children: <StrategyTab sn={sn} /> },
          { key: 'install', label: t('deviceDetail.tab.install'), children: <InstallTab sn={sn} /> },
          { key: 'parallel', label: t('deviceDetail.tab.parallel'), children: <ParallelTab sn={sn} /> },
          { key: 'info', label: t('deviceDetail.tab.info'), children: <InfoTab sn={sn} /> },
        ]}
      />
    </div>
  )
}

export default DeviceDetailPage
