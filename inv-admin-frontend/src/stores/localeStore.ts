import { create } from 'zustand'
import { persist } from 'zustand/middleware'

export type Lang = 'zh' | 'en'

interface LocaleState {
  lang: Lang
  setLang: (lang: Lang) => void
}

const detectBrowserLanguage = (): Lang => {
  if (typeof navigator === 'undefined') return 'zh'
  return navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en'
}

const isLang = (value: unknown): value is Lang => value === 'zh' || value === 'en'

const useLocaleStore = create<LocaleState>()(
  persist(
    (set) => ({
      lang: detectBrowserLanguage(),
      setLang: (lang) => set({ lang }),
    }),
    {
      name: 'locale-storage',
      merge: (persisted, current) => {
        const saved = persisted as Partial<LocaleState> | undefined
        return { ...current, ...saved, lang: isLang(saved?.lang) ? saved.lang : current.lang }
      },
    },
  ),
)

export default useLocaleStore
