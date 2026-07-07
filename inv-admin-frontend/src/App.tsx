import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useEffect } from 'react'
import { ConfigProvider, App as AntApp } from 'antd'
import zhCN from 'antd/locale/zh_CN'
import enUS from 'antd/locale/en_US'
import MainLayout from '@/layouts/MainLayout'
import ProtectedRoute from '@/components/ProtectedRoute'
import ErrorBoundary from '@/components/ErrorBoundary'
import LoginPage from '@/pages/login'
import UnauthorizedPage from '@/pages/unauthorized'
import DashboardPage from '@/pages/dashboard'
import DevicesPage from '@/pages/devices'
import OtaPage from '@/pages/ota'
import AlertsPage from '@/pages/alerts'

import UsersPage from '@/pages/users'
import AdminPage from '@/pages/admin'
import WorkOrdersPage from '@/pages/work-orders'
import BigScreenPage from '@/pages/big-screen'
import ParallelPage from '@/pages/parallel'

import StationsPage from '@/pages/stations'
import ModelsPage from '@/pages/models'
import MonitoringPage from '@/pages/monitoring'
import RemoteSettingsPage from '@/pages/remote-settings'
import BatchSettingsPage from '@/pages/batch-settings'
import OperationLogsPage from '@/pages/operation-logs'
import useAuthStore from '@/stores/authStore'
import useLocaleStore from '@/stores/localeStore'
import useTimezoneStore from '@/stores/timezoneStore'
import { Role } from '@/types'

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

const App: React.FC = () => {
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
          colorPrimary: '#4f6ef7',
          colorSuccess: '#22c55e',
          colorWarning: '#f59e0b',
          colorError: '#ef4444',
          colorInfo: '#4f6ef7',
          borderRadius: 10,
          fontFamily: "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'PingFang SC', 'Microsoft YaHei', sans-serif",
          fontSize: 14,
          colorBgLayout: '#f5f7fa',
          colorBgContainer: '#ffffff',
          boxShadow: '0 1px 3px rgba(0,0,0,0.06), 0 1px 2px rgba(0,0,0,0.04)',
          boxShadowSecondary: '0 4px 12px rgba(0,0,0,0.08)',
        },
        components: {
          Button: {
            controlHeight: 40,
            fontWeight: 500,
          },
          Card: {
            paddingLG: 24,
          },
          Table: {
            headerBg: '#f8fafc',
            headerColor: '#475569',
            rowHoverBg: '#f1f5f9',
          },
          Menu: {
            itemBorderRadius: 8,
            subMenuItemBorderRadius: 8,
            itemMarginInline: 8,
            itemHeight: 42,
            iconSize: 16,
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
          <BrowserRouter>
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
              <Route path="/models" element={<ModelsPage />} />
              <Route path="/monitoring" element={<MonitoringPage />} />
              <Route path="/remote-settings" element={<RemoteSettingsPage />} />
              <Route path="/batch-settings" element={<BatchSettingsPage />} />
              <Route path="/operation-logs" element={<OperationLogsPage />} />
            </Route>
          </Routes>
        </BrowserRouter>
        </ErrorBoundary>
      </AntApp>
    </ConfigProvider>
  )
}

export default App
