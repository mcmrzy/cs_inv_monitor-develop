import 'package:dio/dio.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';

/// 离线日志上传结果（设计文档 §4.3）
class OfflineLogUploadResult {
  final int accepted;
  final int duplicates;

  const OfflineLogUploadResult({
    required this.accepted,
    required this.duplicates,
  });
}

/// 离线日志上报接口（抽象，便于测试替换）
abstract class OfflineLogApi {
  Future<OfflineLogUploadResult> upload(List<OfflineOpLog> logs);
}

/// Dio 实现：POST /devices/offline-logs（需登录，JWT 由 Dio 拦截器注入）
///
/// 与项目响应惯例一致：`{code, message, data}`，`code == 0` 视为成功；
/// 业务失败（code != 0）时抛出异常，由上层同步服务走失败重试路径。
class DioOfflineLogApi implements OfflineLogApi {
  DioOfflineLogApi(this._dio);

  final Dio _dio;

  @override
  Future<OfflineLogUploadResult> upload(List<OfflineOpLog> logs) async {
    final response = await _dio.post(
      '/devices/offline-logs',
      data: {'logs': logs.map((log) => log.toJson()).toList()},
    );
    final body = response.data as Map<String, dynamic>;
    if (body['code'] != 0) {
      throw Exception(
        body['message'] ?? 'Offline log upload failed (code=${body['code']})',
      );
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? const {};
    return OfflineLogUploadResult(
      accepted: (data['accepted'] as num?)?.toInt() ?? 0,
      duplicates: (data['duplicates'] as num?)?.toInt() ?? 0,
    );
  }
}
