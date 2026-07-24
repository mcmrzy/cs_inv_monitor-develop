import { BrowserRouter, Router, Routes, Route, Navigate } from 'react-router-dom'
import type { History } from '@remix-run/router'
import { Suspense, useEffect, useState } from 'react'
import lazyWithRetry from '@/utils/lazyWithRetry'
import { ConfigProvider, App as AntApp, Spin } from 'antd'
import zhCN from 'antd/locale/zh_CN'
import enUS from 'antd/locale/en_US'
import MainLayout from '@/layouts/MainLayout'
import ProtectedRoute from '@/components/ProtectedRoute'
import ErrorBoundary from '@/components/ErrorBoundary'
import useAuthStore from '@/stores/authStore'
import useLocaleStore from '@/stores/localeStore'
import useTimezoneStore from '@/stores/timezoneStore'
import { Role } from '@/types'

const LoginPage = lazyWithRetry(() => import('@/pages/login'))
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
const PipelineHealthPage = lazyWithRetry(() => import('@/pages/system/PipelineHealth'))

const RoleRedirect: React.FC = () => {
  const user = useAuthStore((s) => s.user)
  if (user?.role === Role.INSTALLER) {
    return <Navigate to="/devices" replace />
  }
  if (user?.role === Role.END_USER) {
    return <Navigate to="/dashboard" replace />
  }
  return <Navigate to="/dashboard" replace />
}

const AppRoutes: React.FC = () => (
  <Routes>
    <Route path="/login" element={<LoginPage />} />
    <Route path="/unauthorized" element={<UnauthorizedPage />} />
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
          <BigScreenPage />
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
      <Route path="/dashboard" element={<DashboardPage />} />
      <Route path="/devices" element={<DevicesPage />} />
      <Route path="/ota" element={<OtaPage />} />
      <Route path="/alerts" element={<AlertsPage />} />
      <Route path="/work-orders" element={<WorkOrdersPage />} />
      <Route path="/users" element={<UsersPage />} />
      <Route path="/admin" element={<AdminPage />} />
      <Route path="/parallel" element={<ParallelPage />} />
      <Route path="/stations" element={<StationsPage />} />
      <Route path="/stations/:id" element={<StationDetailPage />} />
      <Route path="/models" element={<ModelsPage />} />
      <Route path="/monitoring" element={<MonitoringPage />} />
      <Route path="/monitoring/:id" element={<StationDetailPage />} />
      <Route path="/remote-settings" element={<RemoteSettingsPage />} />
      <Route path="/batch-settings" element={<BatchSettingsPage />} />
      <Route path="/operation-logs" element={<OperationLogsPage />} />
      <Route path="/devices/:sn/detail" element={<DeviceDetailPage />} />
      <Route path="/system/pipeline-health" element={<PipelineHealthPage />} />
    </Route>
  </Routes>
)

const MemoryRouterWrapper: React.FC<{ history: History; children: React.ReactNode }> = ({ history, children }) => {
  const [location, setLocation] = useState(history.location)
  useEffect(() => {
    return history.listen(({ location: loc }) => setLocation(loc))
  }, [history])
  return (
    <Router location={location} navigator={history}>
      {children}
    </Router>
  )
}

const App: React.FC<{ history?: History }> = ({ history }) => {
  const lang = useLocaleStore((s) => s.lang)
  const fetchTimezone = useTimezoneStore((s) => s.fetchTimezone)

  useEffect(() => {
    fetchTimezone()
  }, [fetchTimezone])

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
        <ErrorBoundary>
          <Suspense fallback={<div style={{ minHeight: 240, display: 'grid', placeItems: 'center' }}><Spin size="large" /></div>}>
            {history ? (
              <MemoryRouterWrapper history={history}>
                <AppRoutes />
              </MemoryRouterWrapper>
            ) : (
              <BrowserRouter>
                <AppRoutes />
              </BrowserRouter>
            )}
          </Suspense>
        </ErrorBoundary>
      </AntApp>
    </ConfigProvider>
  )
}

export default App
