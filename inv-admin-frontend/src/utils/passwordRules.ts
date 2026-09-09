import type { Rule } from 'antd/es/form'

/**
 * 统一密码强度策略（与注册页保持一致）：
 * - 最少 6 位
 * - 必须同时包含字母和数字
 *
 * 文案通过 t() 走语言包（key: user.pwdRule）。
 */
export const passwordRule = (t: (key: string) => string): Rule[] => [
  { min: 6, message: t('user.pwdRule') },
  { pattern: /^(?=.*[a-zA-Z])(?=.*\d).+$/, message: t('user.pwdRule') },
]
