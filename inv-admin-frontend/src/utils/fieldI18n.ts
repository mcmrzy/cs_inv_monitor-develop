import type { Lang } from '@/stores/localeStore'

const ACRONYMS: Record<string, string> = {
  ac: 'AC',
  bms: 'BMS',
  dc: 'DC',
  eps: 'EPS',
  id: 'ID',
  mppt: 'MPPT',
  mqtt: 'MQTT',
  pf: 'PF',
  pv: 'PV',
  soc: 'SOC',
  soh: 'SOH',
  sn: 'SN',
  thd: 'THD',
  wifi: 'WiFi',
}

const formatToken = (token: string): string => {
  const lower = token.toLowerCase()
  if (ACRONYMS[lower]) return ACRONYMS[lower]
  const compound = lower.match(/^(pv|ac|dc|bms|eps|mppt)(\d+)$/)
  if (compound) return `${ACRONYMS[compound[1]]}${compound[2]}`
  return lower ? lower[0].toUpperCase() + lower.slice(1) : lower
}

export const humanizeFieldKey = (fieldKey: string): string =>
  fieldKey.split('_').filter(Boolean).map(formatToken).join(' ')

export const localizeFieldName = (
  fieldKey: string,
  fieldName: string | null | undefined,
  lang: Lang,
): string => {
  const supplied = fieldName?.trim()
  if (lang === 'zh' && supplied) return supplied
  if (lang === 'en' && supplied && !/[\u3400-\u9fff]/u.test(supplied)) return supplied
  return humanizeFieldKey(fieldKey) || supplied || '-'
}
