import { afterEach, describe, expect, it, vi } from 'vitest'
import { tryOpenApp } from './openApp'

afterEach(() => vi.useRealTimers())

describe('tryOpenApp', () => {
  it('opens the app and sends a still-visible browser to download', () => {
    vi.useFakeTimers()
    const launch = vi.fn()
    const fallback = vi.fn()
    tryOpenApp('csinv://bind?sn=H1ZZX0013900001P&pin=344411', fallback, window, document, launch)
    expect(launch).toHaveBeenCalledOnce()
    vi.advanceTimersByTime(2500)
    expect(fallback).toHaveBeenCalledOnce()
  })

  it('does not redirect after the browser backgrounds for the app', () => {
    vi.useFakeTimers()
    const fallback = vi.fn()
    tryOpenApp('csinv://bind', fallback, window, document, vi.fn())
    window.dispatchEvent(new Event('pagehide'))
    vi.advanceTimersByTime(2500)
    expect(fallback).not.toHaveBeenCalled()
  })
})
