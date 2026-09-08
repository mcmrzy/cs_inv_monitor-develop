import { useEffect, useState } from 'react'
import { Button, Card, Typography, Spin, message, Space, Tag } from 'antd'
import {
  AndroidOutlined,
  DownloadOutlined,
  SafetyCertificateOutlined,
  ThunderboltOutlined,
  LineChartOutlined,
  NotificationOutlined,
  CloudSyncOutlined,
} from '@ant-design/icons'
import api from '@/services/api'
import useTranslation from '@/hooks/useTranslation'

const { Title, Text, Paragraph } = Typography

interface AppVersionInfo {
  has_update: boolean
  latest_version_code: number
  latest_version_name: string
  download_url: string
  file_size: number
  file_md5: string
  changelog: string
  is_force: boolean
}

const DownloadPage: React.FC = () => {
  const { t } = useTranslation()
  const [loading, setLoading] = useState(true)
  const [versionInfo, setVersionInfo] = useState<AppVersionInfo | null>(null)
  const [downloading, setDownloading] = useState(false)

  useEffect(() => {
    fetchLatestVersion()
  }, [])

  const fetchLatestVersion = async () => {
    try {
      setLoading(true)
      const res = await api.get('/ota/app/check', {
        params: { platform: 'android', version_code: 0 },
      })
      const data = res as any
      if (data?.latest_version_name) {
        setVersionInfo(data)
      }
    } catch (error) {
      console.error('获取版本信息失败:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleDownload = () => {
    if (!versionInfo?.download_url) {
      message.warning(t('dl.noDownloadUrl'))
      return
    }

    setDownloading(true)
    // 创建一个隐藏的 a 标签来触发下载
    const link = document.createElement('a')
    link.href = versionInfo.download_url
    link.download = `辰烁光伏-v${versionInfo.latest_version_name}.apk`
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)

    setTimeout(() => setDownloading(false), 2000)
  }

  const formatFileSize = (bytes: number) => {
    if (!bytes) return t('dl.approxSize')
    const mb = bytes / (1024 * 1024)
    return `${mb.toFixed(1)} MB`
  }

  const features = [
    {
      icon: <LineChartOutlined style={{ fontSize: 28, color: '#1a73e8' }} />,
      title: t('dl.featureMonitor'),
      desc: t('dl.featureMonitorDesc'),
    },
    {
      icon: <ThunderboltOutlined style={{ fontSize: 28, color: '#f59e0b' }} />,
      title: t('dl.featureAnalytics'),
      desc: t('dl.featureAnalyticsDesc'),
    },
    {
      icon: <NotificationOutlined style={{ fontSize: 28, color: '#ef4444' }} />,
      title: t('dl.featureAlerts'),
      desc: t('dl.featureAlertsDesc'),
    },
    {
      icon: <CloudSyncOutlined style={{ fontSize: 28, color: '#22c55e' }} />,
      title: t('dl.featureOta'),
      desc: t('dl.featureOtaDesc'),
    },
  ]

  return (
    <div style={styles.container}>
      <div style={styles.content}>
        {/* Logo 和标题 */}
        <div style={styles.header}>
          <div style={styles.logo}>
            <svg
              viewBox="0 0 100 100"
              width="64"
              height="64"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <defs>
                <linearGradient id="logoGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#1a73e8" />
                  <stop offset="100%" stopColor="#0d47a1" />
                </linearGradient>
              </defs>
              <rect width="100" height="100" rx="24" fill="url(#logoGrad)" />
              <path
                d="M50 20L25 35v30l25 15 25-15V35L50 20z"
                fill="rgba(255,255,255,0.2)"
                stroke="white"
                strokeWidth="2"
              />
              <circle cx="50" cy="50" r="15" fill="rgba(255,255,255,0.3)" stroke="white" strokeWidth="2" />
              <path d="M50 35v30M35 50h30" stroke="white" strokeWidth="3" strokeLinecap="round" />
            </svg>
          </div>
          <Title level={2} style={{ margin: '16px 0 8px', color: '#1a1a1a' }}>
            {t('dl.appTitle')}
          </Title>
          <Text type="secondary" style={{ fontSize: 16 }}>
            {t('dl.subtitle')}
          </Text>
        </div>

        {/* 版本信息卡片 */}
        <Card style={styles.versionCard} bordered={false}>
          {loading ? (
            <div style={{ textAlign: 'center', padding: '20px 0' }}>
              <Spin tip={t('dl.loadingVersion')} />
            </div>
          ) : versionInfo ? (
            <Space direction="vertical" size={8} style={{ width: '100%' }}>
              <div style={styles.versionRow}>
                <Text type="secondary">{t('dl.latestVersion')}</Text>
                <Tag color="blue">v{versionInfo.latest_version_name}</Tag>
              </div>
              <div style={styles.versionRow}>
                <Text type="secondary">{t('dl.fileSize')}</Text>
                <Text>{formatFileSize(versionInfo.file_size)}</Text>
              </div>
              <div style={styles.versionRow}>
                <Text type="secondary">{t('dl.supportedOs')}</Text>
                <Text>Android 7.0+</Text>
              </div>
              {versionInfo.changelog && (
                <div style={{ marginTop: 8 }}>
                  <Text type="secondary">{t('dl.changelog')}</Text>
                  <Paragraph
                    style={{ marginTop: 4, marginBottom: 0 }}
                    ellipsis={{ rows: 3, expandable: true, symbol: t('dl.expand') }}
                  >
                    {versionInfo.changelog}
                  </Paragraph>
                </div>
              )}
            </Space>
          ) : (
            <div style={{ textAlign: 'center', padding: '20px 0' }}>
              <Text type="secondary">{t('dl.versionLoading')}</Text>
            </div>
          )}
        </Card>

        {/* 下载按钮 */}
        <Button
          type="primary"
          size="large"
          icon={<DownloadOutlined />}
          loading={downloading}
          onClick={handleDownload}
          style={styles.downloadBtn}
          block
        >
          {downloading ? t('dl.downloading') : t('dl.downloadBtn')}
        </Button>

        {/* 系统要求 */}
        <div style={styles.androidBadge}>
          <AndroidOutlined style={{ fontSize: 20, color: '#3ddc84' }} />
          <span>{t('dl.androidOnly')}</span>
        </div>

        {/* 功能特性 */}
        <div style={styles.features}>
          {features.map((feature, index) => (
            <div key={index} style={styles.featureItem}>
              <div style={styles.featureIcon}>{feature.icon}</div>
              <div>
                <Text strong style={{ fontSize: 14 }}>
                  {feature.title}
                </Text>
                <br />
                <Text type="secondary" style={{ fontSize: 12 }}>
                  {feature.desc}
                </Text>
              </div>
            </div>
          ))}
        </div>

        {/* 安全提示 */}
        <div style={styles.securityTip}>
          <SafetyCertificateOutlined style={{ color: '#52c41a', marginRight: 8 }} />
          <Text type="secondary" style={{ fontSize: 12 }}>
            {t('dl.securityTip')}
          </Text>
        </div>

        {/* 底部信息 */}
        <div style={styles.footer}>
          <Text type="secondary" style={{ fontSize: 12 }}>
            {t('dl.footerCopyright')} ·{' '}
            <a href="https://csergy.com" target="_blank" rel="noopener noreferrer">
              csergy.com
            </a>
          </Text>
          <br />
          <Text type="secondary" style={{ fontSize: 12 }}>
            {t('dl.footerDesc')}
          </Text>
        </div>
      </div>
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    minHeight: '100vh',
    background: 'linear-gradient(135deg, #1a73e8 0%, #0d47a1 100%)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    padding: '20px',
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
  },
  content: {
    background: 'white',
    borderRadius: 20,
    boxShadow: '0 20px 60px rgba(0,0,0,0.3)',
    padding: '48px 40px',
    maxWidth: 460,
    width: '100%',
    textAlign: 'center' as const,
  },
  header: {
    marginBottom: 32,
  },
  logo: {
    width: 100,
    height: 100,
    margin: '0 auto',
    borderRadius: 24,
    overflow: 'hidden',
    boxShadow: '0 8px 24px rgba(26, 115, 232, 0.3)',
  },
  versionCard: {
    background: '#f5f7fa',
    borderRadius: 12,
    marginBottom: 24,
    textAlign: 'left' as const,
  },
  versionRow: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  downloadBtn: {
    height: 52,
    fontSize: 18,
    fontWeight: 600,
    borderRadius: 12,
    background: 'linear-gradient(135deg, #1a73e8 0%, #0d47a1 100%)',
    border: 'none',
    boxShadow: '0 8px 24px rgba(26, 115, 232, 0.3)',
    marginBottom: 16,
  },
  androidBadge: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 8,
    background: '#f5f7fa',
    padding: '8px 16px',
    borderRadius: 8,
    marginBottom: 32,
  },
  features: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 16,
    marginBottom: 24,
    textAlign: 'left' as const,
  },
  featureItem: {
    display: 'flex',
    alignItems: 'center',
    gap: 12,
    padding: '12px 8px',
  },
  featureIcon: {
    width: 48,
    height: 48,
    borderRadius: 12,
    background: '#e8f0fe',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  securityTip: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    padding: '12px 0',
    borderTop: '1px solid #eee',
    marginBottom: 16,
  },
  footer: {
    paddingTop: 16,
  },
}

export default DownloadPage
