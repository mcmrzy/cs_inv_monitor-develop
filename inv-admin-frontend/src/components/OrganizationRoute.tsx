import { Button, Result, Spin } from 'antd'
import { Navigate } from 'react-router-dom'
import type { ReactNode } from 'react'
import useOrganizationAccess from '@/hooks/useOrganizationAccess'
import useTranslation from '@/hooks/useTranslation'

interface OrganizationRouteProps {
  children: ReactNode
}

const loadingStyle = {
  minHeight: '50vh',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
} as const

export default function OrganizationRoute({ children }: OrganizationRouteProps) {
  const { status, refetch } = useOrganizationAccess()
  const { t } = useTranslation()

  if (status === 'loading') {
    return (
      <div style={loadingStyle} aria-label="Loading organization access">
        <Spin size="large" />
      </div>
    )
  }

  if (status === 'denied') return <Navigate to="/unauthorized" replace />

  // 加载失败不能当成“无权限”，否则一次网络抖动就把用户丢进 403 页面。
  if (status === 'error') {
    return (
      <Result
        status="warning"
        title={t('unauthorized.loadFailedTitle')}
        subTitle={t('unauthorized.loadFailedDesc')}
        extra={<Button type="primary" onClick={refetch}>{t('common.retry')}</Button>}
      />
    )
  }

  return <>{children}</>
}
