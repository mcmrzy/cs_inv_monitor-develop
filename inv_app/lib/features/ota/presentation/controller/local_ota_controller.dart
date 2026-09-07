import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:inv_app/core/errors/ota_error_types.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/features/ota/data/datasources/local_ota_result_sync_queue.dart';
import 'package:inv_app/features/ota/domain/entities/local_channel.dart';
import 'package:inv_app/features/ota/domain/repositories/local_communication_repository.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';

/// 本地 OTA 执行阶段
enum LocalOTAPhase {
  idle,
  uploading,
  upgrading,
  success,
  failed,
  timedOut,
}

/// 本地 OTA 执行状态（UI 无关，页面负责映射为文案/进度条）
class LocalOTAControllerState {
  final LocalOTAPhase phase;

  /// 固件上传进度 0..1
  final double uploadProgress;

  /// 设备侧升级进度 0..1
  final double upgradeProgress;

  /// 特殊状态文案 l10n key（如 waiting_hotspot_recovery），
  /// 为 null 时使用 [deviceMessage]/[deviceStatus] 渲染
  final String? statusOverrideKey;
  final Map<String, String> statusOverrideParams;

  /// 设备返回的原始状态与消息（供页面做本地化映射）
  final String deviceStatus;
  final String deviceMessage;

  /// 失败时的原始异常（页面经 OtaErrorMapper 映射文案）
  final Object? error;

  /// 升级成功后的新版本号
  final String? newVersion;

  const LocalOTAControllerState({
    this.phase = LocalOTAPhase.idle,
    this.uploadProgress = 0,
    this.upgradeProgress = 0,
    this.statusOverrideKey,
    this.statusOverrideParams = const {},
    this.deviceStatus = '',
    this.deviceMessage = '',
    this.error,
    this.newVersion,
  });

  LocalOTAControllerState copyWith({
    LocalOTAPhase? phase,
    double? uploadProgress,
    double? upgradeProgress,
    String? Function()? statusOverrideKey,
    Map<String, String>? statusOverrideParams,
    String? deviceStatus,
    String? deviceMessage,
    Object? Function()? error,
    String? Function()? newVersion,
  }) {
    return LocalOTAControllerState(
      phase: phase ?? this.phase,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      upgradeProgress: upgradeProgress ?? this.upgradeProgress,
      statusOverrideKey:
          statusOverrideKey != null ? statusOverrideKey() : this.statusOverrideKey,
      statusOverrideParams: statusOverrideParams ?? this.statusOverrideParams,
      deviceStatus: deviceStatus ?? this.deviceStatus,
      deviceMessage: deviceMessage ?? this.deviceMessage,
      error: error != null ? error() : this.error,
      newVersion: newVersion != null ? newVersion() : this.newVersion,
    );
  }
}

/// 本地 OTA 执行引擎（上传 → 触发 → 轮询 → 结果上报）。
///
/// 自 local_ota_page 的巨型 State 下沉而来：页面仅负责渲染与
/// 热点扫描/重连等 UI 相关动作（经回调注入），流程状态机集中于此，
/// 可独立测试，并供升级包串行编排等多入口复用。
class LocalOTAController extends ChangeNotifier {
  LocalOTAController({
    required LocalCommunicationRepository communication,
    required OtaRepository repository,
    required LocalCommunicationChannel channel,
    required String deviceSN,
    required String deviceIP,
    Future<bool> Function()? isHotspotConnected,
    Future<bool> Function()? reconnectHotspot,
    VoidCallback? onTerminateConnection,
    LocalOtaResultSyncQueue? syncQueue,
  })  : _communication = communication,
        _repository = repository,
        _channel = channel,
        _deviceSN = deviceSN,
        _deviceIP = deviceIP,
        _isHotspotConnected = isHotspotConnected,
        _reconnectHotspot = reconnectHotspot,
        _onTerminateConnection = onTerminateConnection,
        _syncQueue = syncQueue;

  final LocalCommunicationRepository _communication;
  final OtaRepository _repository;
  final LocalCommunicationChannel _channel;
  final String _deviceSN;
  final String _deviceIP;
  final Future<bool> Function()? _isHotspotConnected;
  final Future<bool> Function()? _reconnectHotspot;
  final VoidCallback? _onTerminateConnection;

