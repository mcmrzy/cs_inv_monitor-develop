import { Result, Button, Space } from 'antd'
import { useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'
import useOrganizationAccess from '@/hooks/useOrganizationAccess'
import { selectDefaultRoute } from '@/router/routeAccess'

const UnauthorizedPage: React.FC = () => {
  const navigate = useNavigate()
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const user = useAuthStore((state) => state.user)
  const hasAnyPermission = useAuthStore((state) => state.hasAnyPermission)
  const logout = useAuthStore((state) => state.logout)
  const { status: organizationStatus } = useOrganizationAccess()

  const isSystemAdmin = user?.isSystemAdmin === true
  const defaultRoute = selectDefaultRoute(isSystemAdmin, hasAnyPermission)

  // selectDefaultRoute 只在“没有任何权限路由”时返回 /organizations，而该页面还要求
  // 组织访问放行。这种情况下再给“返回首页”只会被守卫弹回本页，形成死循环，因此改为
  // 提供退出登录作为出口。同样地，直接用 /dashboard 做兜底也会对只有 devices:view
  // 之类权限的用户造成回环，所以落到用户自己的默认路由上。
  const canGoHome = isSystemAdmin
    || defaultRoute !== '/organizations'
    || organizationStatus === 'allowed'

  const handleLogout = () => {
    logout()
    queryClient.clear()
    navigate('/login', { replace: true })
  }

  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: '#f0f2f5',
      }}
    >
      <Result
        status="403"
        title="403"
        subTitle={canGoHome ? t('unauthorized.title') : t('unauthorized.noAccessDesc')}
        extra={
          <Space>
            {canGoHome && (
              <Button type="primary" onClick={() => navigate(defaultRoute, { replace: true })}>
                {t('unauthorized.backHome')}
              </Button>
            )}
            <Button onClick={handleLogout}>{t('unauthorized.logout')}</Button>
          </Space>
        }
      />
    </div>
  )
}

export default UnauthorizedPage
