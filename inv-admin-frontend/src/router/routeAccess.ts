export const ROUTE_PERMISSIONS = {
  '/dashboard': ['dashboard:view'],
  '/big-screen': ['dashboard:view'],
  '/devices': ['devices:view'],
  '/devices/:sn/detail': ['devices:view'],
  '/monitoring': ['devices:view'],
  '/monitoring/:id': ['devices:view'],
  '/remote-settings': ['devices:view'],
  '/batch-settings': ['devices:view'],
  // /ota 基础访问：设备列表/固件概览依赖 devices:view
  '/ota': ['devices:view'],
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

/* ==================== OTA Tab 权限 ==================== */

/** OTA 页面五个 Tab */
export const OTA_TABS = [
  'deviceFirmware',
  'firmware',
  'tasks',
  'history',
  'appVersion',
] as const

export type OtaTabKey = (typeof OTA_TABS)[number]

/**
 * Tab 级权限：
 * - deviceFirmware：仅需进入 /ota 的 devices:view
 * - 管理类 Tab（固件/任务/历史/App）：需要 ota:view
 */
export const OTA_TAB_PERMISSIONS: Record<OtaTabKey, readonly string[]> = {
  deviceFirmware: [],
  firmware: ['ota:view'],
  tasks: ['ota:view'],
  history: ['ota:view'],
  appVersion: ['ota:view'],
}

/** OTA 写操作权限码 */
export const OTA_MUTATION_PERMISSIONS = {
  create: ['ota:create'],
  control: ['ota:control'],
  delete: ['ota:delete'],
} as const

export type OtaMutationAction = keyof typeof OTA_MUTATION_PERMISSIONS

/** 判断用户是否可访问指定 OTA Tab */
export function canAccessOtaTab(
  tab: OtaTabKey,
  isSystemAdmin: boolean,
  hasAnyPermission: HasAnyPermission,
): boolean {
  const perms = OTA_TAB_PERMISSIONS[tab] ?? EMPTY_PERMISSIONS
  if (perms.length === 0) return true
  if (isSystemAdmin) return true
  return hasAnyPermission(...perms)
}

/**
 * 解析深链 Tab：无权或非法 Tab 自动回落「设备固件升级」。
 */
export function resolveOtaTab(
  requested: string | null | undefined,
  isSystemAdmin: boolean,
  hasAnyPermission: HasAnyPermission,
): OtaTabKey {
  const candidate = String(requested ?? '').trim() as OtaTabKey
  if (
    (OTA_TABS as readonly string[]).includes(candidate)
    && canAccessOtaTab(candidate, isSystemAdmin, hasAnyPermission)
  ) {
    return candidate
  }
  return 'deviceFirmware'
}

/** 判断是否具备 OTA 写操作权限 */
export function canMutateOta(
  action: OtaMutationAction,
  isSystemAdmin: boolean,
  hasAnyPermission: HasAnyPermission,
): boolean {
  if (isSystemAdmin) return true
  return hasAnyPermission(...OTA_MUTATION_PERMISSIONS[action])
}
