/**
 * 调试曲线名（含「（计算）」后缀）的唯一来源：图例、tooltip、CSV 表头共用，
 * 避免同一测点在不同位置出现不同叫法。
 *
 * 表头用不带后缀的短名（shortLabels）——列宽有限，中文后缀会把表头挤成两行断字；
 * 「计算」信息改由表头副行的小字标注。
 */
import { useMemo } from 'react'

import useTranslation from '@/hooks/useTranslation'
import { METRIC_KEYS, POWER_KEYS, SERIES_DEFS, isDerived, type SeriesKey } from './debugMetrics'

export interface DebugLabels {
  /** 带「（计算）」后缀：图例 / tooltip / CSV 表头 */
  labels: Record<string, string>
  /** 不带后缀：表格列头（第一行） */
  shortLabels: Record<string, string>
}

export function useDebugLabels(): DebugLabels {
  const { t } = useTranslation()
  return useMemo(() => {
    const labels: Record<string, string> = {}
    const shortLabels: Record<string, string> = {}
    const suffix = t('deviceDetail.debug.derivedSuffix')
    for (const key of [...METRIC_KEYS, ...POWER_KEYS] as SeriesKey[]) {
      const name = t(SERIES_DEFS[key].labelKey)
      shortLabels[key] = name
      labels[key] = isDerived(key) ? `${name}${suffix}` : name
    }
    return { labels, shortLabels }
  }, [t])
}
