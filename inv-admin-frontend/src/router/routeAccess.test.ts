import { describe, expect, it, vi } from 'vitest'
import {
  DEFAULT_ROUTE_CANDIDATES,
  getRoutePermissions,
  selectDefaultRoute,
  canAccessOtaTab,
  resolveOtaTab,
  canMutateOta,
  OTA_TABS,
  OTA_TAB_PERMISSIONS,
  OTA_MUTATION_PERMISSIONS,
} from './routeAccess'

describe('getRoutePermissions', () => {
  it.each([
    ['/dashboard', ['dashboard:view']],
    ['/big-screen', ['dashboard:view']],
    ['/devices', ['devices:view']],
    ['/devices/:sn/detail', ['devices:view']],
    ['/monitoring', ['devices:view']],
    ['/monitoring/:id', ['devices:view']],
    ['/remote-settings', ['devices:view']],
    ['/batch-settings', ['devices:view']],
    ['/ota', ['devices:view']],
    ['/alerts', ['alerts:view']],
    ['/work-orders', ['work_orders:view']],
    ['/users', ['users:view']],
    ['/parallel', ['parallel:view']],
    ['/stations', ['stations:view']],
    ['/stations/:id', ['stations:view']],
    ['/models', ['models:view']],
    ['/operation-logs', ['admin:manage']],
    ['/system/system-monitor', ['admin:manage']],
    ['/system/system-config', ['admin:manage']],
  ])('maps %s to its backend permission', (path, expected) => {
    expect(getRoutePermissions(path)).toEqual(expected)
  })

  it('does not treat organization membership as an ordinary permission route', () => {
    expect(getRoutePermissions('/organizations')).toEqual([])
  })

  it('returns an empty list for an unknown route', () => {
    expect(getRoutePermissions('/unknown')).toEqual([])
  })
})

describe('selectDefaultRoute', () => {
  it('keeps the complete product navigation order for default-route selection', () => {
    expect(DEFAULT_ROUTE_CANDIDATES).toEqual([
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
    ])
  })

  it('always sends a system administrator to the dashboard', () => {
    const hasAnyPermission = vi.fn(() => false)

    expect(selectDefaultRoute(true, hasAnyPermission)).toBe('/dashboard')
    expect(hasAnyPermission).not.toHaveBeenCalled()
  })

  it('chooses the first permitted route in product navigation order', () => {
    const allowed = new Set(['ota:view', 'alerts:view'])

    expect(selectDefaultRoute(false, (...permissions) => permissions.some((p) => allowed.has(p)))).toBe(
      '/alerts',
    )
  })

  it('allows /ota access with devices:view alone', () => {
    const allowed = new Set(['devices:view'])

    expect(selectDefaultRoute(false, (...permissions) => permissions.some((p) => allowed.has(p)))).toBe(
      '/devices',
    )
  })

  it('checks administrative pages after ordinary business pages', () => {
    const allowed = new Set(['admin:manage'])

    expect(selectDefaultRoute(false, (...permissions) => permissions.some((p) => allowed.has(p)))).toBe(
      '/operation-logs',
    )
  })

  it('falls back to organization access when no ordinary route is permitted', () => {
    expect(selectDefaultRoute(false, () => false)).toBe('/organizations')
  })
})

describe('OTA tab access', () => {
  it('exposes five tabs in product order', () => {
    expect(OTA_TABS).toEqual(['deviceFirmware', 'firmware', 'tasks', 'history', 'appVersion'])
  })

  it('requires ota:view for management tabs and no extra perm for device tab', () => {
    expect(OTA_TAB_PERMISSIONS.deviceFirmware).toEqual([])
    expect(OTA_TAB_PERMISSIONS.firmware).toEqual(['ota:view'])
    expect(OTA_TAB_PERMISSIONS.tasks).toEqual(['ota:view'])
    expect(OTA_TAB_PERMISSIONS.history).toEqual(['ota:view'])
    expect(OTA_TAB_PERMISSIONS.appVersion).toEqual(['ota:view'])
  })

  it('canAccessOtaTab allows device tab with only devices:view', () => {
    const hasAnyPermission = (...perms: string[]) => perms.some((p) => p === 'devices:view')

    expect(canAccessOtaTab('deviceFirmware', false, hasAnyPermission)).toBe(true)
    expect(canAccessOtaTab('firmware', false, hasAnyPermission)).toBe(false)
  })

  it('canAccessOtaTab allows management tabs with ota:view', () => {
    const hasAnyPermission = (...perms: string[]) => perms.includes('ota:view')

    expect(canAccessOtaTab('firmware', false, hasAnyPermission)).toBe(true)
    expect(canAccessOtaTab('tasks', false, hasAnyPermission)).toBe(true)
  })

  it('system admin can access every tab', () => {
    expect(canAccessOtaTab('firmware', true, () => false)).toBe(true)
    expect(canAccessOtaTab('appVersion', true, () => false)).toBe(true)
  })

  it('resolveOtaTab falls back to deviceFirmware for unauthorized deep link', () => {
    const hasOnlyDevices = (...perms: string[]) => perms.includes('devices:view')

    expect(resolveOtaTab('firmware', false, hasOnlyDevices)).toBe('deviceFirmware')
    expect(resolveOtaTab('deviceFirmware', false, hasOnlyDevices)).toBe('deviceFirmware')
  })

  it('resolveOtaTab keeps authorized deep link', () => {
    const hasOta = (...perms: string[]) => perms.includes('ota:view')

    expect(resolveOtaTab('history', false, hasOta)).toBe('history')
    expect(resolveOtaTab('appVersion', false, hasOta)).toBe('appVersion')
  })

  it('resolveOtaTab rejects unknown tab keys', () => {
    expect(resolveOtaTab('packages', true, () => false)).toBe('deviceFirmware')
    expect(resolveOtaTab(null, true, () => false)).toBe('deviceFirmware')
    expect(resolveOtaTab('', true, () => false)).toBe('deviceFirmware')
  })
})

describe('OTA mutation permissions', () => {
  it('maps create/control/delete to dedicated codes', () => {
    expect(OTA_MUTATION_PERMISSIONS.create).toEqual(['ota:create'])
    expect(OTA_MUTATION_PERMISSIONS.control).toEqual(['ota:control'])
    expect(OTA_MUTATION_PERMISSIONS.delete).toEqual(['ota:delete'])
  })

  it('canMutateOta checks the matching permission code', () => {
    const has = (...perms: string[]) => perms.includes('ota:control')

    expect(canMutateOta('control', false, has)).toBe(true)
    expect(canMutateOta('create', false, has)).toBe(false)
    expect(canMutateOta('delete', false, has)).toBe(false)
    expect(canMutateOta('create', true, () => false)).toBe(true)
  })
})
