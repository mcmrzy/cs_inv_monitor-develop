export const ROUTE_PERMISSIONS = {
  '/dashboard': ['dashboard:view'],
  '/big-screen': ['dashboard:view'],
  '/devices': ['devices:view'],
  '/devices/:sn/detail': ['devices:view'],
  '/monitoring': ['devices:view'],
  '/monitoring/:id': ['devices:view'],
  '/remote-settings': ['devices:view'],
  '/batch-settings': ['devices:view'],
  '/ota': ['ota:view'],
  '/alerts': ['alerts:view'],
  '/work-orders': ['work_orders:view'],
  '/users': ['users:view'],
  '/parallel': ['parallel:view'],
  '/stations': ['stations:view'],
  '/stations/:id': ['stations:view'],
  '/models': ['models:view'],
  '/operation-logs': ['admin:manage'],
  '/system/system-monitor': ['admin:manage'],
  '/system/system-config': ['admin:manage'],
} as const satisfies Record<string, readonly string[]>

export type PermissionRoutePath = keyof typeof ROUTE_PERMISSIONS

const EMPTY_PERMISSIONS: readonly string[] = []

export function getRoutePermissions(path: string): readonly string[] {
  return ROUTE_PERMISSIONS[path as PermissionRoutePath] ?? EMPTY_PERMISSIONS
}

export const DEFAULT_ROUTE_CANDIDATES = [
  '/dashboard',
  '/devices',
  '/stations',
  '/alerts',
  '/work-orders',
  '/ota',
  '/models',
  '/parallel',
  '/users',
  '/operation-logs',
  '/system/system-monitor',
  '/system/system-config',
] as const satisfies readonly PermissionRoutePath[]

type HasAnyPermission = (...permissions: string[]) => boolean

export function selectDefaultRoute(
  isSystemAdmin: boolean,
  hasAnyPermission: HasAnyPermission,
): PermissionRoutePath | '/organizations' {
  if (isSystemAdmin) return '/dashboard'

  for (const path of DEFAULT_ROUTE_CANDIDATES) {
    if (hasAnyPermission(...getRoutePermissions(path))) return path
  }

  return '/organizations'
}
