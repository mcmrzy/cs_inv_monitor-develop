import { describe, it, expect, beforeEach } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import useAuthStore from '@/stores/authStore'
import ModelRegistryWorkspace from './model_registry_workspace'

const API_BASE = '/api/v1'

/** Default happy-path handlers for ModelRegistryWorkspace */
function setupDefaultHandlers() {
  server.use(
    http.get(`${API_BASE}/models`, () =>
      HttpResponse.json({
        code: 0,
        message: 'success',
        data: [
          { id: 1, model_code: 'SG-5K-D', model_name: 'SG-5K-D', manufacturer: 'CSERGY', category: 'inverter', rated_power_kw: 5, is_active: true, device_count: 10 },
          { id: 2, model_code: 'SG-10K-D', model_name: 'SG-10K-D', manufacturer: 'CSERGY', category: 'inverter', rated_power_kw: 10, is_active: false, device_count: 3 },
        ],
      }),
    ),
    http.get(`${API_BASE}/field-catalog`, () =>
      HttpResponse.json({
        code: 0,
        message: 'success',
        data: [
          { field_key: 'ac_voltage', field_type: 'float', category: 'ac', base_unit: 'V', is_timeseries: true, is_aggregatable: true, allowed_aggregates: ['avg', 'min', 'max'], status: 'active' },
        ],
      }),
    ),
    http.get(`${API_BASE}/protocol-versions`, () =>
      HttpResponse.json({
        code: 0,
        message: 'success',
        data: [
          { id: 1, protocol_code: 'heartbeat', version: 1, schema_hash: 'abc123', status: 'released', field_count: 20, released_at: '2026-06-01T00:00:00Z' },
        ],
      }),
    ),
  )
}

describe('ModelRegistryWorkspace', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
    setupDefaultHandlers()
  })

  // ── English mode ──────────────────────────────────────────────────────────

  it('renders page title and tab labels in English', async () => {
    renderAsAdmin(<ModelRegistryWorkspace />, { lang: 'en' })

    // Page title
    expect(await screen.findByText('Model & Protocol Governance')).toBeInTheDocument()

    // Tab labels
    await waitFor(() => {
      expect(screen.getByText(/Model Registry/)).toBeInTheDocument()
      expect(screen.getByText(/Standard Field Dictionary/)).toBeInTheDocument()
      expect(screen.getByText(/Protocol Versions/)).toBeInTheDocument()
    })
  })

  it('renders table column headers in English', async () => {
    renderAsAdmin(<ModelRegistryWorkspace />, { lang: 'en' })

    await waitFor(() => {
      // Model table column headers
      expect(screen.getByText('Model Code')).toBeInTheDocument()
      expect(screen.getByText('Model Name')).toBeInTheDocument()
      expect(screen.getByText('Manufacturer')).toBeInTheDocument()
      expect(screen.getByText('Category')).toBeInTheDocument()
      expect(screen.getByText('Rated Power')).toBeInTheDocument()
      expect(screen.getByText('Device Count')).toBeInTheDocument()
      expect(screen.getByText('Status')).toBeInTheDocument()
      expect(screen.getByText('Actions')).toBeInTheDocument()
    })
  })

  it('renders model data rows in English mode', async () => {
    renderAsAdmin(<ModelRegistryWorkspace />, { lang: 'en' })

    await waitFor(() => {
      // model_code and model_name are both 'SG-5K-D', so use getAllByText
      expect(screen.getAllByText('SG-5K-D').length).toBe(2)
      expect(screen.getAllByText('SG-10K-D').length).toBe(2)
    })
  })

  // ── Chinese mode ──────────────────────────────────────────────────────────

  it('renders page title and tab labels in Chinese', async () => {
    renderAsAdmin(<ModelRegistryWorkspace />, { lang: 'zh' })

    expect(await screen.findByText('型号与协议治理')).toBeInTheDocument()

    await waitFor(() => {
      expect(screen.getByText(/型号注册/)).toBeInTheDocument()
      expect(screen.getByText(/标准字段字典/)).toBeInTheDocument()
      // Use exact text to avoid matching the subtitle which also contains '协议版本'
      const tabLabels = screen.getAllByText(/协议版本/)
      expect(tabLabels.length).toBeGreaterThanOrEqual(1)
    })
  })

  it('renders table column headers in Chinese', async () => {
    renderAsAdmin(<ModelRegistryWorkspace />, { lang: 'zh' })

    await waitFor(() => {
      expect(screen.getByText('型号编码')).toBeInTheDocument()
      expect(screen.getByText('型号名称')).toBeInTheDocument()
      expect(screen.getByText('厂商')).toBeInTheDocument()
      expect(screen.getByText('类别')).toBeInTheDocument()
      expect(screen.getByText('额定功率')).toBeInTheDocument()
      expect(screen.getByText('设备数')).toBeInTheDocument()
      expect(screen.getByText('状态')).toBeInTheDocument()
      expect(screen.getByText('操作')).toBeInTheDocument()
    })
  })

  // ── Error state ───────────────────────────────────────────────────────────

  it('shows English error alert when model list API fails', async () => {
    server.use(
      http.get(`${API_BASE}/models`, () =>
        HttpResponse.json({ code: 500, message: 'internal server error' }, { status: 500 }),
      ),
    )

    renderAsAdmin(<ModelRegistryWorkspace />, { lang: 'en' })

    await waitFor(() => {
      // English error title
      expect(screen.getByText('Failed to load model configuration data')).toBeInTheDocument()
      // Reload button in English
      expect(screen.getByText('Reload')).toBeInTheDocument()
    })
  })

  it('shows Chinese error alert when model list API fails', async () => {
    server.use(
      http.get(`${API_BASE}/models`, () =>
        HttpResponse.json({ code: 500, message: 'internal server error' }, { status: 500 }),
      ),
    )

    renderAsAdmin(<ModelRegistryWorkspace />, { lang: 'zh' })

    await waitFor(() => {
      expect(screen.getByText('型号配置数据加载失败')).toBeInTheDocument()
      expect(screen.getByText('重新加载')).toBeInTheDocument()
    })
  })

  // ── Empty data state ──────────────────────────────────────────────────────

  it('renders empty table when model list is empty (English)', async () => {
    server.use(
      http.get(`${API_BASE}/models`, () =>
        HttpResponse.json({ code: 0, message: 'success', data: [] }),
      ),
    )

    renderAsAdmin(<ModelRegistryWorkspace />, { lang: 'en' })

    await waitFor(() => {
      const empty = document.querySelector('.ant-empty')
      expect(empty).toBeInTheDocument()
    })
  })

  it('renders empty table when model list is empty (Chinese)', async () => {
    server.use(
      http.get(`${API_BASE}/models`, () =>
        HttpResponse.json({ code: 0, message: 'success', data: [] }),
      ),
    )

    renderAsAdmin(<ModelRegistryWorkspace />, { lang: 'zh' })

    await waitFor(() => {
      const empty = document.querySelector('.ant-empty')
      expect(empty).toBeInTheDocument()
    })
  })
})
