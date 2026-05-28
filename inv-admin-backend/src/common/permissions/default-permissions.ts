export const ALL_PERMISSIONS = [
  { resource: 'devices', action: 'view', description: '查看设备列表' },
  { resource: 'devices', action: 'create', description: '创建设备/导入Excel' },
  { resource: 'devices', action: 'edit', description: '编辑设备信息' },
  { resource: 'devices', action: 'delete', description: '删除设备' },
  { resource: 'devices', action: 'export', description: '导出设备数据' },
  { resource: 'devices', action: 'control', description: '远程控制设备' },
  { resource: 'devices', action: 'manage', description: '解绑/审批/生命周期管理' },

  { resource: 'users', action: 'view', description: '查看用户列表' },
  { resource: 'users', action: 'create', description: '创建下级用户' },
  { resource: 'users', action: 'edit', description: '编辑用户信息' },
  { resource: 'users', action: 'delete', description: '删除/禁用用户' },
  { resource: 'users', action: 'manage', description: '重置密码/角色变更' },

  { resource: 'alerts', action: 'view', description: '查看告警列表' },
  { resource: 'alerts', action: 'manage', description: '确认/忽略告警' },
  { resource: 'alert_rules', action: 'view', description: '查看告警规则' },
  { resource: 'alert_rules', action: 'create', description: '创建告警规则' },
  { resource: 'alert_rules', action: 'edit', description: '编辑告警规则' },
  { resource: 'alert_rules', action: 'delete', description: '删除告警规则' },

  { resource: 'work_orders', action: 'view', description: '查看工单列表' },
  { resource: 'work_orders', action: 'create', description: '创建工单' },
  { resource: 'work_orders', action: 'edit', description: '编辑/指派工单' },
  { resource: 'work_orders', action: 'manage', description: 'SLA管理/升级工单' },

  { resource: 'firmware', action: 'view', description: '查看固件列表' },
  { resource: 'firmware', action: 'create', description: '上传固件' },
  { resource: 'firmware', action: 'delete', description: '删除固件' },
  { resource: 'ota', action: 'view', description: '查看OTA任务' },
  { resource: 'ota', action: 'create', description: '创建OTA任务' },
  { resource: 'ota', action: 'control', description: '执行/取消/回滚OTA任务' },

  { resource: 'dashboard', action: 'view', description: '查看仪表盘' },
  { resource: 'dashboard', action: 'export', description: '多设备对比/导出' },

  { resource: 'stations', action: 'view', description: '查看电站列表' },
  { resource: 'stations', action: 'create', description: '创建电站' },
  { resource: 'stations', action: 'edit', description: '编辑电站' },

  { resource: 'parallel', action: 'view', description: '查看并机配置' },
  { resource: 'parallel', action: 'create', description: '创建并机配置' },
  { resource: 'parallel', action: 'control', description: '同步参数/管理并机' },

  { resource: 'audit', action: 'view', description: '查看审计日志' },
  { resource: 'admin', action: 'view', description: '查看系统健康' },
  { resource: 'admin', action: 'manage', description: '租户管理/系统配置' },
];

export const DEFAULT_ROLE_PERMISSIONS: Record<number, { resource: string; action: string }[]> = {
  0: ALL_PERMISSIONS.map(p => ({ resource: p.resource, action: p.action })),

  1: ALL_PERMISSIONS
    .filter(p => !['admin', 'audit'].includes(p.resource) || p.action !== 'manage')
    .map(p => ({ resource: p.resource, action: p.action })),

  2: [
    { resource: 'devices', action: 'view' },
    { resource: 'devices', action: 'edit' },
    { resource: 'devices', action: 'create' },
    { resource: 'devices', action: 'control' },
    { resource: 'devices', action: 'export' },
    { resource: 'alerts', action: 'view' },
    { resource: 'alerts', action: 'manage' },
    { resource: 'work_orders', action: 'view' },
    { resource: 'work_orders', action: 'create' },
    { resource: 'work_orders', action: 'edit' },
    { resource: 'stations', action: 'view' },
    { resource: 'stations', action: 'create' },
    { resource: 'dashboard', action: 'view' },
    { resource: 'users', action: 'view' },
    { resource: 'users', action: 'create' },
  ],

  3: [
    { resource: 'devices', action: 'view' },
    { resource: 'alerts', action: 'view' },
    { resource: 'dashboard', action: 'view' },
    { resource: 'stations', action: 'view' },
  ],
};

export const RESOURCE_LABELS: Record<string, string> = {
  devices: '设备管理',
  users: '用户管理',
  alerts: '告警管理',
  alert_rules: '告警规则',
  work_orders: '工单管理',
  firmware: '固件管理',
  ota: 'OTA升级',
  dashboard: '仪表盘',
  stations: '电站管理',
  parallel: '并机管理',
  audit: '审计日志',
  admin: '系统管理',
};

export const RESOURCE_ORDER = [
  'devices',
  'users',
  'alerts',
  'alert_rules',
  'work_orders',
  'firmware',
  'ota',
  'dashboard',
  'stations',
  'parallel',
  'audit',
  'admin',
];
