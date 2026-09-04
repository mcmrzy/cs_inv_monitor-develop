import { Spin } from 'antd'
import { Navigate } from 'react-router-dom'
import type { ReactNode } from 'react'
import useOrganizationAccess from '@/hooks/useOrganizationAccess'

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
  const { status } = useOrganizationAccess()

  if (status === 'loading') {
    return (
      <div style={loadingStyle} aria-label="Loading organization access">
        <Spin size="large" />
      </div>
    )
  }

  if (status === 'denied') return <Navigate to="/unauthorized" replace />

  return <>{children}</>
}
