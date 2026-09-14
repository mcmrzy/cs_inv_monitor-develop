export interface FirmwareUploadInput {
  file: File
  model: string
  targetChip: string
  changelog?: string
}

/**
 * 固件技术元数据以服务端识别结果为准，前端只提交业务选择与文件本体。
 */
export function buildFirmwareUploadFormData(input: FirmwareUploadInput): FormData {
  const formData = new FormData()
  formData.append('file', input.file)
  formData.append('model', input.model)
  formData.append('target_chip', input.targetChip)
  formData.append('changelog', input.changelog || '')
  return formData
}
