import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { ConfigProvider, App as AntApp } from 'antd'
import zhCN from 'antd/locale/zh_CN'
import MainLayout from '@/layouts/MainLayout'
import ProtectedRoute from '@/components/ProtectedRoute'
import ErrorBoundary from '@/components/ErrorBoundary'
import LoginPage from '@/pages/login'
import UnauthorizedPage from '@/pages/unauthorized'
import DashboardPage from '@/pages/dashboard'
import DevicesPage from '@/pages/devices'
import OtaPage from '@/pages/ota'
import AlertsPage from '@/pages/alerts'
import AlertRulesPage from '@/pages/alert-rules'
import UsersPage from '@/pages/users'
import AdminPage from '@/pages/admin'
import WorkOrdersPage from '@/pages/work-orders'
import BigScreenPage from '@/pages/big-screen'
import ParallelPage from '@/pages/parallel'
import PortalOverview from '@/pages/portal/OverviewPage'
import PortalDevices from '@/pages/portal/DeviceMonitorPage'
import PortalAlerts from '@/pages/portal/AlertsPage'
import StationsPage from '@/pages/stations'
import useAuthStore from '@/stores/authStore'
import { Role } from '@/types'

const RoleRedirect: React.FC = () => {
  const user = useAuthStore((s) => s.user)
  if (user && (user.role === Role.SUPER_ADMIN || user.role === Role.AGENT)) {
    return <Navigate to="/dashboard" replace />
  }
  return <Navigate to="/portal" replace />
}

const App: React.FC = () => {
  return (
    <ConfigProvider
      locale={zhCN}
      theme={{
        token: {
          colorPrimary: '#1677ff',
          borderRadius: 6,
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
              <Route path="/alert-rules" element={<AlertRulesPage />} />
              <Route path="/work-orders" element={<WorkOrdersPage />} />
              <Route path="/users" element={<UsersPage />} />
              <Route path="/admin" element={<AdminPage />} />
              <Route path="/parallel" element={<ParallelPage />} />
              <Route path="/portal" element={<PortalOverview />} />
              <Route path="/portal/devices" element={<PortalDevices />} />
              <Route path="/portal/alerts" element={<PortalAlerts />} />
              <Route path="/stations" element={<StationsPage />} />
            </Route>
          </Routes>
        </BrowserRouter>
        </ErrorBoundary>
      </AntApp>
    </ConfigProvider>
  )
}

export default App
