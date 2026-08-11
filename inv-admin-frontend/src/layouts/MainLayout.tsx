import { useState, useEffect, useMemo } from 'react'
import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Button, Avatar, Dropdown, Badge, Typography, theme, Grid, Form, App, Select, Cascader, Modal, Input, Space,
} from 'antd'
import { ProLayout, ModalForm, ProFormText, ProFormSelect } from '@ant-design/pro-components'
import type { ProLayoutProps } from '@ant-design/pro-components'
import {
  DashboardOutlined, DesktopOutlined, CloudUploadOutlined, AlertOutlined,
  TeamOutlined, SettingOutlined, LogoutOutlined, UserOutlined,
  ClusterOutlined, ThunderboltOutlined,
  EnvironmentOutlined, LockOutlined, FileTextOutlined,
  HeartOutlined, ControlOutlined, UnorderedListOutlined,
  EditOutlined, ExperimentOutlined, GlobalOutlined, ClockCircleOutlined,
} from '@ant-design/icons'
import useAuthStore from '@/stores/authStore'
import useLocaleStore from '@/stores/localeStore'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import api from '@/services/api'
import { channelApi } from '@/services/channelApi'
import { queryKeys } from '@/utils/queryKeys'
import { TIMEZONE_LIST, REGION_LABELS, getTimezoneLabel } from '@/utils/timezone'
import UploadAvatar from '@/components/UploadAvatar'
import RegionPicker from '@/components/RegionPicker'


interface RouteMenuItem {
  path: string
  name: string
  icon: React.ReactNode
  permission?: string
}

