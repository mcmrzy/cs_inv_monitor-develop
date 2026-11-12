import 'package:dio/dio.dart';
import 'package:inv_app/core/utils/api_response.dart';

/// 远程设置写回：按 config-schema 的 param_key 逐条下发独立命令。
///
/// Web 管理端约定：
///   POST /devices/by-sn/{sn}/control
///   `{"command": "<param_key>", "params": {"value": <工程单位值>}}`
///
/// 旧实现把多个改动塞进 `set_params` + params 映射，在 L10 等型号上
/// 会因「命令不在允许列表 / 空 args schema 拒绝未知参数」失败。
Future<void> applyConfigParamWrites({
  required Dio dio,
  required String sn,
  required Map<String, dynamic> changes,
  bool verifyReadback = false,
  bool Function()? isActive,
}) async {
  if (changes.isEmpty) return;
  for (final entry in changes.entries) {
    if (isActive?.call() == false) return;
    final response = await dio.post(
      '/devices/by-sn/${Uri.encodeComponent(sn)}/control',
      data: {
        'command': entry.key,
        'params': {'value': entry.value},
      },
    );
    final data = unwrapApiResponse<Map<String, dynamic>>(
      response.data,
      validate: (value) =>
          value is Map<String, dynamic> &&
          (value['task_id'] is String || value['task_id'] is num),
      expected: 'an object containing task_id',
    );
    final taskId = data['task_id'];
    if (taskId is! String && taskId is! num) {
      throw const FormatException('missing task_id');
    }
    if (verifyReadback) {
      await _waitForReadback(dio, sn, taskId.toString(), isActive);
    }
  }
}

/// An accepted transport request becomes verified only after a device readback.
Future<void> _waitForReadback(
  Dio dio,
  String sn,
  String taskId,
  bool Function()? isActive,
) async {
  final timer = Stopwatch()..start();
  while (timer.elapsed < const Duration(seconds: 35)) {
    if (isActive?.call() == false) return;
    final response = await dio.get(
      '/devices/by-sn/${Uri.encodeComponent(sn)}/commands',
      queryParameters: {'page': 1, 'page_size': 100},
    );
    final data = unwrapApiResponse<Map<String, dynamic>>(
      response.data,
      validate: (value) => value is Map<String, dynamic>,
      expected: 'command history',
    );
    final records = data['items'];
    if (records is! List) {
      throw const FormatException('missing command records');
    }
    for (final record in records) {
      if (record is! Map || record['task_id'].toString() != taskId) continue;
      final status = record['status'];
      final result = record['data'];
      final stage = result is Map ? result['stage'] : null;
      if (const {'failed', 'timeout', 'cancelled'}.contains(status)) {
        throw ApiBusinessException(
          1,
          record['result_message'] is String
              ? record['result_message'] as String
              : 'Device rejected the command',
        );
      }
      if (status == 'submitted' || stage == 'submitted') {
        throw const ApiBusinessException(
          1,
          'Device accepted the command. Readback is unconfirmed.',
        );
      }
      if ((status == 'success' || status == 'applied') && stage == 'applied') {
        return;
      }
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw const ApiBusinessException(1, 'Device readback timed out.');
}
