/**
 * 时区管理工具
 * 后端存储/传输统一使用 UTC, 前端根据站点时区进行本地化显示
 */
import dayjs from 'dayjs'
import utc from 'dayjs/plugin/utc'
import timezone from 'dayjs/plugin/timezone'

dayjs.extend(utc)
dayjs.extend(timezone)

/** 常用时区列表 (与后端保持一致) */
export const TIMEZONE_LIST = [
  { id: 'Pacific/Auckland', label: 'UTC+12 Auckland', offset: '+12:00' },
  { id: 'Australia/Sydney', label: 'UTC+10 Sydney', offset: '+10:00' },
  { id: 'Asia/Tokyo', label: 'UTC+9 Tokyo', offset: '+09:00' },
  { id: 'Asia/Seoul', label: 'UTC+9 Seoul', offset: '+09:00' },
  { id: 'Asia/Shanghai', label: 'UTC+8 Shanghai', offset: '+08:00' },
  { id: 'Asia/Singapore', label: 'UTC+8 Singapore', offset: '+08:00' },
  { id: 'Asia/Ho_Chi_Minh', label: 'UTC+7 Ho Chi Minh', offset: '+07:00' },
  { id: 'Asia/Bangkok', label: 'UTC+7 Bangkok', offset: '+07:00' },
  { id: 'Asia/Jakarta', label: 'UTC+7 Jakarta', offset: '+07:00' },
  { id: 'Asia/Kolkata', label: 'UTC+5:30 Kolkata', offset: '+05:30' },
  { id: 'Asia/Kuala_Lumpur', label: 'UTC+8 Kuala Lumpur', offset: '+08:00' },
  { id: 'Asia/Manila', label: 'UTC+8 Manila', offset: '+08:00' },
  { id: 'Asia/Dubai', label: 'UTC+4 Dubai', offset: '+04:00' },
  { id: 'Asia/Riyadh', label: 'UTC+3 Riyadh', offset: '+03:00' },
  { id: 'Asia/Tehran', label: 'UTC+3:30 Tehran', offset: '+03:30' },
  { id: 'Europe/Moscow', label: 'UTC+3 Moscow', offset: '+03:00' },
  { id: 'Europe/Berlin', label: 'UTC+1 Berlin', offset: '+01:00' },
  { id: 'Europe/Paris', label: 'UTC+1 Paris', offset: '+01:00' },
  { id: 'Europe/Athens', label: 'UTC+2 Athens', offset: '+02:00' },
  { id: 'Europe/Madrid', label: 'UTC+1 Madrid', offset: '+01:00' },
  { id: 'Europe/London', label: 'UTC+0 London', offset: '+00:00' },
  { id: 'Africa/Lagos', label: 'UTC+1 Lagos', offset: '+01:00' },
  { id: 'America/New_York', label: 'UTC-5 New York', offset: '-05:00' },
  { id: 'America/Chicago', label: 'UTC-6 Chicago', offset: '-06:00' },
  { id: 'America/Denver', label: 'UTC-7 Denver', offset: '-07:00' },
  { id: 'America/Los_Angeles', label: 'UTC-8 Los Angeles', offset: '-08:00' },
  { id: 'America/Mexico_City', label: 'UTC-6 Mexico City', offset: '-06:00' },
  { id: 'America/Sao_Paulo', label: 'UTC-3 Sao Paulo', offset: '-03:00' },
]

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
  } catch {
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
 * 获取时区的显示标签
 */
export function getTimezoneLabel(tzId: string): string {
  return TIMEZONE_LIST.find(tz => tz.id === tzId)?.label || tzId
}
