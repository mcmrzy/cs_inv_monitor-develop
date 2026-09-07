import { Navigate } from 'react-router-dom'
import useAuthStore from '@/stores/authStore'

interface PermissionRouteProps {
  children: React.ReactNode
  permissions: readonly string[]
}

const PermissionRoute: React.FC<PermissionRouteProps> = ({ children, permissions }) => {
  const isSystemAdmin = useAuthStore((state) => state.user?.isSystemAdmin === true)
  const hasAnyPermission = useAuthStore((state) => state.hasAnyPermission)

  const isAllowed = isSystemAdmin || (permissions.length > 0 && hasAnyPermission(...permissions))

  if (!isAllowed) {
    return <Navigate to="/unauthorized" replace />
  }

  return <>{children}</>
}

export default PermissionRoute
