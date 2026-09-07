import { BrowserRouter, Routes, Route, Navigate, useLocation } from 'react-router-dom'
import { Suspense, useEffect } from 'react'
import lazyWithRetry from '@/utils/lazyWithRetry'
import { ConfigProvider, App as AntApp, Spin } from 'antd'
import zhCN from 'antd/es/locale/zh_CN'
import enUS from 'antd/es/locale/en_US'
import dayjs from 'dayjs'
import 'dayjs/locale/zh-cn'
import MainLayout from '@/layouts/MainLayout'
import ProtectedRoute from '@/components/ProtectedRoute'
import PermissionRoute from '@/components/PermissionRoute'
import OrganizationRoute from '@/components/OrganizationRoute'
import ErrorBoundary from '@/components/ErrorBoundary'
import { getRoutePermissions, selectDefaultRoute } from '@/router/routeAccess'
import useAuthStore from '@/stores/authStore'
import useLocaleStore from '@/stores/localeStore'
import useTimezoneStore from '@/stores/timezoneStore'

const LoginPage = lazyWithRetry(() => import('@/pages/login'))
const InviteAcceptPage = lazyWithRetry(() => import('@/pages/invite/InviteAcceptPage'))
const UnauthorizedPage = lazyWithRetry(() => import('@/pages/unauthorized'))
const DashboardPage = lazyWithRetry(() => import('@/pages/dashboard'))
const DevicesPage = lazyWithRetry(() => import('@/pages/devices'))
const OtaPage = lazyWithRetry(() => import('@/pages/ota'))
const AlertsPage = lazyWithRetry(() => import('@/pages/alerts'))
const UsersPage = lazyWithRetry(() => import('@/pages/users'))
const AdminPage = lazyWithRetry(() => import('@/pages/admin'))
const WorkOrdersPage = lazyWithRetry(() => import('@/pages/work-orders'))
const BigScreenPage = lazyWithRetry(() => import('@/pages/big-screen'))
const ParallelPage = lazyWithRetry(() => import('@/pages/parallel'))
const StationsPage = lazyWithRetry(() => import('@/pages/stations'))
const StationDetailPage = lazyWithRetry(() => import('@/pages/stations/StationDetailPage'))
const ModelsPage = lazyWithRetry(() => import('@/pages/models'))
const MonitoringPage = lazyWithRetry(() => import('@/pages/monitoring'))
const RemoteSettingsPage = lazyWithRetry(() => import('@/pages/remote-settings'))
const BatchSettingsPage = lazyWithRetry(() => import('@/pages/batch-settings'))
const OperationLogsPage = lazyWithRetry(() => import('@/pages/operation-logs'))
const DeviceDetailPage = lazyWithRetry(() => import('@/pages/device-detail'))
const SystemMonitorPage = lazyWithRetry(() => import('@/pages/system/SystemMonitor'))
const SystemConfigPage = lazyWithRetry(() => import('@/pages/system/SystemConfig'))
const DownloadPage = lazyWithRetry(() => import('@/pages/download'))

const RoleRedirect: React.FC = () => {
  const user = useAuthStore((s) => s.user)
  const hasAnyPermission = useAuthStore((s) => s.hasAnyPermission)
  return <Navigate to={selectDefaultRoute(user?.isSystemAdmin === true, hasAnyPermission)} replace />
}

