/**
 * 一次性引导（绑定后设置设备名称、注册后完善头像昵称）的本地记忆。
 *
 * 两个引导都是可选的：用户点「忽略」后就不再打扰。资料引导按用户 id 记，
 * 设备命名引导按 SN 记 —— 同一浏览器切换账号、或同一账号继续绑新设备时互不影响。
 */

const PROFILE_PENDING_KEY = 'onboarding_profile_pending'
const DEVICE_NAME_SKIPPED_KEY = 'onboarding_device_name_skipped'

const profileSkippedKey = (userId: string | number) => `onboarding_profile_skipped_${userId}`

/** localStorage 在隐私模式/被禁用时会抛异常，引导记忆失败不该影响主流程 */
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

function safeRemove(key: string): void {
  try {
    localStorage.removeItem(key)
  } catch {
    // ignore
  }
}

// ── 注册后完善资料 ──

/** 注册成功后打标，进入主框架时据此弹一次完善资料弹窗 */
export function markProfileSetupPending(): void {
  safeWrite(PROFILE_PENDING_KEY, '1')
}

export function isProfileSetupPending(): boolean {
  return safeRead(PROFILE_PENDING_KEY) === '1'
}

export function clearProfileSetupPending(): void {
  safeRemove(PROFILE_PENDING_KEY)
}

export function isProfileSetupSkipped(userId: string | number): boolean {
  return safeRead(profileSkippedKey(userId)) === '1'
}

export function markProfileSetupSkipped(userId: string | number): void {
  safeWrite(profileSkippedKey(userId), '1')
}

// ── 绑定后设置设备名称 ──

function readSkippedSns(): string[] {
  const raw = safeRead(DEVICE_NAME_SKIPPED_KEY)
  if (!raw) return []
  try {
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed.filter((v): v is string => typeof v === 'string') : []
  } catch {
    return []
  }
}

/** 该设备是否已被用户忽略命名 */
export function isDeviceNameSkipped(sn: string): boolean {
  return readSkippedSns().includes(sn)
}

export function markDeviceNameSkipped(sn: string): void {
  const sns = readSkippedSns()
  if (sns.includes(sn)) return
  sns.push(sn)
  safeWrite(DEVICE_NAME_SKIPPED_KEY, JSON.stringify(sns))
}
