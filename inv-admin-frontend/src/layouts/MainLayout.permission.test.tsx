import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { Route, Routes } from 'react-router-dom'
import { renderWithProviders, screen, waitFor } from '@/test/test-utils'
import { mockManagerUser } from '@/test/mocks/data'
import useAuthStore from '@/stores/authStore'
import { channelApi } from '@/services/channelApi'
import PermissionRoute from '@/components/PermissionRoute'
import MainLayout from './MainLayout'

function renderLayout(path: string, permissions: string[]) {
  return renderWithProviders(
    <Routes>
      <Route element={<MainLayout />}>
        <Route
          path="/users"
          element={
            <PermissionRoute permissions={['users:view']}>
              <div>Users content</div>
            </PermissionRoute>
          }
        />
        <Route path="/models" element={<div>Models content</div>} />
      </Route>
      <Route path="/unauthorized" element={<div>Unauthorized content</div>} />
    </Routes>,
    {
      routerProps: { initialEntries: [path] },
      initialUser: mockManagerUser,
      initialToken: 'layout-token',
      initialPermissions: permissions,
    },
  )
}

describe('MainLayout permission-aware outlet', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
    vi.spyOn(channelApi, 'getMyOrganizations').mockResolvedValue({
      data: { code: 0, data: [] },
    } as never)
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('keeps rendering the outlet when the filtered menu is empty', async () => {
    renderLayout('/users', [])

    await waitFor(() => expect(screen.getByText('Unauthorized content')).toBeInTheDocument())
    expect(screen.queryByText('Users content')).not.toBeInTheDocument()
  })

  it('shows the models menu when models:view is granted', async () => {
    renderLayout('/models', ['models:view'])

    await waitFor(() => expect(screen.getByText('型号管理')).toBeInTheDocument())
    expect(screen.getByText('Models content')).toBeInTheDocument()
  })
})
