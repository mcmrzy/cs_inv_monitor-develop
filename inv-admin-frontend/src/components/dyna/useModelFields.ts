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

export function useModelFields(deviceModel: string | undefined) {
  const [cache, setCache] = useState<ModelFieldsCache | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchFields = useCallback(async (modelCode: string) => {
    setLoading(true)
    setError(null)
    try {
      // 使用 listModelsPublic 而非 listModels，避免终端用户因缺少 admin:manage 权限而无法获取型号列表
      const modelsRes = await modelApi.listModelsPublic()
      const models: DeviceModelItem[] =
        modelsRes.data?.data ?? modelsRes.data ?? []

      const matched = models.find(
        (m) => m.model_code === modelCode || m.model_name === modelCode,
      )

      if (!matched) {
        setCache(null)
        setError(`未找到型号 ${modelCode} 的配置`)
        return
      }

      const fieldsRes = await modelApi.getFields(matched.id)
      const allFields: DeviceModelFieldItem[] =
        fieldsRes.data?.data ?? fieldsRes.data ?? []

      const sortedFields = [...allFields].sort((a, b) => (a.sort ?? 0) - (b.sort ?? 0))
      const showFields = sortedFields.filter((f) => f.is_show)
      const controlFields = sortedFields.filter((f) => f.is_control)

      setCache({
        modelId: matched.id,
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
    if (deviceModel && deviceModel !== '-') {
      fetchFields(deviceModel)
    } else {
      setCache(null)
    }
  }, [deviceModel, fetchFields])

  return { cache, loading, error, refetch: () => deviceModel && fetchFields(deviceModel) }
}

export { type DeviceModelFieldItem as ModelField }
