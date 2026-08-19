# 不同角色用户菜单权限验证文档

## 菜单路由配置

### Admin Routes (系统管理员)
- dashboard
- stationMonitor
- stationManage
- deviceManage
- modelManage
- parallelManage
- remoteSettings
- batchSettings
- ota
- alertCenter
- workOrders
- organizations (组织架构)
- userManage
- operationLogs
- systemMonitor
- systemConfig

### User Routes (普通用户)
- dashboard
- stationMonitor
- stationManage
- deviceManage
- remoteSettings
- alertCenter
- workOrders
- organizations (组织架构 - 需要根据角色过滤)

## 角色识别逻辑

### 1. System Admin (系统管理员)
```typescript
const isAdminRole = user && (user.isSystemAdmin || hasPermission('admin:manage'))
```

特征:
- `user.isSystemAdmin = true`
- 或拥有 `admin:manage` 权限

### 2. End User (纯终端用户)
```typescript
const isEndUser = useMemo(() => {
  if (!user || user.isSystemAdmin) return false
  const orgs = myOrgsData ?? []
  if (!Array.isArray(orgs) || orgs.length === 0) return false
  
  const roleSet = new Set<string>()
  for (const org of orgs) {
    const roles = Array.isArray(org.roles) && org.roles.length > 0 
      ? org.roles 
      : org.role ? [org.role] : []
    roles.forEach((r) => roleSet.add(r))
  }
  return roleSet.size > 0 && [...roleSet].every((r) => r === 'customer')
}, [user, myOrgsData])
```

特征:
- 非系统管理员
- 至少有一个组织记录
- 所有组织角色都是 `customer`

### 3. Org Member (组织成员)
特征:
- 非系统管理员
- 有非 customer 的角色（如 agent, distributor, installer, org_admin 等）

### 4. No Organizations (无组织记录)
特征:
- 非系统管理员
- 没有任何组织记录或角色信息

## 组织架构访问权限

```typescript
const canAccessOrgManagement = useMemo(
  () => !userRoleStatus.includes('no_') && 
        (userRoleStatus === 'system_admin' || userRoleStatus === 'org_member'),
  [userRoleStatus],
)
```

### 判断规则
1. **系统管理员**: ✅ 可以访问
2. **组织成员 (非 customer)**: ✅ 可以访问
3. **纯终端用户 (仅 customer)**: ❌ 禁止访问
4. **无组织记录**: ❌ 禁止访问

### URL 保护机制
```typescript
useEffect(() => {
  if (location.pathname.startsWith('/organizations')) {
    if (isEndUser || userRoleStatus === 'no_organizations' || userRoleStatus === 'no_role_info') {
      navigate('/unauthorized', { replace: true })
    }
  }
}, [isEndUser, userRoleStatus, location.pathname, navigate])
```

即使直接访问 `/organizations` URL，也会被重定向到 `/unauthorized`。

## 常见问题排查

### Q1: 为什么普通用户看不到任何菜单？
A: 这是因为普通用户没有对应菜单项所需的权限（如 `devices:view`, `stations:view` 等）。
   检查步骤:
   1. 确认用户是否有组织记录和角色分配
   2. 检查角色是否映射了对应的权限码
   3. 查看浏览器开发者工具的 Network 标签，确认请求是否成功

### Q2: 为什么普通用户能看到组织架构但无法使用？
A: 这可能是前端渲染延迟导致的。刷新页面后应该会根据实时状态过滤。
   如果仍然有问题，检查 `canAccessOrgManagement` 的值是否正确计算。

### Q3: 如何测试不同角色的菜单显示？
A: 可以使用不同的测试账户登录：
1. 系统管理员账户 - 看到完整管理功能
2. 渠道成员账户（agent/distributor/installer）- 看到基础功能 + 组织架构
3. 终端用户账户（customer）- 只看到基础功能，隐藏组织架构

## API 修复说明

### getMyOrganizations() 兼容性处理

**修复前**:
```typescript
const { data: myOrgsData } = useQuery({
  queryFn: async () => {
    try {
      const r = await channelApi.getMyOrganizations()
      return Array.isArray(r.data?.data) ? r.data.data : []
    } catch {
      return []
    }
  },
  enabled: !!user && !user.isSystemAdmin,
  retry: false,
  staleTime: 60_000,
})
```

**修复后**:
```typescript
const { data: myOrgsData } = useQuery({
  queryKey: queryKeys.channels.myOrganizations(user?.id),
  queryFn: async () => {
    try {
      const r = await channelApi.getMyOrganizations()
      // 兼容性处理：后端可能返回 null、单对象或数组
      const d = r.data?.data
      if (Array.isArray(d)) return d
      if (d && typeof d === 'object') return [d] as any[] // 单个对象转为数组
      return []
    } catch {
      // 接口失败（如无组织记录时返回 null）→ 降级为空数组，不阻塞页面渲染
      return []
    }
  },
  enabled: !!user && !user.isSystemAdmin,
  retry: false,
  staleTime: 60_000,
})
```

这样可以兼容后端返回的各种格式：
- `[]` (空数组) - 正常返回
- `[object]` (包含一个对象的数组) - 正常返回
- `object` (单个对象) - 转为数组返回
- `null` / `undefined` - 返回空数组避免错误
