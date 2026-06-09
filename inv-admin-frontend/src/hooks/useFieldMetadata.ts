import { useQuery } from '@tanstack/react-query'
import { modelApi, DeviceModelFieldItem } from '@/services/modelApi'
import type { FieldMeta } from '@/components/DynamicTable'

export function useFieldMetadata(modelCode: string | undefined) {
  const { data: modelList } = useQuery({
    queryKey: ['models'],
    queryFn: () => modelApi.listModels().then((res) => {
      const d = res.data
      return (Array.isArray(d?.data) ? d.data : (Array.isArray(d) ? d : [])) as any[]
    }),
    staleTime: 60000,
  })

  const modelId = modelList?.find((m) => m.model_code === modelCode)?.id

  const { data: fields = [], isLoading } = useQuery({
    queryKey: ['modelFields', modelId],
    queryFn: () =>
      modelApi.getFields(modelId!).then((res) => {
        const d = res.data
        return (Array.isArray(d?.data) ? d.data : (Array.isArray(d) ? d : [])) as DeviceModelFieldItem[]
      }),
    enabled: modelId != null,
    staleTime: 60000,
  })

  const fieldMetas: FieldMeta[] = fields
    .filter((f) => f.is_show)
    .map((f) => ({
      field_key: f.field_key,
      field_name: f.field_name,
      field_type: f.field_type,
      unit: f.unit,
      sort: f.sort,
      is_show: f.is_show,
    }))

  return { fields: fieldMetas, isLoading, modelId }
}
