import { create } from 'zustand'

interface TimezoneState {
  timezone: string
  fetchTimezone: () => void
}

const useTimezoneStore = create<TimezoneState>()((set) => ({
  timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'Asia/Shanghai',
  fetchTimezone: () => {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'Asia/Shanghai'
    set({ timezone: tz })
  },
}))

export default useTimezoneStore
