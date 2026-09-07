# Web 页面级权限路由设计

## 背景

管理后台当前由 `ProtectedRoute` 统一校验登录状态，`MainLayout` 再按权限过滤侧边菜单。用户仍可通过直接输入 URL 访问未显示的页面，直到页面请求被后端拒绝。这不会替代后端权限控制，但会造成错误的功能入口、无意义请求和不一致的无权限体验。

## 目标

- 登录用户访问受限页面时，在页面渲染和业务请求发生前校验权限。
- 系统管理员继续拥有所有页面访问权。
- 普通用户具备页面声明的任一允许权限时放行，否则跳转 `/unauthorized`。
- 保留现有 `ProtectedRoute` 作为登录态边界，后端继续作为最终授权边界。
- 为直接访问、管理员绕过和无权限拒绝提供回归测试。

## 非目标

- 不修改后端权限模型或接口。
- 不重构页面组件或后端权限模型；路由声明与菜单权限来源允许做必要收敛。
- 不改变登录恢复、Token 刷新和侧边菜单过滤逻辑。
- 不在本轮实现字段级、按钮级权限体系。

## 方案

新增 `routeAccess.ts` 作为普通页面权限映射的单一来源，并新增 `PermissionRoute` 组件接收 `permissions: string[]`：

1. 从 `authStore` 读取 `user` 与 `hasAnyPermission`。
2. `user.isSystemAdmin` 为真时直接渲染子组件。
3. 普通用户具备 `permissions` 中任一权限时渲染子组件。
4. 权限均不满足时使用 React Router 的 `Navigate` 跳转 `/unauthorized`，并通过 `replace` 避免返回键循环。

`App.tsx` 保持现有 URL 结构，将可测试的业务路由部分提取为 `AppRoutes`，并对业务页面的 `element` 增加权限包装。公开路由不变。根重定向改为按候选顺序选择用户第一个实际有权访问的页面；没有普通页面权限时先进入 `/organizations`，再由组织守卫异步判断是放行还是进入 `/unauthorized`。这样既不会把仅有告警或工单权限的用户固定送到 `/devices`，也不会误伤仅具备有效组织成员资格的用户。

### 路由权限映射

| 路由 | 允许权限 |
|---|---|
| `/dashboard` | `dashboard:view` |
| `/devices`、`/devices/:sn/detail`、`/remote-settings`、`/batch-settings` | `devices:view` |
| `/ota` | `ota:view` |
| `/alerts` | `alerts:view` |
| `/work-orders` | `work_orders:view` |
| `/users` | `users:view` |
| `/parallel` | `parallel:view` |
| `/stations`、`/stations/:id` | `stations:view` |
| `/models` | `models:view` |
| `/monitoring`、`/monitoring/:id` | `devices:view` |
| `/operation-logs`、`/system/system-monitor` | `admin:manage` |
| `/system/system-config` | `admin:manage` |
| `/big-screen` | `dashboard:view` |

`/organizations` 是例外：它按当前用户的组织成员角色与可见组织判断，而不是单一权限码。新增共享的 `useOrganizationAccess` 与专用 `OrganizationRoute`，显式区分 `loading`、`allowed`、`denied`：查询未完成时显示加载态且不挂载目标页；系统管理员或具有任一非 `customer` 组织角色时放行；纯 `customer`、无组织、无角色信息或查询失败时跳转 `/unauthorized`。`MainLayout` 复用同一状态决定是否展示组织菜单，并移除现有首次渲染后才执行的重定向 effect。旧 `/admin` 路径重定向到 `/organizations` 后也由专用守卫处理。

`MainLayout` 的普通业务菜单不再分成会遗漏页面的管理员/普通用户白名单，而以统一菜单清单配合 `routeAccess.ts` 权限映射过滤；系统管理员全部可见，普通用户仅显示实际拥有权限的入口。组织入口仍单独按组织访问状态过滤。OTA 使用 `ota:view`，操作日志、系统监控和系统配置使用 `admin:manage`。固件库权限与 OTA 页面访问权限不再混为一类。

根路由候选顺序与主要导航一致：Dashboard、Devices、Stations、Alerts、Work Orders、OTA、Models、Parallel、Users、Operation Logs、System Monitor、System Config，最后以 Organizations 作为异步组织资格兜底。系统管理员默认进入 Dashboard；普通用户选择第一个匹配权限的普通页面，没有匹配项则交给组织守卫判定。

`MainLayout` 始终渲染 `<Outlet />`，不再因侧栏菜单为空而用 `Empty` 替代路由出口。否则无权限直达请求无法挂载 `PermissionRoute`，而拥有未列入旧角色菜单的合法权限也无法显示目标页。空菜单提示由明确的无权限路由承担。

## 错误处理与安全边界

- 无权限统一进入现有 `/unauthorized` 页面，不在目标页面发起查询。
- 权限为空按无权限处理；不沿用菜单层的迁移期宽松回退。
- 前端守卫不是安全边界，后端 `RequirePermission` 必须保留。
- 未登录仍由外层 `ProtectedRoute` 跳转登录页。

## 测试

新增组件测试覆盖：

1. 普通用户具备任一允许权限时显示页面。
2. 普通用户无权限时跳转无权限页。
3. 系统管理员无须具体权限即可访问。
4. 空权限列表不会意外放行普通用户。
5. 根路由对仅有 `alerts:view` 或 `work_orders:view` 的用户进入其实际可访问页面。
6. 权限映射表覆盖所有受限路由，并固定 OTA、系统监控等易漂移权限码。
7. 组织查询加载时不提前拒绝；有效组织成员且普通权限为空时进入组织页；无组织且权限为空时进入无权限页。
8. 使用真实 `AppRoutes` 与 `MainLayout` 覆盖 `/users`、`/big-screen`、设备详情、`/organizations`、`/admin` 和未登录认证优先级，证明守卫实际接入而不只是组件单测通过。

路由层使用表驱动测试覆盖全部权限映射，并额外覆盖 `/organizations` 例外、旧 `/admin` 重定向、两个全屏路由和未登录时认证守卫优先级。

## 验收标准

- TypeScript 编译通过。
- `src` 范围 ESLint 无新增错误。
- 权限组件和路由行为测试通过；如果 Vitest 仍被本机 Rolldown 绑定阻塞，必须明确标记为部分验证。
- 访问无权限页面时不渲染目标页面，并落到 `/unauthorized`。
