import { useState, useEffect, useMemo } from 'react'
import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import {
  Layout, Menu, Button, Avatar, Dropdown, Badge, Typography, theme, Grid, Modal, Form, Input, App, Select,
} from 'antd'
import {
  DashboardOutlined, DesktopOutlined, CloudUploadOutlined, AlertOutlined,
  ToolOutlined, TeamOutlined, SettingOutlined, LogoutOutlined, UserOutlined,
  MenuFoldOutlined, MenuUnfoldOutlined, ClusterOutlined,
  FundViewOutlined, ThunderboltOutlined,
  EnvironmentOutlined, LockOutlined, FileTextOutlined,
  RadarChartOutlined, ControlOutlined, UnorderedListOutlined, HeartOutlined,
  EditOutlined, ExperimentOutlined, GlobalOutlined, ClockCircleOutlined,
} from '@ant-design/icons'
import useAuthStore from '@/stores/authStore'
import useLocaleStore from '@/stores/localeStore'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import { ROLE_MAP, ROLE_COLORS, ROLE_I18N_KEY } from '@/utils/constants'
import { Role } from '@/types'
import api from '@/services/api'
import { TIMEZONE_LIST, REGION_LABELS, getTimezoneLabel } from '@/utils/timezone'

const { Header, Sider, Content } = Layout

interface MenuItem {
  key: string
  icon?: React.ReactNode
  label: string
  permission?: string
  children?: MenuItem[]
  type?: string
}

const getAdminMenuItems = (t: (key: string) => string): MenuItem[] => [
  { key: '/dashboard', icon: <DashboardOutlined />, label: t('menu.dashboard'), permission: 'dashboard:view' },
  { key: '/big-screen', icon: <FundViewOutlined />, label: t('menu.bigScreen'), permission: 'dashboard:view' },
  { key: '/monitoring', icon: <ThunderboltOutlined />, label: t('menu.stationMonitor'), permission: 'devices:view' },
  { key: '/stations', icon: <EnvironmentOutlined />, label: t('menu.stationManage'), permission: 'stations:view' },
  { key: '/devices', icon: <DesktopOutlined />, label: t('menu.deviceManage'), permission: 'devices:view' },
  { key: '/models', icon: <ExperimentOutlined />, label: t('menu.modelManage'), permission: 'models:view' },
  { key: '/parallel', icon: <ClusterOutlined />, label: t('menu.parallelManage'), permission: 'parallel:view' },
  { key: '/remote-settings', icon: <ControlOutlined />, label: t('menu.remoteSettings'), permission: 'devices:view' },
  { key: '/batch-settings', icon: <EditOutlined />, label: t('menu.batchSettings'), permission: 'devices:view' },
  { key: '/ota', icon: <CloudUploadOutlined />, label: t('menu.ota'), permission: 'firmware:view' },
  { key: '/alerts', icon: <AlertOutlined />, label: t('menu.alertCenter'), permission: 'alerts:view' },
  { key: '/work-orders', icon: <FileTextOutlined />, label: t('menu.workOrders'), permission: 'work_orders:view' },
  { key: '/admin', icon: <SettingOutlined />, label: t('menu.systemConfig'), permission: 'admin:view' },
  { key: '/users', icon: <TeamOutlined />, label: t('menu.userManage'), permission: 'users:view' },
  { key: '/operation-logs', icon: <UnorderedListOutlined />, label: t('menu.operationLogs'), permission: 'admin:view' },
  { key: '/system/pipeline-health', icon: <HeartOutlined />, label: t('menu.pipelineHealth'), permission: 'admin:view' },
]

const getUserMenuItems = (t: (key: string) => string): MenuItem[] => [
  { key: '/dashboard', icon: <DashboardOutlined />, label: t('menu.dashboard'), permission: 'dashboard:view' },
  { key: '/monitoring', icon: <ThunderboltOutlined />, label: t('menu.stationMonitor'), permission: 'devices:view' },
  { key: '/stations', icon: <EnvironmentOutlined />, label: t('menu.stationManage'), permission: 'stations:view' },
  { key: '/devices', icon: <DesktopOutlined />, label: t('menu.deviceManage'), permission: 'devices:view' },
  { key: '/remote-settings', icon: <ControlOutlined />, label: t('menu.remoteSettings'), permission: 'devices:view' },
  { key: '/alerts', icon: <AlertOutlined />, label: t('menu.alertCenter'), permission: 'alerts:view' },
  { key: '/work-orders', icon: <FileTextOutlined />, label: t('menu.workOrders'), permission: 'work_orders:view' },
]

