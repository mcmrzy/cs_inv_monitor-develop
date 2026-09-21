import { bindAppUrl, parseDeviceBind, savePendingDeviceBind } from './utils/pendingDeviceBind'
import { tryOpenApp } from './pages/bind/openApp'

const bind = parseDeviceBind(window.location.search)
const status = document.getElementById('bind-status')!
const details = document.getElementById('bind-details')!
const openButton = document.getElementById('open-app') as HTMLButtonElement
const downloadButton = document.getElementById('download-app') as HTMLAnchorElement

if (!bind) {
  status.textContent = '设备二维码无效，请重新扫描设备铭牌上的二维码。'
  openButton.hidden = true
  downloadButton.hidden = true
} else {
  savePendingDeviceBind(bind)
  details.textContent = `设备 SN：${bind.sn}`
  const appUrl = bindAppUrl(bind)
  const download = () => window.location.replace('/download')
  let stopAttempt: (() => void) | undefined
  const openApp = () => {
    stopAttempt?.()
    stopAttempt = tryOpenApp(appUrl, download)
  }
  openButton.addEventListener('click', () => {
    status.textContent = '正在打开 App…'
    openApp()
  })
  downloadButton.href = '/download'

  if (/android|iphone|ipad|ipod/i.test(navigator.userAgent)) {
    // Keep the manual button for browsers that block automatic custom-scheme navigation.
    openApp()
  } else {
    status.textContent = '请用手机扫码打开此页面。'
  }
}
