import { create } from 'zustand'
import { persist } from 'zustand/middleware'

export type Lang = 'zh' | 'en'

interface LocaleState {
  lang: Lang
  setLang: (lang: Lang) => void
}

const useLocaleStore = create<LocaleState>()(
  persist(
    (set) => ({
      lang: (navigator.language.startsWith('zh') ? 'zh' : 'en') as Lang,
      setLang: (lang) => set({ lang }),
    }),
    { name: 'locale-storage' },
  ),
)

export default useLocaleStore