const getAdminRoutes = (t: (key: string) => string): RouteMenuItem[] => [
  { path: '/dashboard', name: t('menu.dashboard'), icon: <DashboardOutlined />, permission: 'dashboard:view' },
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
  // 组织架构对所有登录用户开放（后端按可见范围剪枝 + 角色校验兑底）
  { path: '/organizations', name: t('menu.orgManagement'), icon: <SettingOutlined /> },
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
  // 组织架构对所有登录用户开放（后端按可见范围剪枝 + 角色校验兑底）
  { path: '/organizations', name: t('menu.orgManagement'), icon: <SettingOutlined /> },
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
  const [profileAvatar, setProfileAvatar] = useState('')
  const [timezoneModalOpen, setTimezoneModalOpen] = useState(false)
  const [phoneModalOpen, setPhoneModalOpen] = useState(false)
  const [emailModalOpen, setEmailModalOpen] = useState(false)
  const [phoneForm] = Form.useForm()
  const [emailForm] = Form.useForm()
  const [codeSending, setCodeSending] = useState(false)
  const [codeCountdown, setCodeCountdown] = useState(0)
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

  const isAdminRole = user && (user.isSystemAdmin || hasPermission('admin:manage'))

  // 纯终端用户识别：非系统管理员且所有组织角色并集仅含 customer（无任何管理/渠道角色）
  // 终端用户不可见组织架构（/organizations）入口；其余登录用户（含普通组织管理员）均可见
  const { data: myOrgsData } = useQuery({
    queryKey: queryKeys.channels.myOrganizations(user?.id),
    queryFn: () => channelApi.getMyOrganizations().then((r) => r.data?.data ?? []),
    enabled: !!user && !user.isSystemAdmin,
  })

  const isEndUser = useMemo(() => {
    if (!user || user.isSystemAdmin) return false
    const orgs = (myOrgsData ?? []) as Array<{ roles?: string[]; role?: string }>
    if (!Array.isArray(orgs) || orgs.length === 0) return false
    const roleSet = new Set<string>()
    for (const org of orgs) {
      const roles = Array.isArray(org.roles) && org.roles.length > 0 ? org.roles : org.role ? [org.role] : []
      roles.forEach((r) => roleSet.add(r))
    }
    // 无角色信息（保守）或仅 customer 角色 → 视为终端用户
    return roleSet.size > 0 && [...roleSet].every((r) => r === 'customer')
  }, [user, myOrgsData])

  // Build ProLayout route config with permission filtering
  const routeConfig = useMemo((): ProLayoutProps['route'] => {
    const source = isAdminRole ? getAdminRoutes(t) : getUserRoutes(t)
    // 终端用户不可见组织架构入口；其余菜单按权限过滤
    const filtered = source.filter(
      (item) =>
        !(item.path === '/organizations' && isEndUser) &&
        (!item.permission || hasPermission(item.permission)),
    )
    return {
      path: '/',
      routes: filtered.map(({ permission, ...rest }) => rest),
    }
  }, [isAdminRole, isEndUser, hasPermission, lang, t])

  const handleLogout = () => {
    logout()
    // 清空全局查询缓存，避免跨用户数据串味（如组织角色等按用户维度的数据）
    queryClient.clear()
    navigate('/login')
  }

  const handleOpenProfile = () => {
    setProfileAvatar(user?.avatar || '')
    profileForm.setFieldsValue({
      nickname: user?.nickname || '',
      avatar: user?.avatar || '',
      email: user?.email || '',
      phone: user?.phone || '',
      region: user?.country ? [user.country, user.region_name || ''] : [],
    })
    setProfileModalOpen(true)
  }

  const handleUpdateProfile = async (values: {
    nickname: string
    avatar: string
    email?: string
    region?: string[]
  }) => {
    setProfileLoading(true)
    try {
      // 将region数组转换为country和region_name
      const submitValues: Record<string, unknown> = {
        nickname: values.nickname,
        avatar: values.avatar,
        email: values.email,
      }
      if (values.region && values.region.length >= 2) {
        submitValues.country = values.region[0]
        submitValues.region_name = values.region[1]
      } else if (values.region && values.region.length === 1) {
        submitValues.country = values.region[0]
        submitValues.region_name = ''
      }
      
      const res = await api.put('/auth/profile', submitValues)
      const responseData = res.data as Record<string, unknown>
      if (responseData?.code !== undefined && responseData.code !== 0) {
        message.error((responseData.message as string) || t('msg.profileUpdateFailed'))
        return
      }
      message.success(t('msg.profileUpdated'))
      setProfileModalOpen(false)
      if (user) {
        const updatedUser = {
          ...user,
          nickname: values.nickname,
          avatar: values.avatar,
          email: values.email || user.email,
          country: (submitValues.country as string) || user.country,
          region_name: (submitValues.region_name as string) || user.region_name,
        }
        useAuthStore.setState({ user: updatedUser })
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
    { type: 'divider' as const },
    { key: 'lang', icon: <GlobalOutlined />, label: lang === 'zh' ? 'English' : '中文', onClick: () => setLang(lang === 'zh' ? 'en' : 'zh') },
    { key: 'timezone', icon: <ClockCircleOutlined />, label: t('header.timezone'), onClick: () => setTimezoneModalOpen(true) },
    { type: 'divider' as const },
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

  // 路由级兑底：终端用户直达 /organizations 时重定向（菜单已隐藏入口，这里拦截 URL 直达）
  useEffect(() => {
    if (isEndUser && location.pathname.startsWith('/organizations')) {
      navigate('/unauthorized', { replace: true })
    }
  }, [isEndUser, location.pathname, navigate])

  return (
    <>
      <ProLayout
        title={false}
        logo={<img src="/csergylogo.png" alt="logo" style={{ height: 48, width: 'auto' }} />}
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
          user && (
            <Badge key="role" color={user.isSystemAdmin ? '#eb2f96' : '#1677ff'} text={<Typography.Text style={{ fontSize: 12 }}>{user.isSystemAdmin ? t('header.systemAdmin') : (hasPermission('admin:manage') ? t('header.orgAdmin') : t('header.member'))}</Typography.Text>} />
          ),
        ]}
        avatarProps={{
          size: 'small',
          icon: <UserOutlined />,
          src: user?.avatar && (user.avatar.startsWith('http') || user.avatar.startsWith('/uploads/')) ? user.avatar : undefined,
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
        modalProps={{ destroyOnHidden: true, maskClosable: false }}
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
        width={480}
        modalProps={{ destroyOnHidden: true, maskClosable: false }}
        submitter={{
          searchConfig: { submitText: t('modal.save'), resetText: t('modal.cancel') },
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', marginBottom: 24 }}>
          <UploadAvatar
            value={profileAvatar}
            onChange={(url) => { setProfileAvatar(url); profileForm.setFieldsValue({ avatar: url }) }}
            size={100}
          />
        </div>
        <Form.Item name="avatar" hidden>
          <input />
        </Form.Item>
        <ProFormText
          name="nickname"
          label={t('modal.nickname')}
          fieldProps={{ prefix: <UserOutlined />, placeholder: t('modal.nicknamePlaceholder'), style: { width: 240 } }}
        />
        <Form.Item label={t('modal.phone')}>
          <Space>
            <Input
              value={user?.phone || ''}
              disabled
              style={{ width: 240 }}
              placeholder={t('modal.phonePlaceholder')}
            />
            <Button onClick={() => setPhoneModalOpen(true)}>{t('modal.change')}</Button>
          </Space>
        </Form.Item>
        <Form.Item label={t('modal.email')}>
          <Space>
            <Input
              value={user?.email || ''}
              disabled
              style={{ width: 240 }}
              placeholder={t('modal.emailPlaceholder')}
            />
            <Button onClick={() => setEmailModalOpen(true)}>{t('modal.change')}</Button>
          </Space>
        </Form.Item>
        <Form.Item
          name="region"
          label={t('modal.region')}
        >
          <RegionPicker
            placeholder={t('modal.regionPlaceholder')}
            style={{ width: 240 }}
            mode="profile"
          />
        </Form.Item>
      </ModalForm>

      <ModalForm
        title={t('header.timezone')}
        open={timezoneModalOpen}
        onOpenChange={(open) => {
          if (!open) {
            setTimezoneModalOpen(false)
          }
        }}
        form={Form.useForm()[0]}
        onFinish={async (values) => {
          await handleTimezoneChange(values.timezone)
          setTimezoneModalOpen(false)
          return true
        }}
        layout="vertical"
        modalProps={{ destroyOnHidden: true, maskClosable: false }}
        submitter={{
          searchConfig: { submitText: t('modal.save'), resetText: t('modal.cancel') },
        }}
        initialValues={{ timezone: currentTimezone }}
      >
        <ProFormSelect
          name="timezone"
          label={t('modal.timezone')}
          extra={t('modal.timezoneExtra')}
          fieldProps={{
            showSearch: true,
            placeholder: t('modal.timezonePlaceholder'),
            options: timezoneOptions,
            filterOption: (input: string, option: { label?: string } | undefined) =>
              (option?.label ?? '').toLowerCase().includes(input.toLowerCase()),
          }}
        />
      </ModalForm>

      {/* 手机号更改弹窗 */}
      <Modal
        title={t('modal.changePhone')}
        open={phoneModalOpen}
        onCancel={() => {
          setPhoneModalOpen(false)
          phoneForm.resetFields()
        }}
        onOk={async () => {
          try {
            const values = await phoneForm.validateFields()
            const res = await api.put('/auth/change-phone', {
              new_phone: values.newPhone,
              code: values.phoneCode,
            })
            const responseData = res.data as Record<string, unknown>
            if (responseData?.code !== undefined && responseData.code !== 0) {
              message.error((responseData.message as string) || t('msg.profileUpdateFailed'))
              return
            }
            message.success(t('msg.phoneChanged'))
            setPhoneModalOpen(false)
            phoneForm.resetFields()
            // 刷新用户信息
            queryClient.invalidateQueries({ queryKey: ['user', 'profile'] })
          } catch (error) {
            // 验证失败
          }
        }}
        destroyOnHidden
        maskClosable={false}
      >
        <Form form={phoneForm} layout="vertical">
          <Form.Item
            name="newPhone"
            label={t('modal.newPhone')}
            rules={[{ required: true, message: t('msg.newPhoneRequired') }]}
          >
            <Input placeholder={t('modal.newPhonePlaceholder')} />
          </Form.Item>
          <Form.Item
            name="phoneCode"
            label={t('modal.verifyCode')}
            rules={[{ required: true, message: t('msg.codeRequired') }]}
          >
            <Space>
              <Input placeholder={t('modal.codePlaceholder')} style={{ width: 200 }} />
              <Button
                onClick={async () => {
                  const phone = phoneForm.getFieldValue('newPhone')
                  if (!phone) {
                    message.warning(t('msg.newPhoneRequired'))
                    return
                  }
                  try {
                    const res = await api.post('/auth/send-phone-code', { phone })
                    const responseData = res.data as Record<string, unknown>
                    if (responseData?.code !== undefined && responseData.code !== 0) {
                      message.error((responseData.message as string) || 'Failed to send code')
                      return
                    }
                    message.success(t('modal.sendCode') + ' ✓')
                    setCodeSending(true)
                    setCodeCountdown(60)
                    const timer = setInterval(() => {
                      setCodeCountdown((prev) => {
                        if (prev <= 1) {
                          clearInterval(timer)
                          setCodeSending(false)
                          return 0
                        }
                        return prev - 1
                      })
                    }, 1000)
                  } catch {
                    message.error('Failed to send code')
                  }
                }}
                disabled={codeSending}
                loading={codeSending}
              >
                {codeSending ? `${codeCountdown}s` : t('modal.sendCode')}
              </Button>
            </Space>
          </Form.Item>
        </Form>
      </Modal>

      {/* 邮箱更改弹窗 */}
      <Modal
        title={t('modal.changeEmail')}
        open={emailModalOpen}
        onCancel={() => {
          setEmailModalOpen(false)
          emailForm.resetFields()
        }}
        onOk={async () => {
          try {
            const values = await emailForm.validateFields()
            const res = await api.put('/auth/change-email', {
              new_email: values.newEmail,
              code: values.emailCode,
            })
            const responseData = res.data as Record<string, unknown>
            if (responseData?.code !== undefined && responseData.code !== 0) {
              message.error((responseData.message as string) || t('msg.profileUpdateFailed'))
              return
            }
            message.success(t('msg.emailChanged'))
            setEmailModalOpen(false)
            emailForm.resetFields()
            // 刷新用户信息
            queryClient.invalidateQueries({ queryKey: ['user', 'profile'] })
          } catch (error) {
            // 验证失败
          }
        }}
        destroyOnHidden
        maskClosable={false}
      >
        <Form form={emailForm} layout="vertical">
          <Form.Item
            name="newEmail"
            label={t('modal.newEmail')}
            rules={[
              { required: true, message: t('msg.newEmailRequired') },
              { type: 'email', message: t('msg.invalidEmail') },
            ]}
          >
            <Input placeholder={t('modal.newEmailPlaceholder')} />
          </Form.Item>
          <Form.Item
            name="emailCode"
            label={t('modal.verifyCode')}
            rules={[{ required: true, message: t('msg.codeRequired') }]}
          >
            <Space>
              <Input placeholder={t('modal.codePlaceholder')} style={{ width: 200 }} />
              <Button
                onClick={async () => {
                  const email = emailForm.getFieldValue('newEmail')
                  if (!email) {
                    message.warning(t('msg.newEmailRequired'))
                    return
                  }
                  try {
                    const res = await api.post('/auth/send-email-change-code', { email })
                    const responseData = res.data as Record<string, unknown>
                    if (responseData?.code !== undefined && responseData.code !== 0) {
                      message.error((responseData.message as string) || 'Failed to send code')
                      return
                    }
                    message.success(t('modal.sendCode') + ' ✓')
                    setCodeSending(true)
                    setCodeCountdown(60)
                    const timer = setInterval(() => {
                      setCodeCountdown((prev) => {
                        if (prev <= 1) {
                          clearInterval(timer)
                          setCodeSending(false)
                          return 0
                        }
                        return prev - 1
                      })
                    }, 1000)
                  } catch {
                    message.error('Failed to send code')
                  }
                }}
                disabled={codeSending}
                loading={codeSending}
              >
                {codeSending ? `${codeCountdown}s` : t('modal.sendCode')}
              </Button>
            </Space>
          </Form.Item>
        </Form>
      </Modal>
    </>
  )
}

export default MainLayout
