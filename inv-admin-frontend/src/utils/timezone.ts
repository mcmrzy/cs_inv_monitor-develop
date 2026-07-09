/**
 * 时区管理工具
 * 后端存储/传输统一使用 UTC, 前端根据站点时区进行本地化显示
 */
import dayjs from 'dayjs'
import utc from 'dayjs/plugin/utc'
import timezone from 'dayjs/plugin/timezone'

dayjs.extend(utc)
dayjs.extend(timezone)

/** 区域标识 */
export type TimezoneRegion = 'asia' | 'europe' | 'americas' | 'africa' | 'middle-east'

/** 时区信息 */
export interface TimezoneItem {
  id: string
  labelZh: string
  labelEn: string
  offset: string
  region: TimezoneRegion
}

/** 区域标签（中英双语） */
export const REGION_LABELS: Record<TimezoneRegion, { 'zh-CN': string; 'en-US': string }> = {
  'asia': { 'zh-CN': '亚太地区', 'en-US': 'Asia & Pacific' },
  'europe': { 'zh-CN': '欧洲', 'en-US': 'Europe' },
  'middle-east': { 'zh-CN': '中东', 'en-US': 'Middle East' },
  'africa': { 'zh-CN': '非洲', 'en-US': 'Africa' },
  'americas': { 'zh-CN': '美洲', 'en-US': 'Americas' },
}

/** 常用时区列表 (按UTC偏移量从大到小排序) */
export const TIMEZONE_LIST: TimezoneItem[] = [
  { id: 'Pacific/Auckland', labelZh: 'UTC+12 奥克兰', labelEn: 'UTC+12 Auckland', offset: '+12:00', region: 'asia' },
  { id: 'Australia/Sydney', labelZh: 'UTC+10 悉尼', labelEn: 'UTC+10 Sydney', offset: '+10:00', region: 'asia' },
  { id: 'Asia/Tokyo', labelZh: 'UTC+9 东京', labelEn: 'UTC+9 Tokyo', offset: '+09:00', region: 'asia' },
  { id: 'Asia/Seoul', labelZh: 'UTC+9 首尔', labelEn: 'UTC+9 Seoul', offset: '+09:00', region: 'asia' },
  { id: 'Asia/Shanghai', labelZh: 'UTC+8 上海', labelEn: 'UTC+8 Shanghai', offset: '+08:00', region: 'asia' },
  { id: 'Asia/Singapore', labelZh: 'UTC+8 新加坡', labelEn: 'UTC+8 Singapore', offset: '+08:00', region: 'asia' },
  { id: 'Asia/Kuala_Lumpur', labelZh: 'UTC+8 吉隆坡', labelEn: 'UTC+8 Kuala Lumpur', offset: '+08:00', region: 'asia' },
  { id: 'Asia/Manila', labelZh: 'UTC+8 马尼拉', labelEn: 'UTC+8 Manila', offset: '+08:00', region: 'asia' },
  { id: 'Asia/Ho_Chi_Minh', labelZh: 'UTC+7 胡志明', labelEn: 'UTC+7 Ho Chi Minh', offset: '+07:00', region: 'asia' },
  { id: 'Asia/Bangkok', labelZh: 'UTC+7 曼谷', labelEn: 'UTC+7 Bangkok', offset: '+07:00', region: 'asia' },
  { id: 'Asia/Jakarta', labelZh: 'UTC+7 雅加达', labelEn: 'UTC+7 Jakarta', offset: '+07:00', region: 'asia' },
  { id: 'Asia/Kolkata', labelZh: 'UTC+5:30 加尔各答', labelEn: 'UTC+5:30 Kolkata', offset: '+05:30', region: 'asia' },
  { id: 'Asia/Dubai', labelZh: 'UTC+4 迪拜', labelEn: 'UTC+4 Dubai', offset: '+04:00', region: 'middle-east' },
  { id: 'Asia/Riyadh', labelZh: 'UTC+3 利雅得', labelEn: 'UTC+3 Riyadh', offset: '+03:00', region: 'middle-east' },
  { id: 'Asia/Tehran', labelZh: 'UTC+3:30 德黑兰', labelEn: 'UTC+3:30 Tehran', offset: '+03:30', region: 'middle-east' },
  { id: 'Europe/Moscow', labelZh: 'UTC+3 莫斯科', labelEn: 'UTC+3 Moscow', offset: '+03:00', region: 'europe' },
  { id: 'Europe/Athens', labelZh: 'UTC+2 雅典', labelEn: 'UTC+2 Athens', offset: '+02:00', region: 'europe' },
  { id: 'Africa/Cairo', labelZh: 'UTC+2 开罗', labelEn: 'UTC+2 Cairo', offset: '+02:00', region: 'africa' },
  { id: 'Africa/Johannesburg', labelZh: 'UTC+2 约翰内斯堡', labelEn: 'UTC+2 Johannesburg', offset: '+02:00', region: 'africa' },
  { id: 'Europe/Rome', labelZh: 'UTC+1 罗马', labelEn: 'UTC+1 Rome', offset: '+01:00', region: 'europe' },
  { id: 'Europe/Berlin', labelZh: 'UTC+1 柏林', labelEn: 'UTC+1 Berlin', offset: '+01:00', region: 'europe' },
  { id: 'Europe/Paris', labelZh: 'UTC+1 巴黎', labelEn: 'UTC+1 Paris', offset: '+01:00', region: 'europe' },
  { id: 'Europe/Madrid', labelZh: 'UTC+1 马德里', labelEn: 'UTC+1 Madrid', offset: '+01:00', region: 'europe' },
  { id: 'Africa/Lagos', labelZh: 'UTC+1 拉各斯', labelEn: 'UTC+1 Lagos', offset: '+01:00', region: 'africa' },
  { id: 'Europe/London', labelZh: 'UTC+0 伦敦', labelEn: 'UTC+0 London', offset: '+00:00', region: 'europe' },
  { id: 'America/Toronto', labelZh: 'UTC-5 多伦多', labelEn: 'UTC-5 Toronto', offset: '-05:00', region: 'americas' },
  { id: 'America/New_York', labelZh: 'UTC-5 纽约', labelEn: 'UTC-5 New York', offset: '-05:00', region: 'americas' },
  { id: 'America/Chicago', labelZh: 'UTC-6 芝加哥', labelEn: 'UTC-6 Chicago', offset: '-06:00', region: 'americas' },
  { id: 'America/Mexico_City', labelZh: 'UTC-6 墨西哥城', labelEn: 'UTC-6 Mexico City', offset: '-06:00', region: 'americas' },
  { id: 'America/Denver', labelZh: 'UTC-7 丹佛', labelEn: 'UTC-7 Denver', offset: '-07:00', region: 'americas' },
  { id: 'America/Los_Angeles', labelZh: 'UTC-8 洛杉矶', labelEn: 'UTC-8 Los Angeles', offset: '-08:00', region: 'americas' },
  { id: 'America/Vancouver', labelZh: 'UTC-8 温哥华', labelEn: 'UTC-8 Vancouver', offset: '-08:00', region: 'americas' },
  { id: 'America/Sao_Paulo', labelZh: 'UTC-3 圣保罗', labelEn: 'UTC-3 Sao Paulo', offset: '-03:00', region: 'americas' },
  { id: 'America/Argentina/Buenos_Aires', labelZh: 'UTC-3 布宜诺斯艾利斯', labelEn: 'UTC-3 Buenos Aires', offset: '-03:00', region: 'americas' },
]

