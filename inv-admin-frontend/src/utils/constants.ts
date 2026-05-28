
export const ROLE_MAP: Record<string, string> = {
  0: '超级管理员',
  1: '代理商',
  2: '安装商',
  3: '终端用户',
}

export const DEVICE_STATUS_MAP: Record<string, { label: string; color: string }> = {
  0: { label: '离线', color: '#d9d9d9' },
  1: { label: '在线', color: '#52c41a' },
  2: { label: '故障', color: '#ff4d4f' },
  offline: { label: '离线', color: '#d9d9d9' },
  online: { label: '在线', color: '#52c41a' },
  fault: { label: '故障', color: '#ff4d4f' },
}

export const ALARM_LEVEL_MAP: Record<string, { label: string; color: string }> = {
  1: { label: '严重', color: '#ff4d4f' },
  2: { label: '警告', color: '#fa8c16' },
  3: { label: '提示', color: '#1677ff' },
  critical: { label: '严重', color: '#ff4d4f' },
  major: { label: '重要', color: '#fa8c16' },
  minor: { label: '次要', color: '#1677ff' },
  warning: { label: '警告', color: '#faad14' },
}

export const USER_STATUS_MAP: Record<number, { label: string; color: string }> = {
  0: { label: '已禁用', color: '#ff4d4f' },
  1: { label: '正常', color: '#52c41a' },
  2: { label: '已锁定', color: '#fa8c16' },
}

export const TASK_STATUS_MAP: Record<string, { label: string; color: string }> = {
  pending: { label: '待执行', color: '#d9d9d9' },
  running: { label: '执行中', color: '#1677ff' },
  completed: { label: '已完成', color: '#52c41a' },
  failed: { label: '失败', color: '#ff4d4f' },
  cancelled: { label: '已取消', color: '#faad14' },
}

export const ROLE_COLORS: Record<string, string> = {
  0: '#eb2f96',
  1: '#722ed1',
  2: '#1677ff',
  3: '#52c41a',
}