  /// 升级结果云端同步队列：入队后自动重试直至成功；
  /// 为 null 时退回旧行为（一次性直报，失败仅日志）
  final LocalOtaResultSyncQueue? _syncQueue;

  /// 轮询总超时（挂钟时间，含热点重连与请求耗时）
  static const Duration _maxPollDuration = Duration(seconds: 180);

  LocalOTAControllerState _state = const LocalOTAControllerState();
  LocalOTAControllerState get state => _state;
  bool _disposed = false;

  void _emit(LocalOTAControllerState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  /// 执行完整本地升级流程。[fallbackVersion] 用于设备未返回版本时兜底展示。
  Future<void> execute({
    required String filePath,
    required LocalOtaManifest manifest,
    required String fallbackVersion,
  }) async {
    final isEsp = manifest.target.toLowerCase() == 'esp';

    // ---- 1. 上传固件 ----
    _emit(_state.copyWith(
      phase: LocalOTAPhase.uploading,
      uploadProgress: 0,
      error: () => null,
    ));
    try {
      await _communication.uploadFirmware(
        deviceIP: _deviceIP,
        filePath: filePath,
        manifest: manifest,
        onProgress: (sent, total) {
          if (total > 0) {
            _emit(_state.copyWith(uploadProgress: sent / total));
          }
        },
      );
    } catch (e) {
      _emit(_state.copyWith(
        phase: LocalOTAPhase.failed,
        uploadProgress: _state.uploadProgress,
        error: () => e,
      ));
      _onTerminateConnection?.call();
      return;
    }

    // ---- 2. 触发升级 ----
    try {
      await _communication.triggerUpgrade(_deviceIP);
    } catch (e) {
      _emit(_state.copyWith(
        phase: LocalOTAPhase.failed,
        uploadProgress: 1.0,
        error: () => e,
      ));
      _onTerminateConnection?.call();
      return;
    }

    // ---- 3. 等待重启 ----
    _emit(_state.copyWith(
      phase: LocalOTAPhase.upgrading,
      uploadProgress: 1.0,
      statusOverrideKey: () =>
          isEsp ? 'push_complete_wait_reboot' : null,
    ));
    if (isEsp) {
      // ESP 自升级：传完固件 → 写 Flash → 立即重启（~500ms）
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // ---- 4. 轮询升级进度 ----
    await _pollProgress(
      isEsp: isEsp,
      fallbackVersion: fallbackVersion,
      targetChip: manifest.target,
    );
  }

  /// 统一轮询 /ota/progress（ESP：NVS 持久化结果；ARM：实时进度）
  Future<void> _pollProgress({
    required bool isEsp,
    required String fallbackVersion,
    required String targetChip,
  }) async {
    final versionKey = isEsp ? 'esp_version' : 'arm_version';
    final firmwareKey = isEsp ? 'firmware_esp' : 'firmware_arm';

    // 挂钟计时：热点重连、请求耗时都计入总超时
    final stopwatch = Stopwatch()..start();
    int offlineCount = 0;
    bool isFirstPoll = true;

    while (stopwatch.elapsed < _maxPollDuration) {
      if (_disposed) return;
      if (!isFirstPoll) {
        await Future.delayed(const Duration(seconds: 1));
        if (_disposed) return;
      }
      isFirstPoll = false;

      // WiFi 通道：热点断开 = 设备重启中，尝试重连
      if (_channel == LocalCommunicationChannel.wifiAp &&
          _isHotspotConnected != null) {
        final wifiConnected = await _isHotspotConnected();
        if (!wifiConnected) {
          offlineCount++;
          _emit(_state.copyWith(
            statusOverrideKey: () => 'waiting_hotspot_recovery',
            statusOverrideParams: {
              'seconds': '${stopwatch.elapsed.inSeconds}',
            },
          ));
          if (offlineCount % 2 == 0 && _reconnectHotspot != null) {
            final reconnected = await _reconnectHotspot();
            if (reconnected && !_disposed) {
              _emit(_state.copyWith(
                statusOverrideKey: () => 'hotspot_reconnected',
              ));
              offlineCount = 0;
            } else {
              continue;
            }
          } else {
            continue;
          }
        } else {
          offlineCount = 0;
        }
      }

      try {
        final progress = await _communication.getProgress(_deviceIP);
        final status = (progress['state'] as String? ??
                progress['status'] as String? ??
                '')
            .toLowerCase();
        final percent = (progress['progress'] as num?)?.toDouble() ?? 0.0;
        final message = progress['message'] as String? ?? '';
        // 版本获取优先级：main_version > version > 芯片专属字段
        final mainVer = progress['main_version'] as String? ?? '';
        final chipVer = (progress['version'] as String? ?? '').isNotEmpty
            ? (progress['version'] as String)
            : (progress[versionKey] as String? ?? '');
        final displayVersion = mainVer.isNotEmpty
            ? mainVer
            : (chipVer.isNotEmpty ? chipVer : fallbackVersion);

        _emit(_state.copyWith(
          upgradeProgress: percent / 100.0,
          deviceStatus: status,
          deviceMessage: message,
          statusOverrideKey: () => null,
        ));

        if (status == 'done' || status == 'succeeded') {
          String? newVersion =
              displayVersion.isNotEmpty ? displayVersion : null;
          final chipNewVersion =
              (progress[firmwareKey] as String? ?? '').isNotEmpty
                  ? (progress[firmwareKey] as String)
                  : chipVer.isNotEmpty
                      ? chipVer
                      : (progress[versionKey] as String? ?? fallbackVersion);
          if (newVersion == null) {
            try {
              final info = await _communication.getDeviceInfo(_deviceIP);
              final infoMainVer = info['main_version'] as String? ?? '';
              final infoChipVer =
                  (info[firmwareKey] as String? ?? '').isNotEmpty
                      ? (info[firmwareKey] as String)
                      : (info[versionKey] as String? ?? '').isNotEmpty
                          ? (info[versionKey] as String)
                          : (info['version'] as String? ?? '');
              newVersion = infoMainVer.isNotEmpty
                  ? infoMainVer
                  : (infoChipVer.isNotEmpty ? infoChipVer : null);
            } catch (e) {
              debugPrint('[LocalOTA] get device info failed: $e');
            }
          }

          _emit(_state.copyWith(
            phase: LocalOTAPhase.success,
            newVersion: () => newVersion,
          ));
          _onTerminateConnection?.call();
          // 成功后经 Repository 上报（不再由页面直连 Dio 绕过分层）
          if (newVersion != null) {
            await _reportResult(
              targetChip: targetChip,
              chipNewVersion:
                  chipNewVersion.isNotEmpty ? chipNewVersion : '',
              mainVersion: mainVer.isNotEmpty ? mainVer : null,
            );
          }
          return;
        }

        if (status == 'error' ||
            status == 'failed' ||
            status == 'rolled_back' ||
            status == 'cancelled') {
          _emit(_state.copyWith(phase: LocalOTAPhase.failed));
          _onTerminateConnection?.call();
          return;
        }
      } on DeviceConnectionException {
        // 连接失败：设备可能刚重启完还在初始化 HTTP 服务
        offlineCount++;
        _emit(_state.copyWith(
          statusOverrideKey: () => 'waiting_device_response',
          statusOverrideParams: {
            'seconds': '${stopwatch.elapsed.inSeconds}',
          },
        ));
        continue;
      } catch (e) {
        debugPrint('[LocalOTA] poll progress error: $e');
        continue;
      }
    }

    // 总超时
    _emit(_state.copyWith(phase: LocalOTAPhase.timedOut));
    _onTerminateConnection?.call();
  }

  /// 本地 OTA 成功后上报结果到后端
  Future<void> _reportResult({
    required String targetChip,
    required String chipNewVersion,
    String? mainVersion,
  }) async {
    // 等待网络恢复（断开热点后需要几秒切回移动网络/普通 WiFi）
    await Future.delayed(const Duration(seconds: 3));
    if (_disposed) return;

    final queue = _syncQueue;
    if (queue != null) {
      // 入队即尝试同步；失败留在队列，网络恢复/下次启动时自动重试，
      // 不再静默丢失（旧行为失败仅打日志，云端版本从此与设备不一致）
      await queue.enqueue(
        sn: _deviceSN,
        targetChip: targetChip,
        newVersion: chipNewVersion,
        mainVersion: mainVersion,
      );
      return;
    }

    try {
      await _repository.reportLocalOTAResult(
        sn: _deviceSN,
        targetChip: targetChip,
        newVersion: chipNewVersion,
        mainVersion: mainVersion,
      );
    } catch (e) {
      debugPrint('[LocalOTA] report result failed: $e');
      // 上报失败不影响用户体验，静默处理
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