/**
 * 根据语言获取时区显示标签
 * @param tzId 时区ID
 * @param lang 语言 ('zh' | 'en')
 */
export function getTimezoneLabel(tzId: string, lang: 'zh' | 'en' = 'zh'): string {
  const tz = TIMEZONE_LIST.find(t => t.id === tzId)
  if (!tz) return tzId
  return lang === 'zh' ? tz.labelZh : tz.labelEn
}

/**
 * 将 UTC 时间格式化为指定时区的本地时间
 * @param utcTime UTC 时间字符串 (ISO 8601 格式, 如 "2024-01-01T00:00:00Z")
 * @param tz IANA 时区标识符 (如 "Asia/Shanghai")
 * @param format 输出格式 (默认 "YYYY-MM-DD HH:mm:ss")
 */
export function formatInTimezone(
  utcTime: string | Date | undefined | null,
  tz: string | undefined | null,
  format: string = 'YYYY-MM-DD HH:mm:ss'
): string {
  if (!utcTime) return '-'
  const targetTz = tz || 'Asia/Shanghai'
  try {
    return dayjs.utc(utcTime).tz(targetTz).format(format)
  } catch (e) {
    console.warn('[formatInTimezone] 时区转换失败:', { utcTime, targetTz, error: e })
    return dayjs(utcTime).format(format)
  }
}

/**
 * 将本地时间转换为 UTC 时间字符串 (用于 API 请求)
 * @param localTime 本地时间
 * @param tz 时区
 */
export function toUTCString(localTime: string | Date, tz: string): string {
  return dayjs.tz(localTime, tz).utc().toISOString()
}

/**
 * 获取当前时间在指定时区的格式化字符串
 */
export function nowInTimezone(tz: string, format: string = 'YYYY-MM-DD HH:mm:ss'): string {
  return dayjs().tz(tz || 'Asia/Shanghai').format(format)
}

/**
 * 获取区域的中英文标签
 * @param region 区域标识
 * @param lang 语言 ('zh' | 'en')
 */
export function getRegionLabel(region: TimezoneRegion, lang: 'zh' | 'en' = 'zh'): string {
  const label = REGION_LABELS[region]
  return label ? label[lang === 'zh' ? 'zh-CN' : 'en-US'] : region
}

/**
 * 将时区列表按区域分组，保持预定义顺序
 * @param lang 语言 ('zh' | 'en')
 * @param timezoneList 待分组的时区列表，默认使用 TIMEZONE_LIST
 */
export function groupTimezonesByRegion(
  lang: 'zh' | 'en' = 'zh',
  timezoneList: TimezoneItem[] = TIMEZONE_LIST
): { region: TimezoneRegion; label: string; timezones: TimezoneItem[] }[] {
  const regionOrder: TimezoneRegion[] = ['asia', 'europe', 'americas', 'africa', 'middle-east']
  const grouped = new Map<TimezoneRegion, TimezoneItem[]>()

  for (const tz of timezoneList) {
    const list = grouped.get(tz.region)
    if (list) {
      list.push(tz)
    } else {
      grouped.set(tz.region, [tz])
    }
  }

  return regionOrder
    .filter(r => grouped.has(r))
    .map(r => ({
      region: r,
      label: getRegionLabel(r, lang),
      timezones: grouped.get(r)!,
    }))
}
