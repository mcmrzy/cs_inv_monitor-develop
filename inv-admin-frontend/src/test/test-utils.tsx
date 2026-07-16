/**
 * 自定义测试渲染工具
 *
 * 提供 `renderWithProviders` 函数，自动包装测试组件所需的全局 Provider：
 * - `QueryClientProvider`（@tanstack/react-query）
 * - `MemoryRouter`（react-router-dom，支持自定义路由）
 * - `ConfigProvider`（antd 主题 & 国际化）
 *
 * @example
 * ```tsx
 * import { renderWithProviders, screen } from '@/test/test-utils'
 *
 * test('renders device name', () => {
 *   renderWithProviders(<DeviceCard device={mockDevice} />)
 *   expect(screen.getByText(mockDevice.sn)).toBeInTheDocument()
 * })
 * ```
 */

import { render, type RenderOptions, type RenderResult } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, type MemoryRouterProps } from 'react-router-dom'
import { ConfigProvider, App as AntApp } from 'antd'
import zhCN from 'antd/locale/zh_CN'
import type { ReactElement } from 'react'
import useAuthStore from '@/stores/authStore'
import useLocaleStore, { type Lang } from '@/stores/localeStore'
import type { User } from '@/types'
import { Role } from '@/types'

/** `renderWithProviders` 的可选参数 */
export interface RenderWithProvidersOptions extends Omit<RenderOptions, 'wrapper'> {
  /** 传给 MemoryRouter 的 props，例如 `initialEntries` */
  routerProps?: MemoryRouterProps
  /** 预配置的 QueryClient；若不传则自动创建测试专用实例 */
  queryClient?: QueryClient
  /** 初始认证用户；与 initialToken 同时提供时会在渲染前登录 */
  initialUser?: User | null
  /** 初始访问令牌；与 initialUser 同时提供时会在渲染前登录 */
  initialToken?: string | null
  /** 初始权限列表 */
  initialPermissions?: string[]
  /** 是否使用 MemoryRouter 包装组件；默认 true。渲染已包含 Router 的组件（如 App）时可设为 false */
  withRouter?: boolean
  /** 渲染语言；默认 'zh'。影响 useTranslation 返回的翻译文案 */
  lang?: Lang
}

/**
 * 创建测试专用的 QueryClient 实例
 *
 * 禁用重试和窗口焦点刷新，避免测试中出现不必要的异步行为。
 */
export function createTestQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
        refetchOnWindowFocus: false,
        staleTime: Infinity,
        gcTime: 0,
      },
      mutations: {
        retry: false,
      },
    },
  })
}

function setupAuth(options: RenderWithProvidersOptions) {
  // Default to Chinese locale for tests; override via options.lang
  useLocaleStore.setState({ lang: options.lang ?? 'zh' })

  const { initialUser, initialToken, initialPermissions = [] } = options
  if (initialUser && initialToken) {
    useAuthStore.getState().login(initialToken, 'mock-refresh-token', initialUser, initialPermissions)
  } else if (initialUser === null || initialToken === null) {
    // 显式传入 null 时才会登出；默认不触碰已有的认证状态，支持先登录再渲染
    useAuthStore.getState().logout()
  }
}

/**
 * 带全局 Provider 的组件渲染函数
 *
 * 替代直接使用 `@testing-library/react` 的 `render`，
 * 确保组件在测试环境中能正确访问 QueryClient、路由、Ant Design 主题等上下文。
 *
 * @param ui - 待渲染的 React 元素
 * @param options - 渲染选项
 * @returns `@testing-library/react` 的 `RenderResult`
 */
export function renderWithProviders(
  ui: ReactElement,
  options: RenderWithProvidersOptions = {},
): RenderResult {
  const {
    routerProps = { initialEntries: ['/'] },
    queryClient = createTestQueryClient(),
    withRouter = true,
    ...renderOptions
  } = options

  setupAuth(options)

  function Wrapper({ children }: { children: React.ReactNode }) {
    const inner = (
      <QueryClientProvider client={queryClient}>
        <ConfigProvider locale={zhCN}>
          <AntApp>{children}</AntApp>
        </ConfigProvider>
      </QueryClientProvider>
    )
    if (!withRouter) return inner
    return <MemoryRouter {...routerProps}>{inner}</MemoryRouter>
  }

  return render(ui, { wrapper: Wrapper, ...renderOptions })
}

/**
 * 以超级管理员身份渲染组件
 *
 * 预设：已登录的超级管理员用户 + 全部管理权限。
 */
export function renderAsAdmin(ui: ReactElement, options: Omit<RenderWithProvidersOptions, 'initialUser' | 'initialToken' | 'initialPermissions'> = {}): RenderResult {
  const adminUser: User = {
    id: '1',
    phone: '13800000001',
    email: 'admin@example.com',
    nickname: '超级管理员',
    avatar: '',
    role: Role.SUPER_ADMIN,
    status: 1,
    timezone: 'Asia/Shanghai',
    lastLoginAt: '2026-07-01T08:00:00Z',
    createdAt: '2025-01-01T00:00:00Z',
  }

  return renderWithProviders(ui, {
    ...options,
    initialUser: adminUser,
    initialToken: 'mock-jwt-token',
    initialPermissions: [
      'dashboard:view',
      'devices:view',
      'firmware:view',
      'alerts:view',
      'users:view',
      'admin:view',
      'stations:view',
      'models:view',
      'work_orders:view',
      'parallel:view',
    ],
  })
}

/**
 * 以指定用户身份渲染组件
 */
export function renderAsUser(
  ui: ReactElement,
  user: User,
  permissions: string[] = [],
  options: Omit<RenderWithProvidersOptions, 'initialUser' | 'initialToken' | 'initialPermissions'> = {},
): RenderResult {
  return renderWithProviders(ui, {
    ...options,
    initialUser: user,
    initialToken: 'mock-jwt-token',
    initialPermissions: permissions,
  })
}

/**
 * 从 `@testing-library/react` 重新导出常用工具，
 * 配合 `renderWithProviders` 使用，减少重复导入。
 */
export { screen, waitFor, within, act } from '@testing-library/react'
export { default as userEvent } from '@testing-library/user-event'
