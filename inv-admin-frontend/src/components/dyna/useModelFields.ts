import { useState, useEffect, useCallback } from 'react'
import type { DeviceModelItem, DeviceModelFieldItem } from '@/services/modelApi'
import { modelApi } from '@/services/modelApi'

export interface ModelFieldsCache {
  modelId: number
  model: DeviceModelItem | null
  fields: DeviceModelFieldItem[]
  showFields: DeviceModelFieldItem[]
  controlFields: DeviceModelFieldItem[]
}

export function useModelFields(deviceModel: string | undefined, modelId?: number) {
  const [cache, setCache] = useState<ModelFieldsCache | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchFields = useCallback(async (modelCode: string, mId?: number) => {
    setLoading(true)
    setError(null)
    try {
      let matchedId: number | null = null
      let matched: DeviceModelItem | null = null

      // 优先使用 model_id 直接查询
      if (mId && mId > 0) {
        matchedId = mId
      } else if (modelCode) {
        // Fallback: 字符串匹配（增加 toLowerCase 容错）
        // 使用 listModelsPublic 而非 listModels，避免终端用户因缺少 admin:manage 权限而无法获取型号列表
        const modelsRes = await modelApi.listModelsPublic()
        const models: DeviceModelItem[] =
          modelsRes.data?.data ?? modelsRes.data ?? []

        matched = models.find(
          (m) => m.model_code?.toLowerCase() === modelCode.toLowerCase() ||
                 m.model_name?.toLowerCase() === modelCode.toLowerCase(),
        ) ?? null

        if (!matched) {
          setCache(null)
          setError(`未找到型号 ${modelCode} 的配置`)
          return
        }
        matchedId = matched.id
      }

      if (!matchedId) {
        setCache(null)
        return
      }

      const fieldsRes = await modelApi.getFields(matchedId)
      const allFields: DeviceModelFieldItem[] =
        fieldsRes.data?.data ?? fieldsRes.data ?? []

      const sortedFields = [...allFields].sort((a, b) => (a.sort ?? 0) - (b.sort ?? 0))
      const showFields = sortedFields.filter((f) => f.is_show)
      const controlFields = sortedFields.filter((f) => f.is_control)

      setCache({
        modelId: matchedId,
        model: matched,
        fields: sortedFields,
        showFields,
        controlFields,
      })
    } catch {
      setError('获取型号字段配置失败')
      setCache(null)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    if ((deviceModel && deviceModel !== '-') || (modelId && modelId > 0)) {
      fetchFields(deviceModel ?? '', modelId)
    } else {
      setCache(null)
    }
  }, [deviceModel, modelId, fetchFields])

  return { cache, loading, error, refetch: () => fetchFields(deviceModel ?? '', modelId) }
}

export { type DeviceModelFieldItem as ModelField }
