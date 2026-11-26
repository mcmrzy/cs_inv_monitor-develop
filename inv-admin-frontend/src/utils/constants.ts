

export const DEVICE_STATUS_MAP: Record<string, { label: string; color: string; i18nKey: string }> = {
  0: { label: '离线', color: '#d9d9d9', i18nKey: 'common.offline' },
  1: { label: '在线', color: '#52c41a', i18nKey: 'common.online' },
  2: { label: '故障', color: '#ff4d4f', i18nKey: 'common.fault' },
  offline: { label: '离线', color: '#d9d9d9', i18nKey: 'common.offline' },
  online: { label: '在线', color: '#52c41a', i18nKey: 'common.online' },
  fault: { label: '故障', color: '#ff4d4f', i18nKey: 'common.fault' },
}

export const ALARM_LEVEL_MAP: Record<string, { label: string; color: string; i18nKey: string }> = {
  1: { label: '提示', color: '#1677ff', i18nKey: 'common.alarmInfo' },
  2: { label: '警告', color: '#fa8c16', i18nKey: 'common.alarmWarning' },
  3: { label: '严重', color: '#ff4d4f', i18nKey: 'common.alarmCritical' },
  // 字符串级别映射（设备上报的 level 字段）
  fault: { label: '严重', color: '#ff4d4f', i18nKey: 'common.alarmCritical' },
  warning: { label: '警告', color: '#fa8c16', i18nKey: 'common.alarmWarning' },
  info: { label: '提示', color: '#1677ff', i18nKey: 'common.alarmInfo' },
  normal: { label: '正常', color: '#52c41a', i18nKey: 'common.normal' },
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
  17920: 3,
  17921: 3,
  17922: 3,
  17923: 3,
  17924: 3,
  17925: 3,
  17926: 3,
  17927: 3,
  17928: 3,
  17929: 3,
  17930: 3,
  17931: 3,
  17932: 3,
  17933: 3,
  17934: 3,
  17935: 3,
  18176: 3,
  18177: 3,
  18178: 3,
  18179: 3,
  18180: 3,
  18181: 3,
  18182: 3,
  18183: 3,
  18184: 3,
  18185: 3,
  18186: 3,
  18187: 3,
  18188: 3,
  18189: 3,
  18190: 3,
  18191: 3,
  18432: 2,
  18433: 2,
  18434: 2,
  18435: 2,
  18436: 2,
  18437: 2,
  18438: 2,
  18439: 2,
  18440: 2,
  18441: 2,
  18442: 2,
  18443: 2,
  18444: 2,
  18445: 2,
  18446: 2,
  18447: 2,
  18688: 2,
  18689: 2,
  18690: 2,
  18691: 2,
  18692: 2,
  18693: 2,
  18694: 2,
  18695: 2,
  18696: 2,
  18697: 2,
  18698: 2,
  18699: 2,
  18700: 2,
  18701: 2,
  18702: 2,
  18703: 2,
  22016: 3,
  22017: 3,
  22018: 3,
  22019: 3,
  22020: 3,
  22021: 3,
  22022: 3,
  22023: 3,
  22024: 3,
  22025: 3,
  22026: 3,
  22027: 3,
  22028: 3,
  22029: 3,
  22030: 3,
  22031: 3,
  22272: 3,
  22273: 3,
  22274: 3,
  22275: 3,
  22276: 3,
  22277: 3,
  22278: 3,
  22279: 3,
  22280: 3,
  22281: 3,
  22282: 3,
  22283: 3,
  22284: 3,
  22285: 3,
  22286: 3,
  22287: 3,
  22528: 2,
  22529: 2,
  22530: 2,
  22531: 2,
  22532: 2,
  22533: 2,
  22534: 2,
  22535: 2,
  22536: 2,
  22537: 2,
  22538: 2,
  22539: 2,
  22540: 2,
  22541: 2,
  22542: 2,
  22543: 2,
  22784: 2,
  22785: 2,
  22786: 2,
  22787: 2,
  22788: 2,
  22789: 2,
  22790: 2,
  22791: 2,
  22792: 2,
  22793: 2,
  22794: 2,
  22795: 2,
  22796: 2,
  22797: 2,
  22798: 2,
  22799: 2,
  18944: 3,
  18945: 2,
  18946: 2,
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
  17920: "市电软启失败",
  17921: "母线过压",
  17922: "母线欠压",
  17923: "电池过流",
  17924: "过温",
  17925: "电池过压",
  17926: "电池软启故障",
  17927: "母线短路",
  17928: "逆变软启故障",
  17929: "逆变过压",
  17930: "逆变欠压",
  17931: "逆变短路",
  17932: "负功保护",
  17933: "过载故障",
  17934: "机型不匹配",
  17935: "无引导程序",
  18176: "程序烧录中",
  18177: "光伏反接",
  18178: "并机序号异常",
  18179: "并机通信异常",
  18180: "并机电池压差",
  18181: "并机市电压差",
  18182: "并机频率差",
  18183: "并机设置缺相",
  18184: "并机同步丢失",
  18185: "BMS故障",
  18186: "MCU故障",
  18187: "保留位",
  18188: "逆变负载异常",
  18189: "PV过压",
  18190: "保留位",
  18191: "保留位",
  18432: "电池未接",
  18433: "电池欠压",
  18434: "电池低压",
  18435: "充电器短路",
  18436: "保留位",
  18437: "电池过充",
  18438: "BMS丢失",
  18439: "过温预留",
  18440: "风扇堵转",
  18441: "存储故障",
  18442: "过载",
  18443: "发电机波形",
  18444: "PV能量弱",
  18445: "并机同步丢失",
  18446: "并机设置缺相",
  18447: "并机版本",
  18688: "并机通信异常",
  18689: "并机压差频差",
  18690: "低SOC关机",
  18691: "低SOC告警",
  18692: "并机电池压差",
  18693: "电池短路",
  18694: "电池低于启动",
  18695: "发电机过载",
  18696: "发电机欠压",
  18697: "发电机过压",
  18698: "CT连接异常",
  18699: "市电不稳定",
  18700: "电表通信失败",
  18701: "保留位",
  18702: "保留位",
  18703: "保留位",
  22016: "母线软启故障",
  22017: "母线过压",
  22018: "母线欠压",
  22019: "DCDC 硬件过流保护TZ",
  22020: "控制板/散热器过温",
  22021: "电池过压故障",
  22022: "母线IP软启故障",
  22023: "母线短路",
  22024: "逆变软启故障",
  22025: "逆变过压",
  22026: "逆变欠压",
  22027: "逆变交流短路",
  22028: "逆变负有功/倒灌",
  22029: "逆变过载故障",
  22030: "机型识别错误",
  22031: "版权/认证错误",
  22272: "显示屏Flash闪存故障",
  22273: "光伏过流硬件保护",
  22274: "并机序列号重复",
  22275: "CAN通信故障",
  22276: "并机电池电压差异大",
  22277: "并机市电电压不同",
  22278: "并机市电频率不同",
  22279: "并机输出参数不同",
  22280: "并机同步信号丢失",
  22281: "BMS电池包故障",
  22282: "MCU内部故障",
  22283: "NTC热敏电阻开路",
  22284: "逆变硬件TZ过流故障",
  22285: "预留",
  22286: "预留",
  22287: "预留",
  22528: "电池开路/未接",
  22529: "电池欠压告警",
  22530: "电池低压告警",
  22531: "电池充电短路告警",
  22532: "预留",
  22533: "电池过充告警",
  22534: "BMS通讯丢失告警",
  22535: "机器过温告警",
  22536: "风扇堵转告警",
  22537: "EEPROM读写故障",
  22538: "逆变过载告警",
  22539: "发电机停机/掉电",
  22540: "光伏能量弱",
  22541: "并机同步信号故障",
  22542: "并机配置不兼容",
  22543: "并机固件版本不一致",
  22784: "并机通讯失败",
  22785: "并机市电相位/电压差异",
  22786: "电池SOC欠压关机告警",
  22787: "电池SOC低电告警",
  22788: "预留",
  22789: "预留",
  22790: "电池辅助电源(SPS)故障",
  22791: "预留",
  22792: "预留",
  22793: "预留",
  22794: "预留",
  22795: "预留",
  22796: "预留",
  22797: "预留",
  22798: "预留",
  22799: "预留",
  18944: "逆变器通信中断",
  18945: "告警历史缺口（队列溢出）",
  18946: "告警寄存器数据未知或过期",
}

