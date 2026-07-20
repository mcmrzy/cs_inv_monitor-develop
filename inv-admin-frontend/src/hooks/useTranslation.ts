import { useCallback } from 'react'
import useLocaleStore from '@/stores/localeStore'
import locales from '@/locales'

const useTranslation = () => {
  const { lang } = useLocaleStore()
  const t = useCallback((key: string, params?: Record<string, string | number>): string => {
    let text = locales[lang][key] ?? key
    if (params) {
      Object.entries(params).forEach(([k, v]) => {
        text = text.replace(new RegExp(`{{${k}}}`, 'g'), String(v))
      })
    }
    return text
  }, [lang])
  const hasTranslation = useCallback(
    (key: string): boolean => Object.prototype.hasOwnProperty.call(locales[lang], key),
    [lang],
  )
  return { t, lang, hasTranslation }
}

export default useTranslation
