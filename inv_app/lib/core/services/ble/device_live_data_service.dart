import 'dart:async';

import 'package:inv_app/core/services/ble/device_live_snapshot.dart';

/// 按设备 SN 汇聚 BLE 与云端候选快照，并只发布当前最佳候选值。
///
/// 本服务只负责来源选择和连接代次隔离；遥测字段仍使用现有业务 Map，
/// 不在这里解析或复制成另一套业务实体。
class DeviceLiveDataService {
  final _controller = StreamController<DeviceLiveSnapshot>.broadcast();
  final Map<String, DeviceLiveSnapshot> _latestByDevice = {};
  final Map<String, int> _lastBleGenerationByDevice = {};
  final Map<String, int> _activeBleGenerationByDevice = {};
  bool _disposed = false;

  /// 所有设备的已选快照流。需要单设备隔离时使用 [watchDevice]。
  Stream<DeviceLiveSnapshot> get snapshots => _controller.stream;

  /// 为一次新的 BLE 连接分配单调递增的代次。
  ///
  /// 调用后，属于同一 SN 的旧连接异步结果将被 [add] 丢弃。
  int beginBleConnection(String deviceSn) {
    _ensureUsableDeviceSn(deviceSn);
    _ensureNotDisposed();
    final generation = (_lastBleGenerationByDevice[deviceSn] ?? 0) + 1;
    _lastBleGenerationByDevice[deviceSn] = generation;
    _activeBleGenerationByDevice[deviceSn] = generation;
    return generation;
  }

  /// 结束指定连接。末值不会被清空，消费者可用 `freshnessAt` 明确展示过期。
  void endBleConnection(String deviceSn, int connectionGeneration) {
    if (_disposed) return;
    if (_activeBleGenerationByDevice[deviceSn] == connectionGeneration) {
      _activeBleGenerationByDevice.remove(deviceSn);
    }
  }

  int? activeBleConnectionGeneration(String deviceSn) =>
      _activeBleGenerationByDevice[deviceSn];

  /// 加入候选快照。返回 `true` 表示候选值成为该 SN 的当前值并已发布。
  bool add(DeviceLiveSnapshot candidate) {
    _ensureNotDisposed();
    if (!candidate.isValid ||
        candidate.isObviouslyFutureComparedTo(candidate.receivedAt) ||
        !_belongsToCurrentConnection(candidate)) {
      return false;
    }

    final current = _latestByDevice[candidate.deviceSn];
    if (current != null && !_shouldReplace(current, candidate)) {
      return false;
    }

    _latestByDevice[candidate.deviceSn] = candidate;
    _controller.add(candidate);
    return true;
  }

  DeviceLiveSnapshot? latestFor(String deviceSn) => _latestByDevice[deviceSn];

  /// 只转发指定 SN，避免页面或 Bloc 自行过滤时发生设备串流。
  Stream<DeviceLiveSnapshot> watchDevice(String deviceSn) {
    _ensureUsableDeviceSn(deviceSn);
    return snapshots.where((snapshot) => snapshot.deviceSn == deviceSn);
  }

  bool _belongsToCurrentConnection(DeviceLiveSnapshot candidate) {
    if (candidate.source != DeviceLiveSource.ble) return true;
    return _activeBleGenerationByDevice[candidate.deviceSn] ==
        candidate.connectionGeneration;
  }

  bool _shouldReplace(
    DeviceLiveSnapshot current,
    DeviceLiveSnapshot candidate,
  ) {
    final currentSampledAt = current.sampledAt;
    final candidateSampledAt = candidate.sampledAt;

    if (candidateSampledAt != null && currentSampledAt == null) return true;
    if (candidateSampledAt == null && currentSampledAt != null) return false;

    if (candidateSampledAt != null && currentSampledAt != null) {
      final sampledComparison = candidateSampledAt.compareTo(currentSampledAt);
      if (sampledComparison != 0) return sampledComparison > 0;
    }

    final sequenceComparison = _compareSequence(current, candidate);
    if (sequenceComparison != 0) return sequenceComparison > 0;

    if (candidate.source != current.source) {
      return candidate.source == DeviceLiveSource.ble;
    }

    final currentGeneration = current.connectionGeneration;
    final candidateGeneration = candidate.connectionGeneration;
    if (currentGeneration != null &&
        candidateGeneration != null &&
        candidateGeneration != currentGeneration) {
      return candidateGeneration > currentGeneration;
    }

    return candidate.receivedAt.isAfter(current.receivedAt);
  }

  int _compareSequence(
    DeviceLiveSnapshot current,
    DeviceLiveSnapshot candidate,
  ) {
    if (current.bootId == null ||
        candidate.bootId == null ||
        current.bootId != candidate.bootId ||
        current.sampleSequence == null ||
        candidate.sampleSequence == null) {
      return 0;
    }
    return candidate.sampleSequence!.compareTo(current.sampleSequence!);
  }

  void _ensureUsableDeviceSn(String deviceSn) {
    if (deviceSn.trim().isEmpty) {
      throw ArgumentError.value(deviceSn, 'deviceSn', 'must not be empty');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('DeviceLiveDataService is disposed');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _activeBleGenerationByDevice.clear();
    await _controller.close();
  }
}
