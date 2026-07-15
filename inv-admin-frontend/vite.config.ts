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
    rollupOptions: {
      output: {
        manualChunks(id) {
          const moduleId = id.replace(/\\/g, '/')
          if (!moduleId.includes('/node_modules/')) return undefined

          // ECharts and ZRender are large even with tree shaking. Keep their
          // independently cacheable subsystems separate instead of merging
          // them into one 1 MB vendor chunk.
          if (moduleId.includes('/zrender/')) return 'vendor-zrender'
          if (moduleId.includes('/echarts/lib/chart/') || moduleId.includes('/echarts/charts')) return 'vendor-echarts-charts'
          if (moduleId.includes('/echarts/lib/component/') || moduleId.includes('/echarts/components')) return 'vendor-echarts-components'
          if (moduleId.includes('/echarts/lib/renderer/') || moduleId.includes('/echarts/renderers')) return 'vendor-echarts-renderers'
          if (moduleId.includes('/echarts/')) return 'vendor-echarts-core'

          // Ant Design is split by subsystem. The old catch-all chunk also
          // absorbed every rc-* package and exceeded 1.3 MB minified.
          if (moduleId.includes('@ant-design/icons')) return 'vendor-antd-icons'
          if (moduleId.includes('@ant-design/cssinjs') || moduleId.includes('@ant-design/colors') || moduleId.includes('@ant-design/fast-color')) return 'vendor-antd-style'
          if (moduleId.includes('/rc-picker/') || moduleId.includes('/dayjs/')) return 'vendor-antd-date'
          if (moduleId.includes('/rc-table/')) return 'vendor-antd-table'
          if (moduleId.includes('/rc-field-form/')) return 'vendor-antd-form'
          if (/\/(rc-select|rc-tree|rc-cascader|rc-tree-select|rc-virtual-list)\//.test(moduleId)) return 'vendor-antd-select'
          if (/\/(rc-dialog|rc-menu|rc-dropdown|rc-tooltip|rc-motion|rc-notification)\//.test(moduleId)) return 'vendor-antd-overlay'

          const antdComponent = moduleId.match(/\/antd\/(?:es|lib)\/([^/]+)\//)?.[1]
          if (antdComponent) {
            if (/^(table|pagination|list|descriptions|tree|transfer)$/.test(antdComponent)) return 'vendor-antd-data'
            if (/^(date-picker|time-picker|calendar)$/.test(antdComponent)) return 'vendor-antd-picker'
            if (antdComponent === 'form') return 'vendor-antd-form-controls'
            if (/^(input|input-number|mentions)$/.test(antdComponent)) return 'vendor-antd-input'
            if (/^(select|cascader|tree-select)$/.test(antdComponent)) return 'vendor-antd-selection'
            if (/^(checkbox|radio|switch|slider|rate|color-picker)$/.test(antdComponent)) return 'vendor-antd-choices'
            if (antdComponent === 'upload') return 'vendor-antd-upload'
            if (/^(modal|message|notification|drawer|popover|popconfirm|tooltip|alert|progress|skeleton|spin|result)$/.test(antdComponent)) return 'vendor-antd-feedback'
            if (/^(menu|dropdown|tabs|steps|breadcrumb|anchor)$/.test(antdComponent)) return 'vendor-antd-navigation'
            if (/^(layout|grid|space|flex|divider|affix)$/.test(antdComponent)) return 'vendor-antd-layout'
            if (/^(card|statistic|tag|badge|avatar|typography|image|carousel|collapse)$/.test(antdComponent)) return 'vendor-antd-display'
            return 'vendor-antd-core'
          }
          if (moduleId.includes('/antd/')) return 'vendor-antd-core'
          if (moduleId.includes('/rc-')) return 'vendor-antd-rc'

          if (moduleId.includes('/react/') || moduleId.includes('react-dom') || moduleId.includes('react-router')) return 'vendor-react'
          if (moduleId.includes('@tanstack') || moduleId.includes('/axios/')) return 'vendor-data'
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
