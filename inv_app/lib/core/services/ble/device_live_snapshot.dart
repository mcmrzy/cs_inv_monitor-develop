import 'dart:collection';

/// 实时数据的传输来源。
enum DeviceLiveSource { cloud, ble }

/// 快照内容质量。`invalid` 快照不会进入实时数据流。
enum DeviceLiveQuality { good, degraded, unknown, invalid }

/// 相对某个检查时刻的数据新鲜度。
enum DeviceLiveFreshness { fresh, stale, unknown }

const _defaultFutureSampleTolerance = Duration(minutes: 1);

dynamic _deepFreezeValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(
      value.map(
        (key, nestedValue) => MapEntry(key, _deepFreezeValue(nestedValue)),
      ),
    );
  }
  if (value is Map) {
    return Map.unmodifiable(
      value.map(
        (key, nestedValue) => MapEntry(key, _deepFreezeValue(nestedValue)),
      ),
    );
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map(_deepFreezeValue));
  }
  if (value is Set) {
    return Set<dynamic>.unmodifiable(value.map(_deepFreezeValue));
  }
  return value;
}

Map<String, dynamic> _deepFreezeData(Map<String, dynamic> data) {
  return Map<String, dynamic>.unmodifiable(
    data.map(
      (key, value) => MapEntry(key, _deepFreezeValue(value)),
    ),
  );
}

/// 复用既有遥测 Map 的轻量信封，不复制业务字段模型。
///
/// [sampledAt] 是设备实际采样时间；[receivedAt] 只是 App 收到候选值的
/// 时间，两者不可互相替代。
class DeviceLiveSnapshot {
  DeviceLiveSnapshot._({
    required this.deviceSn,
    required this.source,
    required Map<String, dynamic> data,
    required this.sampledAt,
    required this.receivedAt,
    required this.connectionGeneration,
    required this.quality,
    required this.qualityFlags,
    required this.bootId,
    required this.sampleSequence,
    required this.timeQuality,
    required this.schemaVersion,
  }) : data = UnmodifiableMapView(_deepFreezeData(data)) {
    if (deviceSn.trim().isEmpty) {
      throw ArgumentError.value(deviceSn, 'deviceSn', 'must not be empty');
    }
  }

  factory DeviceLiveSnapshot.cloud({
    required String deviceSn,
    required Map<String, dynamic> data,
    required DateTime? sampledAt,
    required DateTime receivedAt,
    required DeviceLiveQuality quality,
    int? qualityFlags,
    String? bootId,
    int? sampleSequence,
    String? timeQuality,
    String? schemaVersion,
  }) {
    return DeviceLiveSnapshot._(
      deviceSn: deviceSn,
      source: DeviceLiveSource.cloud,
      data: data,
      sampledAt: sampledAt,
      receivedAt: receivedAt,
      connectionGeneration: null,
      quality: quality,
      qualityFlags: qualityFlags,
      bootId: bootId,
      sampleSequence: sampleSequence,
      timeQuality: timeQuality,
      schemaVersion: schemaVersion,
    );
  }

  factory DeviceLiveSnapshot.ble({
    required String deviceSn,
    required Map<String, dynamic> data,
    required DateTime sampledAt,
    required DateTime receivedAt,
    required int connectionGeneration,
    required DeviceLiveQuality quality,
    int? qualityFlags,
    String? bootId,
    int? sampleSequence,
    String? timeQuality,
    String? schemaVersion,
  }) {
    if (connectionGeneration <= 0) {
      throw ArgumentError.value(
        connectionGeneration,
        'connectionGeneration',
        'must be positive',
      );
    }
    if (qualityFlags == null || qualityFlags < 0) {
      throw ArgumentError.value(
        qualityFlags,
        'qualityFlags',
        'BLE telemetry must include non-negative quality flags',
      );
    }
    if (bootId == null || bootId.trim().isEmpty) {
      throw ArgumentError.value(
        bootId,
        'bootId',
        'BLE telemetry must include a boot ID',
      );
    }
    if (sampleSequence == null || sampleSequence < 0) {
      throw ArgumentError.value(
        sampleSequence,
        'sampleSequence',
        'BLE telemetry must include a non-negative sample sequence',
      );
    }
    if (timeQuality == null || timeQuality.trim().isEmpty) {
      throw ArgumentError.value(
        timeQuality,
        'timeQuality',
        'BLE telemetry must include time quality',
      );
    }
    if (schemaVersion == null || schemaVersion.trim().isEmpty) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'BLE telemetry must include a schema version',
      );
    }
    return DeviceLiveSnapshot._(
      deviceSn: deviceSn,
      source: DeviceLiveSource.ble,
      data: data,
      sampledAt: sampledAt,
      receivedAt: receivedAt,
      connectionGeneration: connectionGeneration,
      quality: quality,
      qualityFlags: qualityFlags,
      bootId: bootId,
      sampleSequence: sampleSequence,
      timeQuality: timeQuality,
      schemaVersion: schemaVersion,
    );
  }

  final String deviceSn;
  final DeviceLiveSource source;
  final Map<String, dynamic> data;
  final DateTime? sampledAt;
  final DateTime receivedAt;

  /// 仅 BLE 候选值存在，用于丢弃断线前仍在途的异步结果。
  final int? connectionGeneration;

  final DeviceLiveQuality quality;

  /// 协议中的原始质量位；未知位原样保留，由既有质量解码器解释。
  final int? qualityFlags;
  final String? bootId;
  final int? sampleSequence;
  final String? timeQuality;
  final String? schemaVersion;

  bool get isValid => quality != DeviceLiveQuality.invalid;

  bool isObviouslyFutureComparedTo(
    DateTime reference, {
    Duration tolerance = _defaultFutureSampleTolerance,
  }) {
    return sampledAt?.isAfter(reference.add(tolerance)) ?? false;
  }

  /// 只依据真实采样时间计算；缺失时明确返回 [DeviceLiveFreshness.unknown]。
  DeviceLiveFreshness freshnessAt(
    DateTime now, {
    Duration freshFor = const Duration(minutes: 3),
  }) {
    final sampled = sampledAt;
    if (sampled == null) return DeviceLiveFreshness.unknown;
    if (isObviouslyFutureComparedTo(now)) {
      return DeviceLiveFreshness.unknown;
    }
    return now.difference(sampled) <= freshFor
        ? DeviceLiveFreshness.fresh
        : DeviceLiveFreshness.stale;
  }
}
