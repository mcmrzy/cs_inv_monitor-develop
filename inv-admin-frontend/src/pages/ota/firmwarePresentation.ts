/**
 * 独立模块固件升级 — 展示层纯函数。
 *
 * 用户可见文案不得暴露芯片内部后缀（ARM/ESP/DSP/BMS），
 * 这里统一做模块名映射与遗留标签清洗。
 */

export type TranslateFn = (key: string) => string

/** 模块 target → 文案 key（无芯片内部后缀） */
const MODULE_LABEL_KEYS: Record<string, string> = {
  arm: 'ota.moduleArm',
  esp: 'ota.moduleEsp',
  dsp: 'ota.moduleDsp',
  bms: 'ota.moduleBms',
}

/** 规范化模块 target：去空白、小写 */
export function normalizeFirmwareTarget(target: string | null | undefined): string {
  return String(target ?? '').trim().toLowerCase()
}

/**
 * 将模块 target 映射为用户可见名称。
 * 未知 target 时回退为大写原值，避免空白。
 */
export function firmwareModuleLabel(target: string | null | undefined, t: TranslateFn): string {
  const key = MODULE_LABEL_KEYS[normalizeFirmwareTarget(target)]
  if (!key) {
    const raw = String(target ?? '').trim()
    return raw ? raw.toUpperCase() : '-'
  }
  return t(key)
}

/**
 * 清洗遗留固件/模块标签：去掉半/全角括号包裹的芯片后缀、
 * 连字符/下划线/空格后的芯片 token，以及大小写变体。
 *
 * 例：
 *   '系统中控（ARM）' → '系统中控'
 *   'Communication (ESP)' → 'Communication'
 *   '计算控制-dsp' → '计算控制'
 *   '  BMS_电池  ' → '电池' / 'BMS' 仅当整体就是芯片名时保留 token
 */
export function sanitizeLegacyFirmwareLabel(value: string | null | undefined): string {
  let s = String(value ?? '')
  if (!s) return ''

  // 全角括号/方括号/书名号 → 半角圆括号，便于统一处理
  s = s.replace(/[（［【〖]/g, '(').replace(/[）］】〗]/g, ')')
  // 全角空格与连续空白折叠
  s = s.replace(/[\u3000\s]+/g, ' ').trim()

  // 去掉包裹芯片名的括号： (ARM) / [esp] / <DSP>
  s = s.replace(/[([]\s*(?:arm|esp|dsp|bms)\s*[)\]]/gi, '')
  // 去掉尾部用分隔符拼接的芯片后缀： -arm / _esp / /dsp / |bms / ·ARM
  s = s.replace(/[\s\-_/|·]+(?:arm|esp|dsp|bms)$/i, '')
  // 去掉前缀芯片标记： ARM-xxx / ESP_xxx
  s = s.replace(/^(?:arm|esp|dsp|bms)[\s\-_/|·]+/i, '')

  s = s.replace(/[\u3000\s]+/g, ' ').trim()
  // 清洗后可能只剩分隔符
  if (!s || /^[-_/|·\s]+$/.test(s)) return ''
  return s
}

/**
 * 合成展示名：优先使用清洗后的遗留标签，否则用模块映射。
 */
export function displayFirmwareModuleLabel(
  target: string | null | undefined,
  legacyLabel: string | null | undefined,
  t: TranslateFn,
): string {
  const cleaned = sanitizeLegacyFirmwareLabel(legacyLabel)
  if (cleaned) return cleaned
  return firmwareModuleLabel(target, t)
}