export function getAlarmMessageI18nKey(
  faultCode: string | number | null | undefined,
): string | undefined {
  const code = parseFaultCode(faultCode)
  return ALARM_CODE_MESSAGE[code] !== undefined ? `alarm.code.${code}` : undefined
}

// 解析故障码为十进制数值（支持十进制字符串和0x十六进制格式）
export function parseFaultCode(faultCode: string | number | null | undefined): number {
  if (faultCode == null) return -1
  if (typeof faultCode === 'number') return faultCode
  const str = String(faultCode).trim()
  if (str === '') return -1
  if (str.startsWith('0x') || str.startsWith('0X')) {
    const parsed = parseInt(str.substring(2), 16)
    return Number.isNaN(parsed) ? -1 : parsed
  }
  const parsed = parseInt(str, 10)
  return Number.isNaN(parsed) ? -1 : parsed
}

// 根据故障码获取告警级别显示，优先使用告警码映射，回退到 alarm_level
export function getAlarmLevelDisplay(
  faultCode: string | number | null | undefined,
  alarmLevel: number | string,
): { label: string; color: string; i18nKey?: string } {
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

export const CHART_COLORS = ['#1677ff', '#52c41a', '#fa8c16', '#722ed1', '#eb2f96', '#13c2c2']

export const HERO_GRADIENTS = [
  'linear-gradient(135deg, #4a6cf7 0%, #6366f1 100%)',
  'linear-gradient(135deg, #f97316 0%, #fb923c 100%)',
  'linear-gradient(135deg, #22c55e 0%, #4ade80 100%)',
  'linear-gradient(135deg, #8b5cf6 0%, #a78bfa 100%)',
  'linear-gradient(135deg, #3b82f6 0%, #60a5fa 100%)',
  'linear-gradient(135deg, #06b6d4 0%, #22d3ee 100%)',
]
