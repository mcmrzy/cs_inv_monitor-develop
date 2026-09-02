import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';

/// 一条待同步到云端的本地 OTA 升级结果
@immutable
class PendingLocalOtaResult {
  final String sn;
  final String targetChip;
  final String newVersion;
  final String? mainVersion;
  final DateTime enqueuedAt;

  const PendingLocalOtaResult({
    required this.sn,
    required this.targetChip,
    required this.newVersion,
    this.mainVersion,
    required this.enqueuedAt,
  });

  Map<String, dynamic> toJson() => {
        'sn': sn,
        'target_chip': targetChip,
        'new_version': newVersion,
        if (mainVersion != null && mainVersion!.isNotEmpty)
          'main_version': mainVersion,
        'enqueued_at': enqueuedAt.toIso8601String(),
      };

  static PendingLocalOtaResult? fromJson(Map<String, dynamic> json) {
    final sn = json['sn'] as String?;
    final chip = json['target_chip'] as String?;
    final version = json['new_version'] as String?;
    if (sn == null || sn.isEmpty || chip == null || version == null) {
      return null;
    }
    return PendingLocalOtaResult(
      sn: sn,
      targetChip: chip,
      newVersion: version,
      mainVersion: json['main_version'] as String?,
      enqueuedAt: DateTime.tryParse(json['enqueued_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// 同设备同芯片去重键：后入队的记录覆盖先入队的（设备已升到更新版本）
  String get dedupeKey => '$sn|$targetChip';
}

/// 本地 OTA 成功后的云端版本同步队列。
///
/// 旧行为：断开设备热点后立即上报，失败仅打日志 —— 升级结果从此丢失，
/// 云端固件版本与设备实际版本长期不一致。
/// 现在：上报失败写入 SharedPreferences 待同步队列，在入队时立即重试、
/// 网络恢复时重试、App 启动时重试（[start]），成功才出队。
class LocalOtaResultSyncQueue {
  LocalOtaResultSyncQueue({
    required OtaRepository repository,
    required SharedPreferences sharedPreferences,
    NetworkStatusService? networkStatus,
  })  : _repository = repository,
        _sharedPreferences = sharedPreferences,
        _networkStatus = networkStatus;

  static const String _queueKey = 'local_ota_result_sync_queue_v1';

  final OtaRepository _repository;
  final SharedPreferences _sharedPreferences;
  final NetworkStatusService? _networkStatus;

  List<PendingLocalOtaResult>? _pending;
  bool _flushing = false;
  bool _started = false;
  StreamSubscription<bool>? _networkSub;

  /// 当前待同步条数（含未加载的持久化记录）
  int get pendingCount {
    final pending = _pending;
    if (pending != null) return pending.length;
    return _loadFromStorage().length;
  }

  bool get hasPending => pendingCount > 0;

  /// 启动队列：加载持久化记录、订阅网络恢复、尝试一次启动同步。
  /// 幂等，可安全多次调用。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _pending ??= _loadFromStorage();

    _networkSub?.cancel();
    _networkSub = _networkStatus?.statusStream.listen((online) {
      // 网络恢复（含从设备热点切回正常网络）时重试
      if (online) {
        unawaited(flush());
      }
    });

    unawaited(flush());
  }

  /// 入队一条升级结果：立即尝试同步，失败留在队列中等待重试
  Future<void> enqueue({
    required String sn,
    required String targetChip,
    required String newVersion,
    String? mainVersion,
  }) async {
    final item = PendingLocalOtaResult(
      sn: sn,
      targetChip: targetChip,
      newVersion: newVersion,
      mainVersion: mainVersion,
      enqueuedAt: DateTime.now(),
    );

    final pending = _pending ??= _loadFromStorage();
    // 同设备同芯片仅保留最新一条：设备已升到新版本，旧记录上报也无意义
    pending.removeWhere((e) => e.dedupeKey == item.dedupeKey);
    pending.add(item);
    await _persist();
    debugPrint(
      '[LocalOTA] result enqueued for sync (sn=$sn chip=$targetChip '
      'version=$newVersion, queue=${pending.length})',
    );

    unawaited(flush());
  }

  /// 同步全部待同步记录：成功的出队，失败的保留（下次再试）
  Future<void> flush() async {
    if (_flushing) return;
    final pending = _pending ??= _loadFromStorage();
    if (pending.isEmpty) return;
    _flushing = true;
    try {
      final remaining = <PendingLocalOtaResult>[];
      for (final item in List.of(pending)) {
        try {
          final result = await _repository.reportLocalOTAResult(
            sn: item.sn,
            targetChip: item.targetChip,
            newVersion: item.newVersion,
            mainVersion: item.mainVersion,
          );
          result.fold(
            (failure) {
              debugPrint(
                '[LocalOTA] sync retry later (sn=${item.sn}): ${failure.message}',
              );
              remaining.add(item);
            },
            (_) {
              debugPrint('[LocalOTA] result synced (sn=${item.sn})');
            },
          );
        } catch (e) {
          // 网络异常等：保留记录等待下次重试
          debugPrint('[LocalOTA] sync error (sn=${item.sn}): $e');
          remaining.add(item);
        }
      }
      _pending = remaining;
      await _persist();
    } finally {
      _flushing = false;
    }
  }

  List<PendingLocalOtaResult> _loadFromStorage() {
    final raw = _sharedPreferences.getString(_queueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => PendingLocalOtaResult.fromJson(
              Map<String, dynamic>.from(e)))
          .whereType<PendingLocalOtaResult>()
          .toList();
    } catch (e) {
      debugPrint('[LocalOTA] sync queue corrupt, reset: $e');
      return [];
    }
  }

  Future<void> _persist() async {
    final pending = _pending ?? const <PendingLocalOtaResult>[];
    await _sharedPreferences.setString(
      _queueKey,
      jsonEncode(pending.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> dispose() async {
    await _networkSub?.cancel();
    _networkSub = null;
    _started = false;
  }
}
