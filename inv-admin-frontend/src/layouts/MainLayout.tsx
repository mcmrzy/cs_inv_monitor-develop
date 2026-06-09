import { useState, useEffect, useMemo } from 'react'
import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import {
  Layout, Menu, Button, Avatar, Dropdown, Badge, Typography, theme, Grid, Modal, Form, Input, App,
} from 'antd'
import {
  DashboardOutlined, DesktopOutlined, CloudUploadOutlined, AlertOutlined,
  ToolOutlined, TeamOutlined, SettingOutlined, LogoutOutlined, UserOutlined,
  MenuFoldOutlined, MenuUnfoldOutlined, SafetyOutlined, ClusterOutlined,
  FundViewOutlined, HomeOutlined, ThunderboltOutlined, HistoryOutlined,
  EnvironmentOutlined, LockOutlined, FileTextOutlined,
} from '@ant-design/icons'
import useAuthStore from '@/stores/authStore'
import { ROLE_MAP, ROLE_COLORS } from '@/utils/constants'
import { Role } from '@/types'
import api from '@/services/api'

const { Header, Sider, Content } = Layout

interface MenuItem {
  key: string
  icon: React.ReactNode
  label: string
  permission?: string
}

const adminMenuItems: MenuItem[] = [
  { key: '/dashboard', icon: <DashboardOutlined />, label: '仪表盘', permission: 'dashboard:view' },
  { key: '/devices', icon: <DesktopOutlined />, label: '设备管理', permission: 'devices:view' },
  { key: '/ota', icon: <CloudUploadOutlined />, label: 'OTA升级', permission: 'firmware:view' },
  { key: '/alerts', icon: <AlertOutlined />, label: '告警管理', permission: 'alerts:view' },
  { key: '/alert-rules', icon: <SafetyOutlined />, label: '告警规则', permission: 'alert_rules:view' },
  { key: '/work-orders', icon: <ToolOutlined />, label: '工单管理', permission: 'work_orders:view' },
  { key: '/parallel', icon: <ClusterOutlined />, label: '并机管理', permission: 'parallel:view' },
  { key: '/stations', icon: <EnvironmentOutlined />, label: '电站管理', permission: 'stations:view' },
  { key: '/models', icon: <SettingOutlined />, label: '型号管理', permission: 'models:view' },
  { key: '/users', icon: <TeamOutlined />, label: '用户管理', permission: 'users:view' },
  { key: '/admin', icon: <SettingOutlined />, label: '系统管理', permission: 'admin:view' },
  { key: '/big-screen', icon: <FundViewOutlined />, label: '大屏监控', permission: 'dashboard:view' },
]

const userMenuItems: MenuItem[] = [
  { key: '/dashboard', icon: <DashboardOutlined />, label: '仪表盘', permission: 'dashboard:view' },
  { key: '/devices', icon: <DesktopOutlined />, label: '设备管理', permission: 'devices:view' },
  { key: '/stations', icon: <EnvironmentOutlined />, label: '电站管理', permission: 'stations:view' },
  { key: '/alerts', icon: <AlertOutlined />, label: '告警管理', permission: 'alerts:view' },
  { key: '/alert-rules', icon: <AlertOutlined />, label: '告警规则', permission: 'alert_rules:view' },
  { key: '/work-orders', icon: <FileTextOutlined />, label: '工单管理', permission: 'work_orders:view' },
  { key: '/portal', icon: <HomeOutlined />, label: '我的电站', permission: 'dashboard:view' },
]

