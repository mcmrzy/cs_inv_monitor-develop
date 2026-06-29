/** 安全转为数字 */
export function safeNum(v: unknown): number {
  if (v == null || v === '') return 0
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

/** 格式化数字显示 */
export function fmt(v: unknown, decimals = 1, suffix = ''): string {
  const n = safeNum(v)
  return n !== 0 ? `${n.toFixed(decimals)}${suffix}` : `--${suffix}`
}
