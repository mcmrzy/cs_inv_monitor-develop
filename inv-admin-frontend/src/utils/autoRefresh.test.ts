import { afterEach, describe, expect, it, vi } from 'vitest'
import { MutationObserver, QueryObserver } from '@tanstack/react-query'
import { autoRefreshInterval } from './autoRefresh'
import { createAppQueryClient } from './createAppQueryClient'

describe('automatic data refresh', () => {
  afterEach(() => vi.restoreAllMocks())

  it('polls changing task and device state faster than ordinary settings', () => {
    expect(autoRefreshInterval(['ota', 'tasks', { page: 1 }])).toBe(10_000)
    expect(autoRefreshInterval(['devices', 'realtime', 'SN001'])).toBe(15_000)
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
})