const MainLayout: React.FC = () => {
  const [collapsed, setCollapsed] = useState(false)
  const [mobileCollapsed, setMobileCollapsed] = useState(true)
  const [passwordModalOpen, setPasswordModalOpen] = useState(false)
  const [passwordLoading, setPasswordLoading] = useState(false)
  const [passwordForm] = Form.useForm()
  const navigate = useNavigate()
  const location = useLocation()
  const { user, logout, hasPermission } = useAuthStore()
  const { token: themeToken } = theme.useToken()
  const screens = Grid.useBreakpoint()
  const { message } = App.useApp()

  const isMobile = !screens.md

  useEffect(() => {
    if (!screens.md) { setMobileCollapsed(true) } else { setMobileCollapsed(false) }
  }, [screens.md])

  const siderCollapsed = isMobile ? mobileCollapsed : collapsed

  const isAdminRole = user && (user.role === Role.SUPER_ADMIN || user.role === Role.AGENT)

  const displayMenuItems = useMemo(() => {
    const source = isAdminRole ? adminMenuItems : userMenuItems
    return source
      .filter(item => !item.permission || hasPermission(item.permission))
      .map(({ permission, ...rest }) => rest)
  }, [isAdminRole, hasPermission])

  const selectedKey = '/' + (location.pathname.split('/')[1] || (isAdminRole ? 'dashboard' : 'portal'))

  const handleMenuClick = (info: { key: string }) => {
    navigate(info.key)
  }

  const handleLogout = () => {
    logout()
    navigate('/login')
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
        message.error((responseData.message as string) || '修改密码失败')
        return
      }
      message.success('密码修改成功')
      setPasswordModalOpen(false)
      passwordForm.resetFields()
    } catch (error) {
      message.error('修改密码失败，请检查旧密码是否正确')
    } finally {
      setPasswordLoading(false)
    }
  }

  const userMenuItemsDropdown = [
    { key: 'profile', icon: <UserOutlined />, label: '个人信息' },
    { key: 'change-password', icon: <LockOutlined />, label: '修改密码', onClick: () => setPasswordModalOpen(true) },
    { key: 'logout', icon: <LogoutOutlined />, label: '退出登录', danger: true, onClick: handleLogout },
  ]

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
            {collapsed ? 'INV' : '逆变器物联平台'}
          </Typography.Text>
        </div>
        <Menu theme="dark" mode="inline" selectedKeys={[selectedKey]} items={displayMenuItems} onClick={handleMenuClick} />
      </Sider>
      <Layout style={{ marginLeft: siderCollapsed ? 80 : 220, transition: 'all 0.2s' }}>
        <Header style={{ padding: isMobile ? '0 12px' : '0 24px', background: themeToken.colorBgContainer, display: 'flex', alignItems: 'center', justifyContent: 'space-between', borderBottom: `1px solid ${themeToken.colorBorderSecondary}`, position: 'sticky', top: 0, zIndex: 99 }}>
          <Button type="text" icon={siderCollapsed ? <MenuUnfoldOutlined /> : <MenuFoldOutlined />} onClick={() => { if (isMobile) { setMobileCollapsed(!mobileCollapsed) } else { setCollapsed(!collapsed) } }} style={{ fontSize: 16, width: 40, height: 40 }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            {user && (
              <Badge color={ROLE_COLORS[user.role]} text={<Typography.Text style={{ fontSize: 13 }}>{ROLE_MAP[user.role] || user.role}</Typography.Text>} />
            )}
            <Dropdown menu={{ items: userMenuItemsDropdown }} placement="bottomRight">
              <div style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8 }}>
                <Avatar size="small" icon={<UserOutlined />} src={user?.avatar} />
                <Typography.Text>{user?.nickname || '用户'}</Typography.Text>
              </div>
            </Dropdown>
          </div>
        </Header>
        <Content style={{ margin: isMobile ? 12 : 24 }}>
          <Outlet />
        </Content>
      </Layout>

      <Modal
        title="修改密码"
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
            label="旧密码"
            rules={[{ required: true, message: '请输入旧密码' }]}
          >
            <Input.Password prefix={<LockOutlined />} placeholder="请输入旧密码" />
          </Form.Item>
          <Form.Item
            name="new_password"
            label="新密码"
            rules={[
              { required: true, message: '请输入新密码' },
              { min: 6, message: '密码至少6位' },
            ]}
          >
            <Input.Password prefix={<LockOutlined />} placeholder="请输入新密码" />
          </Form.Item>
          <Form.Item
            name="confirm_password"
            label="确认新密码"
            dependencies={['new_password']}
            rules={[
              { required: true, message: '请确认新密码' },
              ({ getFieldValue }) => ({
                validator(_, value) {
                  if (!value || getFieldValue('new_password') === value) {
                    return Promise.resolve()
                  }
                  return Promise.reject(new Error('两次输入的密码不一致'))
                },
              }),
            ]}
          >
            <Input.Password prefix={<LockOutlined />} placeholder="请确认新密码" />
          </Form.Item>
          <Form.Item style={{ marginBottom: 0, textAlign: 'right' }}>
            <Button onClick={() => {
              setPasswordModalOpen(false)
              passwordForm.resetFields()
            }} style={{ marginRight: 8 }}>
              取消
            </Button>
            <Button type="primary" htmlType="submit" loading={passwordLoading}>
              确认修改
            </Button>
          </Form.Item>
        </Form>
      </Modal>
    </Layout>
  )
}

export default MainLayout
