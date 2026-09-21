const storageKey = 'pending-device-bind-v1'

export interface PendingDeviceBind {
  sn: string
  pin: string
}

export function parseDeviceBind(search: string): PendingDeviceBind | null {
  const params = new URLSearchParams(search)
  const sn = params.get('sn')?.trim().toUpperCase() ?? ''
  const pin = params.get('pin')?.trim() ?? ''
  if (!/^[A-Z0-9]{16}$/.test(sn) || (pin !== '' && !/^\d{6}$/.test(pin))) return null
  return { sn, pin }
}

export function bindAppUrl(bind: PendingDeviceBind): string {
  const params = new URLSearchParams({ sn: bind.sn, pin: bind.pin })
  return `csinv://bind?${params}`
}

export function savePendingDeviceBind(bind: PendingDeviceBind): void {
  try {
    sessionStorage.setItem(storageKey, JSON.stringify({ ...bind, savedAt: Date.now() }))
  } catch {
    // Private browsing may disable storage; the user can rescan the QR code.
  }
}

export function readPendingDeviceBind(): PendingDeviceBind | null {
  try {
    const raw = sessionStorage.getItem(storageKey)
    if (!raw) return null
    const value = JSON.parse(raw) as PendingDeviceBind & { savedAt?: number }
    if (!value.savedAt || Date.now() - value.savedAt > 24 * 60 * 60 * 1000) return null
    const params = new URLSearchParams({ sn: value.sn, pin: value.pin })
    return parseDeviceBind(`?${params}`)
  } catch {
    return null
  }
}
