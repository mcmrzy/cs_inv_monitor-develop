import React from 'react'
import ReactDOM from 'react-dom/client'
import { QueryClientProvider } from '@tanstack/react-query'
import dayjs from 'dayjs'
import 'dayjs/locale/zh-cn'
import App from './App'
import './global.css'
import { createAppQueryClient } from './utils/createAppQueryClient'

// 设置dayjs默认locale为中文
dayjs.locale('zh-cn')

const queryClient = createAppQueryClient()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <App />
    </QueryClientProvider>
  </React.StrictMode>,
)
