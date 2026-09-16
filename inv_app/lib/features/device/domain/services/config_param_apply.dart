import 'package:dio/dio.dart';
import 'package:inv_app/core/utils/api_response.dart';

/// 远程设置写回：按 config-schema 的 param_key 逐条下发独立命令。
///
/// Web 管理端约定：
///   POST /devices/by-sn/{sn}/control
///   {"command": "<param_key>", "params": {"value": <工程单位值>}}
///
/// 旧实现把多个改动塞进 `set_params` + params 映射，在 L10 等型号上
/// 会因「命令不在允许列表 / 空 args schema 拒绝未知参数」失败。
Future<void> applyConfigParamWrites({
  required Dio dio,
  required String sn,
  required Map<String, dynamic> changes,
}) async {
  if (changes.isEmpty) return;
  for (final entry in changes.entries) {
    final response = await dio.post(
      '/devices/by-sn/$sn/control',
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
  }
}