const MainLayout: React.FC = () => {
  const [collapsed, setCollapsed] = useState(false)
  const [mobileCollapsed, setMobileCollapsed] = useState(true)
  const [passwordModalOpen, setPasswordModalOpen] = useState(false)
  const [passwordLoading, setPasswordLoading] = useState(false)
  const [passwordForm] = Form.useForm()
  const [profileModalOpen, setProfileModalOpen] = useState(false)
  const [profileLoading, setProfileLoading] = useState(false)
  const [profileForm] = Form.useForm()
  const navigate = useNavigate()
  const location = useLocation()
  const { user, logout, hasPermission } = useAuthStore()
  const { lang, setLang } = useLocaleStore()
  const fetchTimezone = useTimezoneStore((s) => s.fetchTimezone)
  const queryClient = useQueryClient()
  const { t } = useTranslation()
  const { token: themeToken } = theme.useToken()
  const screens = Grid.useBreakpoint()
  const { message } = App.useApp()

  const isMobile = !screens.md

  useEffect(() => {
    if (!screens.md) { setMobileCollapsed(true) } else { setMobileCollapsed(false) }
  }, [screens.md])

  const siderCollapsed = isMobile ? mobileCollapsed : collapsed

  const isAdminRole = user && (user.role === Role.SUPER_ADMIN || user.role === Role.ADMIN)

  const filterMenuItems = (items: MenuItem[]): any[] => {
    return items
      .map(({ permission, ...rest }) => {
        if (permission && !hasPermission(permission)) return null
        return rest
      })
      .filter(Boolean)
  }

  const displayMenuItems = useMemo(() => {
    const source = isAdminRole ? getAdminMenuItems(t) : getUserMenuItems(t)
    return filterMenuItems(source)
  }, [isAdminRole, hasPermission, lang])

  const selectedKey = (() => {
    const path = location.pathname
    // For multi-segment routes like /system/pipeline-health, use full path
    if (path.match(/^\/[^/]+\/[^/]+/)) return path
    return '/' + (path.split('/')[1] || 'dashboard')
  })()

  const handleMenuClick = (info: { key: string }) => {
    navigate(info.key)
  }

  const handleLogout = () => {
    logout()
    navigate('/login')
  }

  const handleOpenProfile = () => {
    profileForm.setFieldsValue({
      nickname: user?.nickname || '',
      timezone: user?.timezone || 'Asia/Shanghai',
    })
    setProfileModalOpen(true)
  }

  const handleUpdateProfile = async (values: { nickname: string; timezone: string }) => {
    setProfileLoading(true)
    try {
      const res = await api.put('/auth/profile', values)
      const responseData = res.data as Record<string, unknown>
      if (responseData?.code !== undefined && responseData.code !== 0) {
        message.error((responseData.message as string) || t('msg.profileUpdateFailed'))
        return
      }
      message.success(t('msg.profileUpdated'))
      setProfileModalOpen(false)
      // 更新本地存储的用户信息并刷新时区
      if (user) {
        const updatedUser = { ...user, nickname: values.nickname, timezone: values.timezone }
        useAuthStore.setState({ user: updatedUser })
        fetchTimezone()
      }
    } catch {
      message.error(t('msg.profileUpdateFailed'))
    } finally {
      setProfileLoading(false)
    }
  }

  const handleChangePassword = async (values: { old_password: string; new_password: string }) => {
    setPasswordLoading(true)
    try {
      const res = await api.post('/auth/change-password', {
        old_password: values.old_password,
        new_password: values.new_password,
      })
      const responseData = res.data as Record<string, unknown>
      if (responseData?.code !== undefined && responseData.code !== 0) {
        message.error((responseData.message as string) || t('msg.passwordChangeFailed'))
        return
      }
      message.success(t('msg.passwordChanged'))
      setPasswordModalOpen(false)
      passwordForm.resetFields()
    } catch (error) {
      message.error(t('msg.passwordCheckFailed'))
    } finally {
      setPasswordLoading(false)
    }
  }

  const userMenuItemsDropdown = [
    { key: 'profile', icon: <UserOutlined />, label: t('header.profile'), onClick: handleOpenProfile },
    { key: 'change-password', icon: <LockOutlined />, label: t('header.changePassword'), onClick: () => setPasswordModalOpen(true) },
    { key: 'logout', icon: <LogoutOutlined />, label: t('header.logout'), danger: true, onClick: handleLogout },
  ]

  const langMenuItems = [
    { key: 'zh', label: '中文' },
    { key: 'en', label: 'English' },
  ]

  const currentTimezone = user?.timezone || 'Asia/Shanghai'

  const timezoneOptions = useMemo(() => {
    const groups: Record<string, { label: string; options: { value: string; label: string }[] }> = {}
    TIMEZONE_LIST.forEach(tz => {
      if (!groups[tz.region]) {
        const regionLabel = REGION_LABELS[tz.region]
        groups[tz.region] = { label: lang === 'zh' ? regionLabel['zh-CN'] : regionLabel['en-US'], options: [] }
      }
      groups[tz.region].options.push({
        value: tz.id,
        label: getTimezoneLabel(tz.id, lang),
      })
    })
    return Object.values(groups)
  }, [lang])

  const handleTimezoneChange = async (tz: string) => {
    try {
      const res = await api.put('/auth/profile', { timezone: tz })
      const responseData = res.data as Record<string, unknown>
      if (responseData?.code !== undefined && responseData.code !== 0) {
        message.error((responseData.message as string) || t('msg.timezoneUpdateFailed'))
        return
      }
      message.success(t('msg.timezoneUpdated'))
      if (user) {
        useAuthStore.setState({ user: { ...user, timezone: tz } })
        // 更新 timezoneStore 中的时区状态并失效缓存，使页面重新获取数据
        fetchTimezone()
        queryClient.invalidateQueries()
      }
    } catch {
      message.error(t('msg.timezoneUpdateFailed'))
    }
  }

  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider
        trigger={null}
        collapsible
        collapsed={siderCollapsed}
        breakpoint="md"
        onBreakpoint={(broken) => { if (broken) setMobileCollapsed(true) }}
        theme="dark"
        width={220}
        style={{ overflow: 'auto', height: '100vh', position: 'fixed', left: 0, top: 0, bottom: 0, zIndex: 100 }}
      >
        <div style={{ height: 64, display: 'flex', alignItems: 'center', justifyContent: 'center', borderBottom: '1px solid rgba(255,255,255,0.1)' }}>
          <Typography.Text strong style={{ color: '#fff', fontSize: collapsed ? 16 : 18, whiteSpace: 'nowrap' }}>
            {collapsed ? 'CSERGY' : t('app.title')}
          </Typography.Text>
        </div>
        <Menu theme="dark" mode="inline" selectedKeys={[selectedKey]} items={displayMenuItems} onClick={handleMenuClick} />
      </Sider>
      <Layout style={{ marginLeft: siderCollapsed ? 80 : 220, transition: 'all 0.2s' }}>
        <Header style={{ padding: isMobile ? '0 12px' : '0 24px', background: themeToken.colorBgContainer, display: 'flex', alignItems: 'center', justifyContent: 'space-between', borderBottom: `1px solid ${themeToken.colorBorderSecondary}`, position: 'sticky', top: 0, zIndex: 99 }}>
          <Button type="text" icon={siderCollapsed ? <MenuUnfoldOutlined /> : <MenuFoldOutlined />} onClick={() => { if (isMobile) { setMobileCollapsed(!mobileCollapsed) } else { setCollapsed(!collapsed) } }} style={{ fontSize: 16, width: 40, height: 40 }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            <Dropdown menu={{ items: langMenuItems, onClick: ({ key }) => setLang(key as 'zh' | 'en') }} placement="bottomRight">
              <Button type="text" icon={<GlobalOutlined />} style={{ fontSize: 16, display: 'flex', alignItems: 'center', gap: 4 }}>
                {lang === 'zh' ? '中文' : 'EN'}
              </Button>
            </Dropdown>
            <Select
              showSearch
              value={currentTimezone}
              options={timezoneOptions}
              onChange={(val) => handleTimezoneChange(val)}
              filterOption={(input, option) =>
                (option?.label as string)?.toLowerCase().includes(input.toLowerCase()) ?? false
              }
              style={{ width: isMobile ? 100 : 160 }}
              popupMatchSelectWidth={false}
              variant="borderless"
              suffixIcon={<ClockCircleOutlined />}
            />
            {user && (
              <Badge color={ROLE_COLORS[user.role]} text={<Typography.Text style={{ fontSize: 13 }}>{ROLE_I18N_KEY[user.role] ? t(ROLE_I18N_KEY[user.role]) : ROLE_MAP[user.role] || user.role}</Typography.Text>} />
            )}
            <Dropdown menu={{ items: userMenuItemsDropdown }} placement="bottomRight">
              <div style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8 }}>
                <Avatar size="small" icon={<UserOutlined />} src={user?.avatar} />
                <Typography.Text>{user?.nickname || t('header.user')}</Typography.Text>
              </div>
            </Dropdown>
          </div>
        </Header>
        <Content style={{ margin: isMobile ? 12 : 24 }}>
          <Outlet />
        </Content>
      </Layout>

      <Modal
        title={t('modal.changePassword')}
        open={passwordModalOpen}
        onCancel={() => {
          setPasswordModalOpen(false)
          passwordForm.resetFields()
        }}
        footer={null}
        destroyOnClose
      >
        <Form
          form={passwordForm}
          onFinish={handleChangePassword}
          layout="vertical"
          style={{ marginTop: 16 }}
        >
          <Form.Item
            name="old_password"
            label={t('modal.oldPassword')}
            rules={[{ required: true, message: t('msg.oldPasswordRequired') }]}
          >
            <Input.Password prefix={<LockOutlined />} placeholder={t('modal.oldPasswordPlaceholder')} />
          </Form.Item>
          <Form.Item
            name="new_password"
            label={t('modal.newPassword')}
            rules={[
              { required: true, message: t('msg.newPasswordRequired') },
              { min: 6, message: t('msg.pwdMinLength') },
            ]}
          >
            <Input.Password prefix={<LockOutlined />} placeholder={t('modal.newPasswordPlaceholder')} />
          </Form.Item>
          <Form.Item
            name="confirm_password"
            label={t('modal.confirmPassword')}
            dependencies={['new_password']}
            rules={[
              { required: true, message: t('msg.confirmPasswordRequired') },
              ({ getFieldValue }) => ({
                validator(_, value) {
                  if (!value || getFieldValue('new_password') === value) {
                    return Promise.resolve()
                  }
                  return Promise.reject(new Error(t('msg.pwdMismatch')))
                },
              }),
            ]}
          >
            <Input.Password prefix={<LockOutlined />} placeholder={t('modal.confirmPasswordPlaceholder')} />
          </Form.Item>
          <Form.Item style={{ marginBottom: 0, textAlign: 'right' }}>
            <Button onClick={() => {
              setPasswordModalOpen(false)
              passwordForm.resetFields()
            }} style={{ marginRight: 8 }}>
              {t('modal.cancel')}
            </Button>
            <Button type="primary" htmlType="submit" loading={passwordLoading}>
              {t('modal.confirm')}
            </Button>
          </Form.Item>
        </Form>
      </Modal>

      <Modal
        title={t('modal.profile')}
        open={profileModalOpen}
        onCancel={() => {
          setProfileModalOpen(false)
          profileForm.resetFields()
        }}
        footer={null}
        destroyOnClose
      >
        <Form
          form={profileForm}
          onFinish={handleUpdateProfile}
          layout="vertical"
          style={{ marginTop: 16 }}
        >
          <Form.Item
            name="nickname"
            label={t('modal.nickname')}
          >
            <Input prefix={<UserOutlined />} placeholder={t('modal.nicknamePlaceholder')} />
          </Form.Item>
          <Form.Item
            name="timezone"
            label={t('modal.timezone')}
            extra={t('modal.timezoneExtra')}
          >
            <Select
              showSearch
              placeholder={t('modal.timezonePlaceholder')}
              options={TIMEZONE_LIST.map(tz => ({ value: tz.id, label: getTimezoneLabel(tz.id, lang) }))}
              filterOption={(input, option) =>
                (option?.label ?? '').toLowerCase().includes(input.toLowerCase())
              }
            />
          </Form.Item>
          <Form.Item style={{ marginBottom: 0, textAlign: 'right' }}>
            <Button onClick={() => {
              setProfileModalOpen(false)
              profileForm.resetFields()
            }} style={{ marginRight: 8 }}>
              {t('modal.cancel')}
            </Button>
            <Button type="primary" htmlType="submit" loading={profileLoading}>
              {t('modal.save')}
            </Button>
          </Form.Item>
        </Form>
      </Modal>
    </Layout>
  )
}

export default MainLayout
