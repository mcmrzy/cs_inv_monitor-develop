
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

export const ALARM_LEVEL_OPTIONS = [
  { label: '严重', value: 1 },
  { label: '警告', value: 2 },
  { label: '提示', value: 3 },
]

// 根据故障码映射告警严重级别，与移动端 alarm_code_mapping.dart 保持一致
// key 为故障码的十进制数值
export const FAULT_CODE_SEVERITY: Record<number, 'critical' | 'warning'> = {
  // critical 级别
  0x0001: 'critical', // 电网过压
  0x0002: 'critical', // 电网欠压
  0x0004: 'critical', // 电网过频
  0x0008: 'critical', // 电网欠频
  0x0010: 'critical', // PV过压
  0x0040: 'critical', // 电池过压
  0x0100: 'critical', // 电池过温
  0x0400: 'critical', // 逆变器过温
  0x0800: 'critical', // 逆变器过载
  0x1000: 'critical', // 短路保护
  0x2000: 'critical', // 漏流保护
  0x4000: 'critical', // 接地故障
  0x00010002: 'critical', // 电池充放过流
  0x00010008: 'critical', // BMS通信断开
  0x00010010: 'critical', // 电池绝缘故障
  0x00020001: 'critical', // DC母线过压
  0x00020040: 'critical', // ADC采样异常
  0x00020080: 'critical', // 继电器故障
  0x00020100: 'critical', // 固件校验失败
  // warning 级别
  0x0020: 'warning', // PV欠压
  0x0080: 'warning', // 电池欠压
  0x0200: 'warning', // 电池低温
  0x8000: 'warning', // 通信故障
  0x00010001: 'warning', // 电池SOC过低
  0x00010004: 'warning', // 电芯压差过大
  0x00020002: 'warning', // DC母线欠压
  0x00020004: 'warning', // 散热器过温
  0x00020008: 'warning', // 风扇故障
  0x00020010: 'warning', // EEPROM错误
  0x00020020: 'warning', // SPI通信错误
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

// 根据故障码获取告警级别，优先使用故障码映射，回退到 alarm_level
export function getAlarmLevelDisplay(
  faultCode: string | number | null | undefined,
  alarmLevel: number | string,
): { label: string; color: string } {
  const code = parseFaultCode(faultCode)
  const severity = code >= 0 ? FAULT_CODE_SEVERITY[code] : undefined
  if (severity === 'critical') return { label: '严重', color: '#ff4d4f' }
  if (severity === 'warning') return { label: '警告', color: '#fa8c16' }
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
