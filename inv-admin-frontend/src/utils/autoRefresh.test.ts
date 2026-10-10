import { afterEach, describe, expect, it, vi } from 'vitest'
import { focusManager, MutationObserver, QueryObserver } from '@tanstack/react-query'
import { autoRefreshInterval } from './autoRefresh'
import { createAppQueryClient } from './createAppQueryClient'

describe('automatic data refresh', () => {
  afterEach(() => vi.restoreAllMocks())

  it('polls changing task and device state faster than ordinary settings', () => {
    expect(autoRefreshInterval(['ota', 'tasks', { page: 1 }])).toBe(10_000)
    expect(autoRefreshInterval(['devices', 'realtime', 'SN001'])).toBe(15_000)
    expect(autoRefreshInterval(['devices', 'realtime-batch'])).toBe(15_000)
    expect(autoRefreshInterval(['station-rt-overview', '1'])).toBe(15_000)
    expect(autoRefreshInterval(['station-devices-rt', 1])).toBe(15_000)
    expect(autoRefreshInterval(['ota', 'upgrades', { page: 1 }])).toBe(10_000)
    expect(autoRefreshInterval(['stations', 'summary'])).toBe(30_000)
    expect(autoRefreshInterval(['system-config', 'domains'])).toBe(120_000)
  })

  it('refreshes active queries after a successful operation and on focus', async () => {
    const client = createAppQueryClient()
    const fetcher = vi.fn().mockResolvedValue({ items: [] })
    const observer = new QueryObserver(client, { queryKey: ['users', 'list'], queryFn: fetcher })
    const unsubscribe = observer.subscribe(() => {})

    try {
      await vi.waitFor(() => expect(fetcher).toHaveBeenCalledTimes(1))

      const mutation = new MutationObserver(client, { mutationFn: async () => ({ code: 0 }) })
      await mutation.mutate()

      await vi.waitFor(() => expect(fetcher).toHaveBeenCalledTimes(2))
      expect(client.getDefaultOptions().queries?.refetchOnWindowFocus).toBe('always')
      expect(client.getDefaultOptions().queries?.refetchOnReconnect).toBe('always')
      expect(client.getDefaultOptions().queries?.refetchOnMount).toBe('always')
    } finally {
      unsubscribe()
      client.clear()
    }
  })

  it('resumes polling after a hidden page returns, even when data did not change', async () => {
    vi.useFakeTimers()
    const client = createAppQueryClient()
    client.mount()
    const fetcher = vi.fn().mockResolvedValue({ power: 100 })
    const observer = new QueryObserver(client, { queryKey: ['station-devices-rt', 1], queryFn: fetcher })
    const unsubscribe = observer.subscribe(() => {})
    try {
      await vi.advanceTimersByTimeAsync(1)
      expect(fetcher).toHaveBeenCalledTimes(1)
      focusManager.setFocused(false)
      await vi.advanceTimersByTimeAsync(30_000)
      expect(fetcher).toHaveBeenCalledTimes(1)
      focusManager.setFocused(true)
      await vi.advanceTimersByTimeAsync(1)
      expect(fetcher).toHaveBeenCalledTimes(2)
      await vi.advanceTimersByTimeAsync(15_000)
      expect(fetcher).toHaveBeenCalledTimes(3)
    } finally {
      unsubscribe()
      client.unmount()
      client.clear()
      focusManager.setFocused(undefined)
      vi.useRealTimers()
    }
  })
})
