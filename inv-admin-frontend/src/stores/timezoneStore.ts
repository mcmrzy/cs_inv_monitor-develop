import { create } from 'zustand'
import useAuthStore from './authStore'

interface TimezoneState {
  timezone: string
  fetchTimezone: () => void
}

const useTimezoneStore = create<TimezoneState>()((set, get) => ({
  timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'Asia/Shanghai',
  fetchTimezone: () => {
    // 时区优先级：用户配置 > 浏览器检测 > 默认值
    const userTimezone = useAuthStore.getState().user?.timezone
    const browserTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone
    const tz = userTimezone || browserTimezone || 'Asia/Shanghai'
    set({ timezone: tz })
  },
}))

export default useTimezoneStore
