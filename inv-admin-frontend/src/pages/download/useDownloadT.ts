import { useCallback } from 'react'
import useLocaleStore from '@/stores/localeStore'
import download from '@/locales/download'

/**
 * 下载页专用文案 hook：只加载 download 词典，不拉全站 locales，
 * 供独立入口（download.html）与管理后台路由共用。
 */
const useDownloadT = () => {
  const { lang } = useLocaleStore()
  const t = useCallback(
    (key: string, params?: Record<string, string | number>): string => {
      const dict = download[lang] as Record<string, string>
      let text = dict[key] ?? key
      if (params) {
        Object.entries(params).forEach(([k, v]) => {
          text = text.replace(new RegExp(`{{${k}}}`, 'g'), String(v))
        })
      }
      return text
    },
    [lang],
  )
  return { t, lang }
}

export default useDownloadT
