import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:8888',
        changeOrigin: true,
      },
    },
  },
  build: {
    target: 'es2020',
    chunkSizeWarningLimit: 1000,
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: false,
        drop_debugger: true,
        pure_funcs: undefined,
      },
      format: {
        comments: false,
      },
    },
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined
          if (id.includes('/echarts/') || id.includes('zrender/')) return 'vendor-charts'
          if (id.includes('/antd/') || id.includes('@ant-design') || id.includes('/rc-') || id.includes('rc-util')) return 'vendor-antd'
          if (id.includes('/react/') || id.includes('react-dom') || id.includes('react-router') || id.includes('@remix-run')) return 'vendor-react'
          if (id.includes('@tanstack') || id.includes('/axios/')) return 'vendor-data'
          if (id.includes('/leaflet/') || id.includes('react-leaflet')) return 'vendor-maps'
          if (id.includes('/dayjs/')) return 'vendor-utils'
          if (id.includes('rc-slider-captcha') || id.includes('create-puzzle')) return 'vendor-captcha'
          return undefined
        },
      },
    },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    css: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: ['node_modules/', 'src/test/'],
    },
  },
})
