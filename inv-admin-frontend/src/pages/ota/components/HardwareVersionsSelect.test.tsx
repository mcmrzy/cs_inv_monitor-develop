import { useState } from 'react'
import { describe, it, expect } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { API_BASE } from '@/utils/urls'
import { renderAsAdmin, renderWithProviders } from '@/test/test-utils'
import { mockManagerUser } from '@/test/mocks/data'
import HardwareVersionsSelect from './HardwareVersionsSelect'

function Selector() {
  const [value, setValue] = useState<string[]>([])
  return <><HardwareVersionsSelect model="L10" value={value} onChange={setValue} /><output>{value.join(',')}</output></>
}

describe('hardware directory selection', () => {
  it('offers explicit directory versions as a multi-select', async () => {
    server.use(http.get(`${API_BASE}/ota/hardware-versions`, ({ request }) => {
      expect(new URL(request.url).searchParams.get('model')).toBe('L10')
      return HttpResponse.json({ code: 0, data: [{ model: 'L10', version: 'HW-1' }, { model: 'L10', version: 'HW-2' }] })
    }))
    renderAsAdmin(<Selector />)
    fireEvent.mouseDown(screen.getByRole('combobox'))
    fireEvent.click(await screen.findByText('HW-1', { selector: '.ant-select-item-option-content' }))
    fireEvent.click(await screen.findByText('HW-2', { selector: '.ant-select-item-option-content' }))
    expect(screen.getByText('HW-1,HW-2')).toBeInTheDocument()
  })
  it('allows an administrator to add a version to the selected model', async () => {
    let added: any
    server.use(
      http.get(`${API_BASE}/ota/hardware-versions`, () => HttpResponse.json({ code: 0, data: added ? [added] : [] })),
      http.post(`${API_BASE}/ota/hardware-versions`, async ({ request }) => {
        added = await request.json()
        return HttpResponse.json({ code: 0, data: added })
      }),
    )
    renderAsAdmin(<Selector />)
    fireEvent.click(screen.getByRole('button', { name: /新增硬件版本/ }))
    fireEvent.change(await screen.findByPlaceholderText('HW-1.0'), { target: { value: ' hw-3 ' } })
    fireEvent.click(screen.getByRole('button', { name: /确.*定/ }))
    await waitFor(() => expect(added).toMatchObject({ model: 'L10', version: 'HW-3' }))
    expect(await screen.findByText('HW-3', { selector: 'output' })).toBeInTheDocument()
  })
  it('does not offer creation to a non-administrator', () => {
    server.use(http.get(`${API_BASE}/ota/hardware-versions`, () => HttpResponse.json({ code: 0, data: [] })))
    renderWithProviders(<Selector />, { initialUser: mockManagerUser, initialToken: 'token', initialPermissions: ['ota:create'] })
    expect(screen.queryByRole('button', { name: /新增硬件版本/ })).not.toBeInTheDocument()
  })
})
