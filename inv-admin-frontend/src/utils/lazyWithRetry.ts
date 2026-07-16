import { lazy, ComponentType } from 'react'

/**
 * 动态导入失败自动重试
 * 解决部署更新后旧 chunk hash 不匹配导致的 "Failed to fetch dynamically imported module" 错误
 */
function lazyWithRetry<T extends ComponentType<any>>(
  importFn: () => Promise<{ default: T }>,
  retries = 2,
  delay = 1000
) {
  return lazy(() => {
    const attempt = (remaining: number): Promise<{ default: T }> =>
      importFn().catch((err: Error) => {
        if (remaining <= 0) {
          // 最终失败：强制刷新页面以获取最新 HTML
          if (typeof window !== 'undefined') {
            window.location.reload()
          }
          throw err
        }
        return new Promise<{ default: T }>((resolve) =>
          setTimeout(() => resolve(attempt(remaining - 1)), delay)
        )
      })
    return attempt(retries)
  })
}

export default lazyWithRetry
