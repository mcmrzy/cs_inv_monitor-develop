import { describe, expect, it, vi } from 'vitest'
import { DEFAULT_ROUTE_CANDIDATES, getRoutePermissions, selectDefaultRoute } from './routeAccess'

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
    ['/ota', ['ota:view']],
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
