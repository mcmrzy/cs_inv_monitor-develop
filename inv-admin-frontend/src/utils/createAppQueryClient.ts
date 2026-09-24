import { MutationCache, QueryClient } from '@tanstack/react-query'
import { autoRefreshInterval } from './autoRefresh'

export function createAppQueryClient(): QueryClient {
  const client: QueryClient = new QueryClient({
    mutationCache: new MutationCache({
      // Keep related cards, counts and details in sync even when a page only
      // invalidates its own list. Inactive queries are marked stale for next visit.
      onSuccess: (): void => { void client.invalidateQueries() },
    }),
    defaultOptions: {
      queries: {
        refetchOnWindowFocus: 'always',
        refetchOnReconnect: 'always',
        refetchOnMount: 'always',
        refetchInterval: (query) => autoRefreshInterval(query.queryKey),
        retry: 1,
        staleTime: 30_000,
      },
      mutations: {
        retry: 0,
      },
    },
  })
  return client
}
