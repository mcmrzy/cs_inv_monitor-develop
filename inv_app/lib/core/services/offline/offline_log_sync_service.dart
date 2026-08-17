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

  /// 单轮同步最多连续上传的批次数（避免剩余批次等退避后才继续）
  static const int maxBatchesPerRound = 4;

  Timer? _retryTimer;
  StreamSubscription<bool>? _netSub;
  bool _started = false;
  bool _syncing = false; // 同步互斥：多触发源并发时仅执行一轮

  /// 是否有退避重试在等待（测试断言用）
  bool get hasPendingRetry => _retryTimer?.isActive ?? false;

  /// 启动：恢复僵死的 syncing 日志、监听网络恢复事件并立即尝试一次
  Future<void> start() async {
    if (_started) return;
    _started = true;
    // markSyncing 后进程被杀/ack 丢失的日志会停在 syncing，
    // 启动时恢复为 pending 使其可重试
    await store.resetSyncingToPending();
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
    // 连续上传多个批次，避免未传完的批次等退避后才继续
    for (var round = 0; round < maxBatchesPerRound; round++) {
      final pending = await store.pending(limit: batchSize);
      if (pending.isEmpty) return;

      await store.markSyncing(pending.map((log) => log.logId).toList());
      try {
        final result = await api.upload(pending);
        // 服务端按 (user_id, log_id) 幂等去重：accepted 为新接收，
        // duplicates 为已存在——两者都算"已处理"，
        // 否则重传时 accepted=0 会导致日志永久卡在 pending 无限重试
        final processed =
            (result.accepted + result.duplicates).clamp(0, pending.length);
        final processedIds = pending
            .take(processed)
            .map((log) => log.logId)
            .toList();
        if (processedIds.isNotEmpty) {
          await store.markSynced(processedIds);
        }
        // 防御：服务端未处理完的条目 bump attempts，
        // 避免原地打转，达上限后转 failed 等待手动重试
        if (processed < pending.length) {
          final remaining = pending.skip(processed).toList();
          await _bumpOrFail(remaining, scheduleOnRetry: false);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[OfflineLogSync] upload failed: $e');
        }
        await _bumpOrFail(pending);
        return;
      }
    }
    // 达到单轮批次上限仍有剩余：尽快安排下一轮
    _scheduleRetry(0);
  }

  /// 失败处理：按单条 attempts 判定（而非整批取最大次数），
  /// 达上限的转 failed 终止态，其余 bump 后按最小次数调度退避
  Future<void> _bumpOrFail(
    List<OfflineOpLog> logs, {
    bool scheduleOnRetry = true,
  }) async {
    if (logs.isEmpty) return;
    final failedIds = <String>[];
    final retryIds = <String>[];
    var minAttempts = maxAttempts;
    for (final log in logs) {
      final attempts = log.syncAttempts + 1;
      if (attempts >= maxAttempts) {
        failedIds.add(log.logId);
      } else {
        retryIds.add(log.logId);
        if (attempts < minAttempts) minAttempts = attempts;
      }
    }
    if (failedIds.isNotEmpty) {
      await store.markFailed(failedIds);
    }
    if (retryIds.isNotEmpty) {
      await store.bumpAttempts(retryIds);
      if (scheduleOnRetry) {
        _scheduleRetry(minAttempts);
      }
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
