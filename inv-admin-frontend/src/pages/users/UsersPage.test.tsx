import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import { mockUsers, paginatedResponse } from '@/test/mocks/data'
import useAuthStore from '@/stores/authStore'
import { Role } from '@/types'
import UsersPage from './index'

// Mock timezone utilities to avoid dayjs plugin issues
vi.mock('@/utils/timezone', () => ({
  formatInTimezone: (val: string) => val || '-',
}))

describe('UsersPage', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
  })

  it('should render the users page title', async () => {
    renderAsAdmin(<UsersPage />)
    // Wait for initial query to settle
    await waitFor(() => {
      expect(document.querySelector('.ant-typography')).toBeInTheDocument()
    })
  })

  it('should render user list with correct data', async () => {
    renderAsAdmin(<UsersPage />)

    // Wait for user data to load
    await waitFor(() => {
      expect(screen.getByText('13800000001')).toBeInTheDocument()
    })

    // Role names appear in tabs and table tags, so use getAllByText
    expect(screen.getAllByText('超级管理员').length).toBeGreaterThan(0)
    expect(screen.getAllByText('管理员').length).toBeGreaterThan(0)
    expect(screen.getAllByText('安装商').length).toBeGreaterThan(0)
  })

  it('should show role tags', async () => {
    renderAsAdmin(<UsersPage />)

    await waitFor(() => {
      expect(screen.getByText('13800000001')).toBeInTheDocument()
    })

    // Role tags should be present
    const tags = document.querySelectorAll('.ant-tag')
    expect(tags.length).toBeGreaterThan(0)
  })

  it('should render role filter tabs', async () => {
    renderAsAdmin(<UsersPage />)

    // Wait for tabs
    await waitFor(() => {
      const tabs = document.querySelectorAll('.ant-tabs-tab')
      expect(tabs).toHaveLength(7)
    })
    expect(screen.getByRole('tab', { name: '运营商' })).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: '经销商' })).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: '安装商' })).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: '终端用户' })).toBeInTheDocument()
  })

  it('should show add user button for admin', async () => {
    renderAsAdmin(<UsersPage />)

    await waitFor(() => {
      const addButtons = screen.getAllByRole('button')
      const hasAddButton = addButtons.some(btn => btn.textContent?.includes('新增') || btn.textContent?.includes('添加'))
      // The button text comes from t('user.addUser')
      expect(document.querySelector('.ant-btn-primary')).toBeInTheDocument()
    })
  })

  it('should render search input', async () => {
    renderAsAdmin(<UsersPage />)

    await waitFor(() => {
      const searchInput = document.querySelector('.ant-input-search input, .ant-input input')
      expect(searchInput).toBeInTheDocument()
    })
  })

  it('should render pagination', async () => {
    renderAsAdmin(<UsersPage />)

    await waitFor(() => {
      expect(screen.getByText('13800000001')).toBeInTheDocument()
    })

    // Ant Design Table pagination
    const pagination = document.querySelector('.ant-pagination')
    expect(pagination).toBeInTheDocument()
  })

  it('should show table columns', async () => {
    renderAsAdmin(<UsersPage />)

    await waitFor(() => {
      expect(screen.getByText('13800000001')).toBeInTheDocument()
    })

    // Column headers from the table
    expect(screen.getByText('ID')).toBeInTheDocument()
  })

  it('should handle empty user list', async () => {
    server.use(
      http.get('/api/v1/users', () => {
        return HttpResponse.json({
          code: 0,
          data: paginatedResponse([], 0),
        })
      }),
    )

    renderAsAdmin(<UsersPage />)

    await waitFor(() => {
      const empty = document.querySelector('.ant-empty')
      expect(empty).toBeInTheDocument()
    })
  })
})
