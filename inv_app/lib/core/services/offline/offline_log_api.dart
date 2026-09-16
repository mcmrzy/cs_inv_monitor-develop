import 'package:dio/dio.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';

enum OfflineLogItemStatus { accepted, duplicate, rejected }

class OfflineLogItemResult {
  final String logId;
  final OfflineLogItemStatus status;
  final String? reason;

  const OfflineLogItemResult({
    required this.logId,
    required this.status,
    this.reason,
  });

  static OfflineLogItemResult? fromJson(Map<String, dynamic> json) {
    final logId = json['log_id'];
    final rawStatus = json['status'];
    if (logId is! String || logId.isEmpty || rawStatus is! String) {
      return null;
    }
    final status = switch (rawStatus) {
      'accepted' => OfflineLogItemStatus.accepted,
      'duplicate' => OfflineLogItemStatus.duplicate,
      'rejected' => OfflineLogItemStatus.rejected,
      _ => null,
    };
    if (status == null) return null;
    return OfflineLogItemResult(
      logId: logId,
      status: status,
      reason: json['reason'] as String?,
    );
  }
}

/// 离线日志上传结果（设计文档 §4.3）
class OfflineLogUploadResult {
  final int accepted;
  final int duplicates;
  final int rejected;
  final List<OfflineLogItemResult> results;
  final bool itemResultsPresent;

  const OfflineLogUploadResult({
    required this.accepted,
    required this.duplicates,
    this.rejected = 0,
    this.results = const [],
    this.itemResultsPresent = false,
  });

  bool get hasItemResults => itemResultsPresent || results.isNotEmpty;
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
    final rawResults = data['results'];
    final results = rawResults is List
        ? rawResults
            .whereType<Map>()
            .map((item) => OfflineLogItemResult.fromJson(
                  item.cast<String, dynamic>(),
                ))
            .whereType<OfflineLogItemResult>()
            .toList(growable: false)
        : const <OfflineLogItemResult>[];
    return OfflineLogUploadResult(
      accepted: (data['accepted'] as num?)?.toInt() ?? 0,
      duplicates: (data['duplicates'] as num?)?.toInt() ?? 0,
      rejected: (data['rejected'] as num?)?.toInt() ?? 0,
      results: results,
      itemResultsPresent: rawResults is List,
    );
  }
}
