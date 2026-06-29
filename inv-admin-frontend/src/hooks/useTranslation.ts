import useLocaleStore from '@/stores/localeStore'
import locales from '@/locales'

const useTranslation = () => {
  const { lang } = useLocaleStore()
  const t = (key: string, params?: Record<string, string | number>): string => {
    let text = locales[lang][key] ?? key
    if (params) {
      Object.entries(params).forEach(([k, v]) => {
        text = text.replace(new RegExp(`{{${k}}}`, 'g'), String(v))
      })
    }
    return text
  }
  return { t, lang }
}

export default useTranslation