export const AppRoutes: React.FC = () => (
  <Routes>
    <Route path="/login" element={<LoginPage />} />
    <Route path="/invite/:token" element={<InviteAcceptPage />} />
    <Route path="/unauthorized" element={<UnauthorizedPage />} />
    <Route path="/download" element={<DownloadPage />} />
    <Route
      path="/"
      element={
        <ProtectedRoute>
          <RoleRedirect />
        </ProtectedRoute>
      }
    />
    <Route
      path="/big-screen"
      element={
        <ProtectedRoute>
          <PermissionRoute permissions={getRoutePermissions('/big-screen')}>
            <BigScreenPage />
          </PermissionRoute>
        </ProtectedRoute>
      }
    />
    {/* 设备完整详情页：全屏布局（无侧边栏），便于聚焦查看 */}
    <Route
      path="/devices/:sn/detail"
      element={
        <ProtectedRoute>
          <PermissionRoute permissions={getRoutePermissions('/devices/:sn/detail')}>
            <DeviceDetailPage />
          </PermissionRoute>
        </ProtectedRoute>
      }
    />
    <Route
      element={
        <ProtectedRoute>
          <MainLayout />
        </ProtectedRoute>
      }
    >
      <Route path="/dashboard" element={<PermissionRoute permissions={getRoutePermissions('/dashboard')}><DashboardPage /></PermissionRoute>} />
      <Route path="/devices" element={<PermissionRoute permissions={getRoutePermissions('/devices')}><DevicesPage /></PermissionRoute>} />
      <Route path="/ota" element={<PermissionRoute permissions={getRoutePermissions('/ota')}><OtaPage /></PermissionRoute>} />
      <Route path="/alerts" element={<PermissionRoute permissions={getRoutePermissions('/alerts')}><AlertsPage /></PermissionRoute>} />
      <Route path="/work-orders" element={<PermissionRoute permissions={getRoutePermissions('/work-orders')}><WorkOrdersPage /></PermissionRoute>} />
      <Route path="/users" element={<PermissionRoute permissions={getRoutePermissions('/users')}><UsersPage /></PermissionRoute>} />
      <Route path="/organizations" element={<OrganizationRoute><AdminPage /></OrganizationRoute>} />
      {/* 旧路径兼容：/admin → /organizations */}
      <Route path="/admin" element={<Navigate to="/organizations" replace />} />
      <Route path="/parallel" element={<PermissionRoute permissions={getRoutePermissions('/parallel')}><ParallelPage /></PermissionRoute>} />
      <Route path="/stations" element={<PermissionRoute permissions={getRoutePermissions('/stations')}><StationsPage /></PermissionRoute>} />
      <Route path="/stations/:id" element={<PermissionRoute permissions={getRoutePermissions('/stations/:id')}><StationDetailPage /></PermissionRoute>} />
      <Route path="/models" element={<PermissionRoute permissions={getRoutePermissions('/models')}><ModelsPage /></PermissionRoute>} />
      <Route path="/monitoring" element={<PermissionRoute permissions={getRoutePermissions('/monitoring')}><MonitoringPage /></PermissionRoute>} />
      <Route path="/monitoring/:id" element={<PermissionRoute permissions={getRoutePermissions('/monitoring/:id')}><StationDetailPage /></PermissionRoute>} />
      <Route path="/remote-settings" element={<PermissionRoute permissions={getRoutePermissions('/remote-settings')}><RemoteSettingsPage /></PermissionRoute>} />
      <Route path="/batch-settings" element={<PermissionRoute permissions={getRoutePermissions('/batch-settings')}><BatchSettingsPage /></PermissionRoute>} />
      <Route path="/operation-logs" element={<PermissionRoute permissions={getRoutePermissions('/operation-logs')}><OperationLogsPage /></PermissionRoute>} />
      <Route path="/system/system-monitor" element={<PermissionRoute permissions={getRoutePermissions('/system/system-monitor')}><SystemMonitorPage /></PermissionRoute>} />
      <Route path="/system/system-config" element={<PermissionRoute permissions={getRoutePermissions('/system/system-config')}><SystemConfigPage /></PermissionRoute>} />
    </Route>
  </Routes>
)

/**
 * 路由感知的错误边界：以路由路径作为 key，
 * 某个页面发生渲染错误（如接口数据异常导致的 d.map is not a function）时，
 * 切换到其他菜单/路由会自动重置错误状态恢复使用，避免整个应用卡死在错误页必须手动刷新。
 */
const RoutableErrorBoundary: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const location = useLocation()
  return <ErrorBoundary key={location.pathname}>{children}</ErrorBoundary>
}

const App: React.FC = () => {
  const lang = useLocaleStore((s) => s.lang)
  const fetchTimezone = useTimezoneStore((s) => s.fetchTimezone)

  useEffect(() => {
    fetchTimezone()
  }, [fetchTimezone])

  // 根据语言设置dayjs locale
  useEffect(() => {
    dayjs.locale(lang === 'zh' ? 'zh-cn' : 'en')
  }, [lang])

  return (
    <ConfigProvider
      locale={lang === 'zh' ? zhCN : enUS}
      theme={{
        token: {
          colorPrimary: '#1677ff',
          colorSuccess: '#52c41a',
          colorWarning: '#faad14',
          colorError: '#ff4d4f',
          colorInfo: '#1677ff',
          borderRadius: 8,
          fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'PingFang SC', 'Microsoft YaHei', sans-serif",
          fontSize: 14,
          colorBgLayout: '#f5f5f5',
          colorBgContainer: '#ffffff',
          boxShadow: '0 1px 2px 0 rgba(0,0,0,0.03), 0 1px 6px -1px rgba(0,0,0,0.02), 0 2px 4px 0 rgba(0,0,0,0.02)',
          boxShadowSecondary: '0 6px 16px 0 rgba(0,0,0,0.08), 0 3px 6px -4px rgba(0,0,0,0.12), 0 9px 28px 8px rgba(0,0,0,0.05)',
        },
        components: {
          Button: {
            controlHeight: 38,
            fontWeight: 500,
          },
          Card: {
            paddingLG: 24,
          },
          Table: {
            headerBg: '#fafafa',
            headerColor: '#000000d9',
            rowHoverBg: '#f5f5f5',
          },
          Menu: {
            itemBorderRadius: 6,
            subMenuItemBorderRadius: 6,
            itemMarginInline: 8,
            itemHeight: 40,
            iconSize: 16,
            itemSelectedBg: '#e6f4ff',
            itemSelectedColor: '#1677ff',
          },
          Input: {
            controlHeight: 40,
          },
          Select: {
            controlHeight: 40,
          },
        },
      }}
    >
      <AntApp>
        <BrowserRouter>
          <RoutableErrorBoundary>
            <Suspense fallback={<div style={{ minHeight: 240, display: 'grid', placeItems: 'center' }}><Spin size="large" /></div>}>
              <AppRoutes />
            </Suspense>
          </RoutableErrorBoundary>
        </BrowserRouter>
      </AntApp>
    </ConfigProvider>
  )
}

export default App
