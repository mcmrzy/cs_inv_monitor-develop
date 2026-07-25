import { useState, useEffect, useMemo } from 'react'
import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import {
  Button, Avatar, Dropdown, Badge, Typography, theme, Grid, Form, App, Select,
} from 'antd'
import { ProLayout, ModalForm, ProFormText, ProFormSelect } from '@ant-design/pro-components'
import type { ProLayoutProps } from '@ant-design/pro-components'
import {
  DashboardOutlined, DesktopOutlined, CloudUploadOutlined, AlertOutlined,
  TeamOutlined, SettingOutlined, LogoutOutlined, UserOutlined,
  ClusterOutlined, FundViewOutlined, ThunderboltOutlined,
  EnvironmentOutlined, LockOutlined, FileTextOutlined,
  HeartOutlined, ControlOutlined, UnorderedListOutlined,
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

interface RouteMenuItem {
  path: string
  name: string
  icon: React.ReactNode
  permission?: string
}

const getAdminRoutes = (t: (key: string) => string): RouteMenuItem[] => [
  { path: '/dashboard', name: t('menu.dashboard'), icon: <DashboardOutlined />, permission: 'dashboard:view' },
  { path: '/big-screen', name: t('menu.bigScreen'), icon: <FundViewOutlined />, permission: 'dashboard:view' },
  { path: '/monitoring', name: t('menu.stationMonitor'), icon: <ThunderboltOutlined />, permission: 'devices:view' },
  { path: '/stations', name: t('menu.stationManage'), icon: <EnvironmentOutlined />, permission: 'stations:view' },
  { path: '/devices', name: t('menu.deviceManage'), icon: <DesktopOutlined />, permission: 'devices:view' },
  { path: '/models', name: t('menu.modelManage'), icon: <ExperimentOutlined />, permission: 'models:view' },
  { path: '/parallel', name: t('menu.parallelManage'), icon: <ClusterOutlined />, permission: 'parallel:view' },
  { path: '/remote-settings', name: t('menu.remoteSettings'), icon: <ControlOutlined />, permission: 'devices:view' },
  { path: '/batch-settings', name: t('menu.batchSettings'), icon: <EditOutlined />, permission: 'devices:view' },
  { path: '/ota', name: t('menu.ota'), icon: <CloudUploadOutlined />, permission: 'firmware:view' },
  { path: '/alerts', name: t('menu.alertCenter'), icon: <AlertOutlined />, permission: 'alerts:view' },
  { path: '/work-orders', name: t('menu.workOrders'), icon: <FileTextOutlined />, permission: 'work_orders:view' },
  { path: '/admin', name: t('menu.systemConfig'), icon: <SettingOutlined />, permission: 'admin:view' },
  { path: '/users', name: t('menu.userManage'), icon: <TeamOutlined />, permission: 'users:view' },
  { path: '/operation-logs', name: t('menu.operationLogs'), icon: <UnorderedListOutlined />, permission: 'admin:view' },
  { path: '/system/system-monitor', name: t('menu.systemMonitor'), icon: <HeartOutlined />, permission: 'admin:view' },
]

const getUserRoutes = (t: (key: string) => string): RouteMenuItem[] => [
  { path: '/dashboard', name: t('menu.dashboard'), icon: <DashboardOutlined />, permission: 'dashboard:view' },
  { path: '/monitoring', name: t('menu.stationMonitor'), icon: <ThunderboltOutlined />, permission: 'devices:view' },
  { path: '/stations', name: t('menu.stationManage'), icon: <EnvironmentOutlined />, permission: 'stations:view' },
  { path: '/devices', name: t('menu.deviceManage'), icon: <DesktopOutlined />, permission: 'devices:view' },
  { path: '/remote-settings', name: t('menu.remoteSettings'), icon: <ControlOutlined />, permission: 'devices:view' },
  { path: '/alerts', name: t('menu.alertCenter'), icon: <AlertOutlined />, permission: 'alerts:view' },
  { path: '/work-orders', name: t('menu.workOrders'), icon: <FileTextOutlined />, permission: 'work_orders:view' },
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

  const isAdminRole = user && (user.role === Role.SUPER_ADMIN || user.role === Role.ADMIN)

  // Build ProLayout route config with permission filtering
  const routeConfig = useMemo((): ProLayoutProps['route'] => {
    const source = isAdminRole ? getAdminRoutes(t) : getUserRoutes(t)
    const filtered = source.filter(item => !item.permission || hasPermission(item.permission))
    return {
      path: '/',
      routes: filtered.map(({ permission, ...rest }) => rest),
    }
  }, [isAdminRole, hasPermission, lang, t])

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
    } catch {
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
        fetchTimezone()
        queryClient.invalidateQueries()
      }
    } catch {
      message.error(t('msg.timezoneUpdateFailed'))
    }
  }

  const siderCollapsed = isMobile ? mobileCollapsed : collapsed

  return (
    <>
      <ProLayout
        title={siderCollapsed ? 'C' : '辰烁科技 | CSERGY'}
        logo="/csergylogo.png"
        layout="mix"
        fixSiderbar
        fixedHeader
        collapsed={siderCollapsed}
        onCollapse={(val) => {
          if (isMobile) { setMobileCollapsed(val) } else { setCollapsed(val) }
        }}
        breakpoint="md"
        siderWidth={220}
        navTheme="light"
        colorPrimary="#1677ff"
        route={routeConfig}
        location={{ pathname: location.pathname }}
        menu={{ locale: false }}
        token={{
          sider: {
            colorBgMenuItemSelected: '#e6f4ff',
            colorTextMenuSelected: '#1677ff',
          },
          header: {
            colorBgHeader: '#ffffff',
          },
          pageContainer: {
            paddingBlockPageContainerContent: 0,
            paddingInlinePageContainerContent: 0,
          },
        }}
        menuItemRender={(item, dom) => (
          <a onClick={(e) => { e.preventDefault(); if (item.path) navigate(item.path) }}>{dom}</a>
        )}
        actionsRender={() => [
          <Dropdown key="lang" menu={{ items: langMenuItems, onClick: ({ key }) => setLang(key as 'zh' | 'en') }} placement="bottomRight">
            <Button type="text" icon={<GlobalOutlined />} style={{ fontSize: 14, display: 'flex', alignItems: 'center', gap: 4 }}>
              {lang === 'zh' ? '中文' : 'EN'}
            </Button>
          </Dropdown>,
          <Select
            key="tz"
            showSearch
            value={currentTimezone}
            options={timezoneOptions}
            onChange={(val) => handleTimezoneChange(val)}
            filterOption={(input, option) =>
              (option?.label as string)?.toLowerCase().includes(input.toLowerCase()) ?? false
            }
            style={{ width: isMobile ? 100 : 140 }}
            popupMatchSelectWidth={false}
            variant="borderless"
            suffixIcon={<ClockCircleOutlined />}
          />,
          user && (
            <Badge key="role" color={ROLE_COLORS[user.role]} text={<Typography.Text style={{ fontSize: 12 }}>{ROLE_I18N_KEY[user.role] ? t(ROLE_I18N_KEY[user.role]) : ROLE_MAP[user.role] || user.role}</Typography.Text>} />
          ),
        ]}
        avatarProps={{
          size: 'small',
          icon: <UserOutlined />,
          src: user?.avatar && user.avatar.startsWith('http') ? user.avatar : undefined,
          title: user?.nickname || t('header.user'),
          render: (_, dom) => (
            <Dropdown menu={{ items: userMenuItemsDropdown }} placement="bottomRight">
              {dom}
            </Dropdown>
          ),
        }}
        contentStyle={{ padding: isMobile ? 12 : 24 }}
      >
        <Outlet />
      </ProLayout>

      <ModalForm
        title={t('modal.changePassword')}
        open={passwordModalOpen}
        onOpenChange={(open) => {
          if (!open) {
            setPasswordModalOpen(false)
            passwordForm.resetFields()
          }
        }}
        form={passwordForm}
        onFinish={handleChangePassword}
        layout="vertical"
        modalProps={{ destroyOnClose: true, maskClosable: false }}
        submitter={{
          searchConfig: { submitText: t('modal.confirm'), resetText: t('modal.cancel') },
        }}
      >
        <ProFormText.Password
          name="old_password"
          label={t('modal.oldPassword')}
          rules={[{ required: true, message: t('msg.oldPasswordRequired') }]}
          fieldProps={{ prefix: <LockOutlined />, placeholder: t('modal.oldPasswordPlaceholder') }}
        />
        <ProFormText.Password
          name="new_password"
          label={t('modal.newPassword')}
          rules={[
            { required: true, message: t('msg.newPasswordRequired') },
            { min: 6, message: t('msg.pwdMinLength') },
          ]}
          fieldProps={{ prefix: <LockOutlined />, placeholder: t('modal.newPasswordPlaceholder') }}
        />
        <ProFormText.Password
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
          fieldProps={{ prefix: <LockOutlined />, placeholder: t('modal.confirmPasswordPlaceholder') }}
        />
      </ModalForm>

      <ModalForm
        title={t('modal.profile')}
        open={profileModalOpen}
        onOpenChange={(open) => {
          if (!open) {
            setProfileModalOpen(false)
            profileForm.resetFields()
          }
        }}
        form={profileForm}
        onFinish={handleUpdateProfile}
        layout="vertical"
        modalProps={{ destroyOnClose: true, maskClosable: false }}
        submitter={{
          searchConfig: { submitText: t('modal.save'), resetText: t('modal.cancel') },
        }}
      >
        <ProFormText
          name="nickname"
          label={t('modal.nickname')}
          fieldProps={{ prefix: <UserOutlined />, placeholder: t('modal.nicknamePlaceholder') }}
        />
        <ProFormSelect
          name="timezone"
          label={t('modal.timezone')}
          extra={t('modal.timezoneExtra')}
          fieldProps={{
            showSearch: true,
            placeholder: t('modal.timezonePlaceholder'),
            options: TIMEZONE_LIST.map(tz => ({ value: tz.id, label: getTimezoneLabel(tz.id, lang) })),
            filterOption: (input: string, option: { label?: string } | undefined) =>
              (option?.label ?? '').toLowerCase().includes(input.toLowerCase()),
          }}
        />
      </ModalForm>
    </>
  )
}

export default MainLayout
