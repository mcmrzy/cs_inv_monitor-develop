/// OTA 相关异常类型定义
///
/// 本地 OTA 三条链路（WiFi AP / BLE / 云端轮询）共用的错误分类，
/// UI 层通过 [OtaErrorMapper.l10nKeyOf] 将异常映射为本地化文案 key，
/// 并可按类型做差异化恢复（如连接断开→自动重连、签名校验失败→终止重试）。
class DeviceConnectionException implements Exception {
  final String message;
  DeviceConnectionException(this.message);
  @override
  String toString() => message;
}

/// 本地固件相关异常（文件缺失/损坏等）
class LocalFirmwareException implements Exception {
  final String message;
  LocalFirmwareException(this.message);
  @override
  String toString() => message;
}

/// 固件目标型号与当前近场连接设备无法确认一致。
///
/// 该异常在上传任何字节前产生；固件/设备型号缺失或不匹配均按 fail-closed
/// 处理，避免把错误固件发送给设备。
class LocalOtaDeviceModelException implements Exception {
  final String message;
  LocalOtaDeviceModelException(this.message);
  @override
  String toString() => message;
}

/// The connected BLE device does not advertise this module for local OTA.
class LocalOtaUnsupportedTargetException implements Exception {
  final String target;
  LocalOtaUnsupportedTargetException(this.target);
  @override
  String toString() => 'Unsupported local OTA target: $target';
}

/// The device cannot stage this image in its current cache partition.
class OtaInsufficientStorageException implements Exception {
  final String diagnostic;
  OtaInsufficientStorageException(this.diagnostic);
  @override
  String toString() => diagnostic;
}

/// 设备拒绝固件上传（HTTP 非 2xx / 设备端返回错误）
class OtaUploadRejectedException implements Exception {
  final String message;
  OtaUploadRejectedException(this.message);
  @override
  String toString() => message;
}

/// 升级超时 / 进度停滞（假死）
class OtaTimeoutException implements Exception {
  final String message;
  OtaTimeoutException(this.message);
  @override
  String toString() => message;
}

/// 固件完整性/签名校验失败
class OtaVerificationException implements Exception {
  final String message;
  OtaVerificationException(this.message);
  @override
  String toString() => message;
}

/// 设备响应无法解析（协议错误）
class OtaProtocolException implements Exception {
  final String message;
  OtaProtocolException(this.message);
  @override
  String toString() => message;
}

/// OTA 异常 → l10n key 映射器。
///
/// UI 层不应直接展示 `e.toString()`，而应通过此映射取本地化文案，
/// 需要携带详情时使用 `ota_err_unknown` 的 {error} 参数。
class OtaErrorMapper {
  OtaErrorMapper._();

  /// 返回异常对应的 l10n 文案 key
  static String l10nKeyOf(Object error) {
    if (error is DeviceConnectionException) return 'ota_err_connection';
    if (error is OtaTimeoutException) return 'ota_err_timeout';
    if (error is OtaUploadRejectedException) return 'ota_err_upload_rejected';
    if (error is OtaVerificationException) return 'ota_err_verify';
    if (error is LocalFirmwareException) return 'ota_err_firmware';
    if (error is LocalOtaDeviceModelException) return 'ota_err_device_model';
    if (error is LocalOtaUnsupportedTargetException) {
      return 'ota_err_unsupported_target';
    }
    if (error is OtaInsufficientStorageException) {
      return 'ota_err_insufficient_storage';
    }
    if (error is OtaProtocolException) return 'ota_err_protocol';
    return 'ota_err_unknown';
  }

  /// 是否需要携带原始错误信息作为 {error} 参数
  static bool carriesDetail(Object error) =>
      l10nKeyOf(error) == 'ota_err_unknown';
}
