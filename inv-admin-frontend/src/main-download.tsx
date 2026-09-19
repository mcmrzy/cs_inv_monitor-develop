import React from 'react'
import ReactDOM from 'react-dom/client'
import DownloadPage from './pages/download'
import './global.css'

/**
 * 下载页独立入口（download.html）。
 * 只打包 DownloadPage + React，不引入管理后台路由 / antd 布局 / 全站 locales，
 * 显著降低手机浏览器首屏请求数与 JS 体积。
 */
ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <DownloadPage />
  </React.StrictMode>,
)
