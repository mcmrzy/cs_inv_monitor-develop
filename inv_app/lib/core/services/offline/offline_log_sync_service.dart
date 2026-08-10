import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/offline/offline_log_api.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';

/// 离线操作日志同步服务（设计文档 §3.5）
///
/// - 触发：网络恢复事件 / App 启动（start）/ 手动 syncNow
/// - 批次 ≤50 条；失败按指数退避重试（30s/1min/5min/15min/60min 封顶）
/// - 单条重试 5 次后标记 failed，等待手动重试
class OfflineLogSyncService {
  OfflineLogSyncService({
    required this.store,
    required this.api,
    required this.networkStatus,
  });

  final OfflineOpLogStore store;
  final OfflineLogApi api;
  final NetworkStatusService networkStatus;

  /// 指数退避序列（与协议无关，纯客户端策略）
  static const List<Duration> backoffSteps = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 60),
  ];

  static const int maxAttempts = 5;
  static const int batchSize = 50;

  Timer? _retryTimer;
  StreamSubscription<bool>? _netSub;
  bool _started = false;
  bool _syncing = false; // 同步互斥：多触发源并发时仅执行一轮

  /// 是否有退避重试在等待（测试断言用）
  bool get hasPendingRetry => _retryTimer?.isActive ?? false;

  /// 启动：监听网络恢复事件并立即尝试一次
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _netSub = networkStatus.statusStream
        .where((online) => online)
        .listen((_) {
      _retryTimer?.cancel();
      syncNow();
    });
    await syncNow();
  }

  /// 立即同步一轮（可手动触发）
  ///
  /// 互斥：网络恢复事件 / 退避重试 / 手动触发 / 启动可能并发，
  /// 重叠时直接跳过本轮，避免重复上传与状态回滚。
  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _syncOnce();
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce() async {
    _retryTimer?.cancel();
    final pending = await store.pending(limit: batchSize);
    if (pending.isEmpty) return;

    await store.markSyncing(pending.map((log) => log.logId).toList());
    try {
      final result = await api.upload(pending);
      // 服务端按 accepted 计数：只标记被接受的为 synced
      final acceptedIds = pending
          .take(result.accepted)
          .map((log) => log.logId)
          .toList();
      if (acceptedIds.isNotEmpty) {
        await store.markSynced(acceptedIds);
      }
      // 若一批没传完（accepted < len），继续下一批
      if (await store.pendingCount() > 0) {
        _scheduleRetry(0);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OfflineLogSync] upload failed: $e');
      }
      // 用内存批次计算（先算再加）：bump 后 attempts >= max 的日志
      // 会被 pending() 过滤，重查数据库会导致 markFailed 不可达
      final ids = pending.map((log) => log.logId).toList();
      final attempts = pending.fold<int>(
            0,
            (max, log) =>
                log.syncAttempts > max ? log.syncAttempts : max,
          ) +
          1;
      if (attempts >= maxAttempts) {
        await store.markFailed(ids);
        return;
      }
      await store.bumpAttempts(ids);
      _scheduleRetry(attempts);
    }
  }

  void _scheduleRetry(int attemptIndex) {
    _retryTimer?.cancel();
    final index = attemptIndex.clamp(0, backoffSteps.length - 1).toInt();
    _retryTimer = Timer(backoffSteps[index], () {
      syncNow();
    });
  }

  void dispose() {
    _retryTimer?.cancel();
    _netSub?.cancel();
    _started = false;
  }
}
