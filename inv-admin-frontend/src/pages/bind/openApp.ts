/** Browser pages cannot query installed apps. A backgrounded page is the only
 * useful signal that the custom scheme opened an app or a system prompt. */
export function tryOpenApp(
  appUrl: string,
  fallback: () => void,
  browser: Window = window,
  page: Document = document,
  launch: (url: string) => void = (url) => { browser.location.href = url },
): () => void {
  let finished = false
  const cleanup = () => {
    browser.clearTimeout(timer)
    page.removeEventListener('visibilitychange', onVisibilityChange)
    browser.removeEventListener('pagehide', onPageHide)
  }
  const onPageHide = () => {
    finished = true
    cleanup()
  }
  const onVisibilityChange = () => {
    if (page.hidden) onPageHide()
  }
  page.addEventListener('visibilitychange', onVisibilityChange)
  browser.addEventListener('pagehide', onPageHide)
  const timer = browser.setTimeout(() => {
    cleanup()
    if (!finished && !page.hidden) fallback()
  }, 2500)
  try {
    launch(appUrl)
  } catch {
    cleanup()
    fallback()
  }
  return cleanup
}
