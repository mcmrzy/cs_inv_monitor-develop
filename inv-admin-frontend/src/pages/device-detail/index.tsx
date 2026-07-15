import { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { Tabs, Button, Space, Typography } from 'antd'
import { ArrowLeftOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import StatusTab from './StatusTab'
import StrategyTab from './StrategyTab'
import InstallTab from './InstallTab'
import ParallelTab from './ParallelTab'
import DiagnosticsTab from './DiagnosticsTab'

const { Title, Text } = Typography

const DeviceDetailPage: React.FC = () => {
  const { t } = useTranslation()
  const { sn } = useParams<{ sn: string }>()
  const navigate = useNavigate()
  const [activeTab, setActiveTab] = useState('status')

  if (!sn) {
    return (
      <div style={{ textAlign: 'center', padding: 48 }}>
        <Text type="secondary">{t('deviceDetail.deviceSn')}: N/A</Text>
      </div>
    )
  }

  return (
    <div>
      <div style={{ marginBottom: 16, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <Space>
          <Button
            icon={<ArrowLeftOutlined />}
            onClick={() => navigate(-1)}
          >
            {t('deviceDetail.back')}
          </Button>
          <Title level={4} style={{ margin: 0 }}>
            {t('deviceDetail.title')}
          </Title>
          <Text type="secondary" style={{ fontFamily: 'monospace' }}>
            {t('deviceDetail.deviceSn')}: {sn}
          </Text>
        </Space>
      </div>

      <Tabs
        activeKey={activeTab}
        onChange={setActiveTab}
        items={[
          { key: 'status', label: t('deviceDetail.tab.status'), children: <StatusTab sn={sn} /> },
          { key: 'strategy', label: t('deviceDetail.tab.strategy'), children: <StrategyTab sn={sn} /> },
          { key: 'install', label: t('deviceDetail.tab.install'), children: <InstallTab sn={sn} /> },
          { key: 'parallel', label: t('deviceDetail.tab.parallel'), children: <ParallelTab sn={sn} /> },
          { key: 'diagnostics', label: t('deviceDetail.tab.diagnostics'), children: <DiagnosticsTab sn={sn} /> },
        ]}
      />
    </div>
  )
}

export default DeviceDetailPage
