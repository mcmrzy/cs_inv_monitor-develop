export interface FirmwareUploadInput {
  file: File
  model: string
  targetChip: string
  hardwareVersions: string[]
  boardCodes?: string[]
  changelog?: string
}

/**
 * 固件技术元数据以服务端识别结果为准，前端只提交业务选择与文件本体。
 */
export function buildFirmwareUploadFormData(input: FirmwareUploadInput): FormData {
  const hardwareVersions = [...new Set((input.hardwareVersions ?? []).map((v) => v.trim().toUpperCase()).filter(Boolean))]
  const boardCodes = [...new Set((input.boardCodes ?? []).map(v => v.trim()).filter(Boolean))]
  if (hardwareVersions.length === 0 && boardCodes.length === 0) throw new Error('Explicit board compatibility is required')
  const formData = new FormData()
  formData.append('file', input.file)
  formData.append('model', input.model)
  formData.append('target_chip', input.targetChip)
  if (hardwareVersions.length) formData.append('hardware_versions', JSON.stringify(hardwareVersions))
  if (boardCodes.length) formData.append('board_codes', JSON.stringify(boardCodes))
  formData.append('changelog', input.changelog || '')
  return formData
}
