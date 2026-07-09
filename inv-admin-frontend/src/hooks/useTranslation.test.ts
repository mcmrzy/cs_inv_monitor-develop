import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook } from '@testing-library/react'
import useTranslation from './useTranslation'
import useLocaleStore from '@/stores/localeStore'

describe('useTranslation', () => {
  beforeEach(() => {
    useLocaleStore.setState({ lang: 'zh' })
  })

  it('should return translation for zh locale', () => {
    const { result } = renderHook(() => useTranslation())

    expect(result.current.t('common.search')).toBe('搜索')
    expect(result.current.t('common.refresh')).toBe('刷新')
    expect(result.current.t('common.delete')).toBe('删除')
  })

  it('should return translation for en locale', () => {
    useLocaleStore.setState({ lang: 'en' })

    const { result } = renderHook(() => useTranslation())

    expect(result.current.t('common.search')).toBe('Search')
    expect(result.current.t('common.refresh')).toBe('Refresh')
    expect(result.current.t('common.delete')).toBe('Delete')
  })

  it('should return key when translation is missing', () => {
    const { result } = renderHook(() => useTranslation())

    expect(result.current.t('nonexistent.key')).toBe('nonexistent.key')
  })

  it('should support parameter interpolation', () => {
    const { result } = renderHook(() => useTranslation())

    const text = result.current.t('common.total', { total: 42 })
    expect(text).toBe('共 42 条')
  })

  it('should support parameter interpolation in English', () => {
    useLocaleStore.setState({ lang: 'en' })

    const { result } = renderHook(() => useTranslation())

    const text = result.current.t('common.total', { total: 42 })
    expect(text).toBe('Total 42 items')
  })

  it('should return current lang', () => {
    const { result } = renderHook(() => useTranslation())

    expect(result.current.lang).toBe('zh')
  })

  it('should return en lang when switched', () => {
    useLocaleStore.setState({ lang: 'en' })

    const { result } = renderHook(() => useTranslation())

    expect(result.current.lang).toBe('en')
  })

  it('should translate device-related keys', () => {
    const { result } = renderHook(() => useTranslation())

    expect(result.current.t('common.deviceSN')).toBe('设备SN')
    expect(result.current.t('common.model')).toBe('型号')
  })

  it('should translate status-related keys', () => {
    const { result } = renderHook(() => useTranslation())

    expect(result.current.t('common.online')).toBe('在线')
    expect(result.current.t('common.offline')).toBe('离线')
    expect(result.current.t('common.fault')).toBe('故障')
  })

  it('should translate batch operation keys', () => {
    const { result } = renderHook(() => useTranslation())

    const text = result.current.t('common.selectedDevicesCount', { count: 5 })
    expect(text).toBe('已选设备: 5 台')
  })
})
