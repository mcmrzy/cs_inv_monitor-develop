
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
  1: { label: '提示', color: '#1677ff' },
  2: { label: '警告', color: '#fa8c16' },
  3: { label: '严重', color: '#ff4d4f' },
  // 字符串级别映射（设备上报的 level 字段）
  fault: { label: '严重', color: '#ff4d4f' },
  warning: { label: '警告', color: '#fa8c16' },
  info: { label: '提示', color: '#1677ff' },
  normal: { label: '正常', color: '#52c41a' },
}

export const ALARM_LEVEL_OPTIONS = [
  { label: '严重', value: 3 },
  { label: '警告', value: 2 },
  { label: '提示', value: 1 },
]

// 告警码到级别的映射，与移动端 alarm_code_mapping.dart 及后端保持一致
// DB alarm_level: 1=提示(info) 2=警告(warning) 3=严重(fault)
export const ALARM_CODE_LEVEL: Record<number, number> = {
  0: 1,  // 故障恢复，正常运行
  1: 3,  // 逆变器过温保护
  2: 3,  // 电池过压保护
  3: 3,  // 电池欠压保护
  4: 3,  // 输出过载保护
  5: 3,  // 直流母线过压
  6: 2,  // 逆变器温度过高
  7: 2,  // 电池SOC过低
  8: 2,  // PV输入异常
  9: 2,  // 电芯压差过大
  10: 1, // 系统启动完成
  11: 1, // 进入待机模式
  12: 1, // 恢复并网运行
}

// 告警码到描述的映射
export const ALARM_CODE_MESSAGE: Record<number, string> = {
  0: '故障恢复，系统正常',
  1: '逆变器过温保护',
  2: '电池过压保护',
  3: '电池欠压保护',
  4: '输出过载保护',
  5: '直流母线过压',
  6: '逆变器温度过高',
  7: '电池SOC过低',
  8: 'PV输入异常',
  9: '电芯压差过大',
  10: '系统启动完成',
  11: '进入待机模式',
  12: '恢复并网运行',
}

// 解析故障码为十进制数值（支持十进制字符串和0x十六进制格式）
export function parseFaultCode(faultCode: string | number | null | undefined): number {
  if (faultCode == null) return -1
  if (typeof faultCode === 'number') return faultCode
  const str = String(faultCode).trim()
  if (str.startsWith('0x') || str.startsWith('0X')) {
    return parseInt(str.substring(2), 16) || -1
  }
  return parseInt(str, 10) || -1
}

// 根据故障码获取告警级别显示，优先使用告警码映射，回退到 alarm_level
export function getAlarmLevelDisplay(
  faultCode: string | number | null | undefined,
  alarmLevel: number | string,
): { label: string; color: string } {
  const code = parseFaultCode(faultCode)
  // 优先使用告警码映射
  if (code >= 0 && ALARM_CODE_LEVEL[code] !== undefined) {
    const level = ALARM_CODE_LEVEL[code]
    return ALARM_LEVEL_MAP[level] || { label: String(alarmLevel), color: '#d9d9d9' }
  }
  // 回退到 alarm_level
  const key = typeof alarmLevel === 'number' ? String(alarmLevel) : alarmLevel
  return ALARM_LEVEL_MAP[key] || { label: String(alarmLevel), color: '#d9d9d9' }
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

export const CHART_COLORS = ['#1677ff', '#52c41a', '#fa8c16', '#722ed1', '#eb2f96', '#13c2c2']

export const HERO_GRADIENTS = [
  'linear-gradient(135deg, #4a6cf7 0%, #6366f1 100%)',
  'linear-gradient(135deg, #f97316 0%, #fb923c 100%)',
  'linear-gradient(135deg, #22c55e 0%, #4ade80 100%)',
  'linear-gradient(135deg, #8b5cf6 0%, #a78bfa 100%)',
  'linear-gradient(135deg, #3b82f6 0%, #60a5fa 100%)',
  'linear-gradient(135deg, #06b6d4 0%, #22d3ee 100%)',
]
