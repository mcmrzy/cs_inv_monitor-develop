import { describe, expect, it } from 'vitest'
import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderAsAdmin } from '@/test/test-utils'
import AdminPage from './index'

describe('AdminPage role permission contract', () => {
  it('offers permission editing for every database role including installer and end user', async () => {
    const user = userEvent.setup()
    renderAsAdmin(<AdminPage />)

    await user.click(screen.getByRole('tab', { name: '权限配置' }))
    await user.click(screen.getByRole('combobox'))

    for (const roleName of ['超级管理员', '管理员', '运营商', '经销商', '安装商', '终端用户']) {
      expect(await screen.findByRole('option', { name: roleName })).toBeInTheDocument()
    }
  })
})
