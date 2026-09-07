import { beforeEach, describe, expect, it } from 'vitest'
import { Route, Routes } from 'react-router-dom'
import { renderWithProviders, screen } from '@/test/test-utils'
import { mockAdminUser, mockManagerUser } from '@/test/mocks/data'
import useAuthStore from '@/stores/authStore'
import PermissionRoute from './PermissionRoute'

function renderPermissionRoute(permissions: readonly string[]) {
  return renderWithProviders(
    <Routes>
      <Route
        path="/protected"
        element={
          <PermissionRoute permissions={permissions}>
            <div>Protected content</div>
          </PermissionRoute>
        }
      />
      <Route path="/unauthorized" element={<div>Unauthorized page</div>} />
    </Routes>,
    { routerProps: { initialEntries: ['/protected'] } },
  )
}

describe('PermissionRoute', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
  })

  it('renders children when a normal user has any declared permission', () => {
    useAuthStore.getState().login('token', 'refresh', mockManagerUser, ['devices:view'])

    renderPermissionRoute(['dashboard:view', 'devices:view'])

    expect(screen.getByText('Protected content')).toBeInTheDocument()
  })

  it('redirects a normal user without a declared permission', () => {
    useAuthStore.getState().login('token', 'refresh', mockManagerUser, ['alerts:view'])

    renderPermissionRoute(['devices:view'])

    expect(screen.getByText('Unauthorized page')).toBeInTheDocument()
    expect(screen.queryByText('Protected content')).not.toBeInTheDocument()
  })

  it('lets a system administrator bypass declared permissions', () => {
    useAuthStore.getState().login('token', 'refresh', mockAdminUser, [])

    renderPermissionRoute(['admin:manage'])

    expect(screen.getByText('Protected content')).toBeInTheDocument()
  })

  it('redirects a normal user when no permission is declared', () => {
    useAuthStore.getState().login('token', 'refresh', mockManagerUser, ['devices:view'])

    renderPermissionRoute([])

    expect(screen.getByText('Unauthorized page')).toBeInTheDocument()
  })
})
