/**
 * 曲线选择药丸开关（SeriesChip）。
 *
 * 为什么不用 antd Checkbox + 色块字符：那样每项会出现两个方块（勾选框 + 色块），
 * 且色块与勾选框不对齐，15 项铺开又散又吵。药丸开关把「选中态、颜色、实测/计算」
 * 三件事收在一个控件里：
 *  - 选中：实心圆点 + 该曲线颜色的描边与浅色底；未选：灰点 + 灰描边；
 *  - 计算功率：描边为虚线、圆点用方点，和曲线图里的虚线一一对应。
 */
import React from 'react'

import { DEBUG_TEXT, DEBUG_TITLE } from './debugTheme'

interface SeriesChipProps {
  label: string
  color: string
  active: boolean
  /** 派生（计算）曲线：虚线描边 + 方点 */
  derived?: boolean
  onToggle: () => void
}

const SeriesChip: React.FC<SeriesChipProps> = ({ label, color, active, derived = false, onToggle }) => (
  <button
    type="button"
    aria-pressed={active}
    onClick={onToggle}
    style={{
      display: 'inline-flex',
      alignItems: 'center',
      gap: 6,
      height: 28,
      padding: '0 12px',
      borderRadius: 999,
      cursor: 'pointer',
      font: 'inherit',
      fontSize: 13,
      lineHeight: 1,
      transition: 'border-color .15s, background-color .15s, color .15s',
      border: `1px ${derived ? 'dashed' : 'solid'} ${active ? color : '#d9d9d9'}`,
      background: active ? `${color}14` : '#fff',
      color: active ? DEBUG_TITLE : DEBUG_TEXT,
      fontWeight: active ? 600 : 400,
    }}
  >
    <span
      style={{
        width: 8,
        height: 8,
        flex: '0 0 auto',
        borderRadius: derived ? 2 : 999,
        background: active ? color : '#d9d9d9',
      }}
    />
    {label}
  </button>
)

export default SeriesChip
