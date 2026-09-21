import { beforeEach, describe, expect, it, vi } from 'vitest'
import { bindAppUrl, parseDeviceBind, readPendingDeviceBind, savePendingDeviceBind } from './pendingDeviceBind'

beforeEach(() => sessionStorage.clear())

describe('device bind handoff', () => {
  it('preserves the QR parameters through the download page', () => {
    const bind = parseDeviceBind('?sn=h1zzx0013900001p&pin=344411')
    expect(bind).toEqual({ sn: 'H1ZZX0013900001P', pin: '344411' })
    savePendingDeviceBind(bind!)
    expect(bindAppUrl(readPendingDeviceBind()!)).toBe('csinv://bind?sn=H1ZZX0013900001P&pin=344411')
  })

  it('rejects malformed identifiers and expired stored links', () => {
    expect(parseDeviceBind('?sn=bad&pin=344411')).toBeNull()
    expect(parseDeviceBind('?sn=H1ZZX0013900001P&pin=abc')).toBeNull()
    const bind = parseDeviceBind('?sn=H1ZZX0013900001P&pin=344411')!
    savePendingDeviceBind(bind)
    vi.spyOn(Date, 'now').mockReturnValue(Date.now() + 25 * 60 * 60 * 1000)
    expect(readPendingDeviceBind()).toBeNull()
    vi.restoreAllMocks()
  })
})
