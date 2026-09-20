/**
 * 电站监控 → 历史数据页的本地记忆。
 *
 * 默认不显示任何数据字段，由用户自己添加；选择结果按「型号」记忆，
 * 这样同一型号的多台设备打开时列集合一致，换型号也不会套用不存在的字段。
 */

const STORAGE_PREFIX = 'station_history_fields'
const MAX_REMEMBERED_FIELDS = 100

/** 可持久化的历史数据视图偏好 */
export interface StationHistoryPrefs {
  fields: string[]
  granularity?: string
}

/** localStorage 在隐私模式/被禁用时会抛异常，记忆失败不该影响主流程 */
function safeRead(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

function safeWrite(key: string, value: string): void {
  try {
    localStorage.setItem(key, value)
  } catch {
    // ignore
  }
}

/** 型号未知时退到通用键，保证仍能记住用户的选择 */
export function stationHistoryPrefsKey(modelId?: number | string | null): string {
  const scope = modelId === undefined || modelId === null || modelId === '' ? 'default' : String(modelId)
  return `${STORAGE_PREFIX}:${scope}`
}

function sanitizeFields(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  const seen = new Set<string>()
  const fields: string[] = []
  for (const item of value) {
    if (typeof item !== 'string') continue
    const key = item.trim()
    if (!key || seen.has(key)) continue
    seen.add(key)
    fields.push(key)
    if (fields.length >= MAX_REMEMBERED_FIELDS) break
  }
  return fields
}

/** 读取记忆的字段选择；没有记录时返回空数组（默认不显示任何字段） */
export function loadStationHistoryPrefs(modelId?: number | string | null): StationHistoryPrefs {
  const raw = safeRead(stationHistoryPrefsKey(modelId))
  if (!raw) return { fields: [] }
  try {
    const parsed = JSON.parse(raw)
    // 兼容早期只存数组的格式
    if (Array.isArray(parsed)) return { fields: sanitizeFields(parsed) }
    if (parsed && typeof parsed === 'object') {
      const granularity = (parsed as { granularity?: unknown }).granularity
      return {
        fields: sanitizeFields((parsed as { fields?: unknown }).fields),
        granularity: typeof granularity === 'string' ? granularity : undefined,
      }
    }
  } catch {
    return { fields: [] }
  }
  return { fields: [] }
}

export function saveStationHistoryPrefs(modelId: number | string | null | undefined, prefs: StationHistoryPrefs): void {
  const payload: StationHistoryPrefs = { fields: sanitizeFields(prefs.fields) }
  if (prefs.granularity) payload.granularity = prefs.granularity
  safeWrite(stationHistoryPrefsKey(modelId), JSON.stringify(payload))
}
