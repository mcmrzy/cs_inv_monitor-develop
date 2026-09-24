import 'package:flutter_blue_ultra/flutter_blue_ultra.dart';

/// Android `writeCharacteristic` 回调会原样带回 AOSP 内部 GATT 状态码
/// （见 flutter_blue_ultra 的 gattErrorString 表）。其中下面三个属于
/// 「本地协议栈忙/拒绝启动」一族，是长写（prepare/execute 多步序列）场景下
/// 偶发的瞬时错误，重发同一帧即可：
///
///   132 GATT_BUSY、133 GATT_ERROR、134 GATT_CMD_STARTED
///
/// 设备侧真正的协议拒绝（offset 不连续、JSON 不合法等）走 ATT 错误码
/// （0x01-0x17），不在此列，调用方应原样上抛。
const Set<int> transientBleWriteCodes = {132, 133, 134};

/// 该写入失败是否属于可安全重发的瞬时错误。
///
/// 除 Android 栈的忙/拒绝外，还包含插件自身的等待超时（fbu-code: 1，
/// "Timed out after Ns"）：写的完成回调 15 秒没来，写是否落地**未知**。
/// 设备若已收到会推 ACK 进状态流，调用方据此决定跳过或原样重发。
bool isTransientBleWriteError(Object error) {
  if (error is! FlutterBlueUltraException) return false;
  final code = error.code;
  if (code != null && transientBleWriteCodes.contains(code)) return true;
  return isPluginWriteTimeout(error);
}

/// 插件层的等待超时（flutter_blue_ultra 的 fbpTimeout 抛出）。
bool isPluginWriteTimeout(FlutterBlueUltraException e) =>
    e.platform == ErrorPlatform.fbu &&
    (e.code == FbuErrorCode.timeout.index ||
        (e.description?.contains('Timed out after') ?? false));

/// 设备侧主动拒绝（ATT 应用层错误，Android 回传 1-17）时返回该错误码，
/// 否则返回 null。重试无意义——最常见的是 14 GATT_UNLIKELY：L10 固件在
/// ota.ctrl 里现场创建 6KB 栈的 OTA 工作任务，堆不足时 xTaskCreate 失败
/// 就回这个码；数据帧队列（深度 4）满、或上一次升级任务未退出也回它。
int? deviceAttErrorCodeOf(Object error) {
  if (error is! FlutterBlueUltraException) return null;
  // ATT 错误码只会经 Android 平台通道原样回传；fbu 平台的 code 是
  // FbuErrorCode 枚举（1 = timeout），不在 ATT 语义里。
  if (error.platform != ErrorPlatform.android) return null;
  final code = error.code;
  if (code == null || code < 1 || code > 17) return null;
  return code;
}

/// 把设备侧拒绝翻译成可操作的中文原因（供升级失败的提示语拼装）。
String deviceAttRefusalReason(int code) {
  switch (code) {
    case 14:
      return '设备端无法启动本次升级（内存不足，或上一次升级尚未结束）';
    case 13:
      return '设备认为该帧内容或长度不合法';
    case 9:
      return '设备端写缓冲已满';
    default:
      return '设备拒绝了这一帧（ATT 错误码 $code）';
  }
}
