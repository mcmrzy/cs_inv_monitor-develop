// 设备云端调试 API —— 会话生命周期 + 采样数据
//
// 契约（business-api 已实现）：
//   GET    /devices/by-sn/:sn/debug-session            → { session, device_online, supported, interval_seconds }
//   POST   /devices/by-sn/:sn/debug-session            → { session, conflict }
//   DELETE /devices/by-sn/:sn/debug-session/:id        → { session }
//   GET    /devices/by-sn/:sn/debug-samples            → { items, next_cursor, session }
//
// 统一响应 {code, message, data}，经 unwrapApiResponse 解包；
// 离线/冲突/超限时后端返回非 0 code（如 409），此处抛 ApiBusinessException。

import 'package:dio/dio.dart';

import 'package:inv_app/core/utils/api_response.dart';

/// 调试会话状态
///
/// starting=正在开启 active=已开启 stopping=正在关闭 stopped=已停止
/// expired=已过期 interrupted=数据中断 failed=失败
class DeviceDebugSession {
  final String id;
  final String deviceSn;
  final String status;
  final int intervalSeconds;
  final int durationSeconds;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final DateTime? stoppedAt;
  final String? requestedBy;
  final String source;
  final String? startTaskId;
  final String? stopTaskId;
  final DateTime? lastSampleAt;
  final String? failureReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DeviceDebugSession({
    required this.id,
    required this.deviceSn,
    required this.status,
    required this.intervalSeconds,
    required this.durationSeconds,
    this.startedAt,
    this.expiresAt,
    this.stoppedAt,
    this.requestedBy,
    required this.source,
    this.startTaskId,
    this.stopTaskId,
    this.lastSampleAt,
    this.failureReason,
    this.createdAt,
    this.updatedAt,
  });

  bool get isTerminal =>
      status == 'stopped' || status == 'expired' || status == 'failed';

  factory DeviceDebugSession.fromJson(Map<String, dynamic> json) {
    DateTime? parseTime(dynamic raw) =>
        raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

    return DeviceDebugSession(
      id: json['id'] as String? ?? '',
      deviceSn: json['device_sn'] as String? ?? '',
      status: json['status'] as String? ?? '',
      intervalSeconds: (json['interval_seconds'] as num?)?.toInt() ?? 30,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      startedAt: parseTime(json['started_at']),
      expiresAt: parseTime(json['expires_at']),
      stoppedAt: parseTime(json['stopped_at']),
      requestedBy: json['requested_by'] as String?,
      source: json['source'] as String? ?? '',
      startTaskId: json['start_task_id'] as String?,
      stopTaskId: json['stop_task_id'] as String?,
      lastSampleAt: parseTime(json['last_sample_at']),
      failureReason: json['failure_reason'] as String?,
      createdAt: parseTime(json['created_at']),
      updatedAt: parseTime(json['updated_at']),
    );
  }
}

/// 单帧采样的指标集合；double? 可空 = 该测点采集断线（曲线断开）
class DeviceDebugMetrics {
  final double? pv1Voltage;
  final double? buck1Current;
  final double? pv2Voltage;
  final double? buck2Current;
  final double? batteryVoltage;
  final double? batteryCurrent;
  final double? dcBusVoltage;
  final double? invCurrent;
  final double? acVoltage;
  final double? acCurrent;

  const DeviceDebugMetrics({
    this.pv1Voltage,
    this.buck1Current,
    this.pv2Voltage,
    this.buck2Current,
    this.batteryVoltage,
    this.batteryCurrent,
    this.dcBusVoltage,
    this.invCurrent,
    this.acVoltage,
    this.acCurrent,
  });

  double? valueFor(String key) => switch (key) {
        'pv1_voltage' => pv1Voltage,
        'buck1_current' => buck1Current,
        'pv2_voltage' => pv2Voltage,
        'buck2_current' => buck2Current,
        'battery_voltage' => batteryVoltage,
        'battery_current' => batteryCurrent,
        'dc_bus_voltage' => dcBusVoltage,
        'inv_current' => invCurrent,
        'ac_voltage' => acVoltage,
        'ac_current' => acCurrent,
        _ => null,
      };

  factory DeviceDebugMetrics.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic raw) => raw is num ? raw.toDouble() : null;
    return DeviceDebugMetrics(
      pv1Voltage: asDouble(json['pv1_voltage']),
      buck1Current: asDouble(json['buck1_current']),
      pv2Voltage: asDouble(json['pv2_voltage']),
      buck2Current: asDouble(json['buck2_current']),
      batteryVoltage: asDouble(json['battery_voltage']),
      batteryCurrent: asDouble(json['battery_current']),
      dcBusVoltage: asDouble(json['dc_bus_voltage']),
      invCurrent: asDouble(json['inv_current']),
      acVoltage: asDouble(json['ac_voltage']),
      acCurrent: asDouble(json['ac_current']),
    );
  }
}

/// 单帧采样（按 time 升序由后端保证）
class DeviceDebugSample {
  final DateTime time;

  /// 服务端收到时间（可为 null）
  final DateTime? receivedAt;

  /// 质量标记（如丢包/补传），空列表表示无异常
  final List<String> qualityFlags;

  final String? protocolVersion;
  final DeviceDebugMetrics metrics;

  const DeviceDebugSample({
    required this.time,
    this.receivedAt,
    this.qualityFlags = const [],
    this.protocolVersion,
    required this.metrics,
  });

  factory DeviceDebugSample.fromJson(Map<String, dynamic> json) {
    final flags = json['quality_flags'];
    return DeviceDebugSample(
      time: DateTime.tryParse(json['time'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      receivedAt:
          json['received_at'] is String
              ? DateTime.tryParse(json['received_at'] as String)?.toUtc()
              : null,
      qualityFlags: flags is List
          ? flags.whereType<String>().toList(growable: false)
          : const [],
      protocolVersion: json['protocol_version'] as String?,
      metrics: DeviceDebugMetrics.fromJson(
        (json['metrics'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }
}

/// GET debug-session 响应 data
class DeviceDebugSessionInfo {
  final DeviceDebugSession? session;
  final bool deviceOnline;

  /// 设备/协议是否支持云端调试
  final bool supported;

  /// 建议采样间隔（秒）
  final int intervalSeconds;

  const DeviceDebugSessionInfo({
    this.session,
    required this.deviceOnline,
    required this.supported,
    required this.intervalSeconds,
  });

  factory DeviceDebugSessionInfo.fromJson(Map<String, dynamic> json) {
    final sessionRaw = json['session'];
    return DeviceDebugSessionInfo(
      session: sessionRaw is Map<String, dynamic>
          ? DeviceDebugSession.fromJson(sessionRaw)
          : null,
      deviceOnline: json['device_online'] == true,
      supported: json['supported'] != false,
      intervalSeconds: (json['interval_seconds'] as num?)?.toInt() ?? 30,
    );
  }
}

/// POST debug-session 响应 data；conflict=true 表示设备已有进行中的会话
class DeviceDebugSessionStartResult {
  final DeviceDebugSession? session;
  final bool conflict;

  const DeviceDebugSessionStartResult({this.session, this.conflict = false});

  factory DeviceDebugSessionStartResult.fromJson(Map<String, dynamic> json) {
    final sessionRaw = json['session'];
    return DeviceDebugSessionStartResult(
      session: sessionRaw is Map<String, dynamic>
          ? DeviceDebugSession.fromJson(sessionRaw)
          : null,
      conflict: json['conflict'] == true,
    );
  }
}

/// GET debug-samples 响应 data；next_cursor 为不透明游标，空串表示无更多数据
class DeviceDebugSamplesPage {
  final List<DeviceDebugSample> items;
  final String nextCursor;
  final DeviceDebugSession? session;

  const DeviceDebugSamplesPage({
    required this.items,
    required this.nextCursor,
    this.session,
  });

  factory DeviceDebugSamplesPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final sessionRaw = json['session'];
    return DeviceDebugSamplesPage(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(DeviceDebugSample.fromJson)
              .toList(growable: false)
          : const [],
      nextCursor: json['next_cursor'] as String? ?? '',
      session: sessionRaw is Map<String, dynamic>
          ? DeviceDebugSession.fromJson(sessionRaw)
          : null,
    );
  }
}

/// 设备云端调试 API
class DeviceDebugApi {
  DeviceDebugApi(this._dio);

  final Dio _dio;

  /// 查询当前调试会话（含设备在线状态与是否支持）
  Future<DeviceDebugSessionInfo> getDebugSession(String sn) async {
    final res = await _dio.get('/devices/by-sn/$sn/debug-session');
    final data = unwrapApiResponse<Map<String, dynamic>>(
      res.data,
      validate: (value) => value is Map<String, dynamic>,
      expected: 'an object',
    );
    return DeviceDebugSessionInfo.fromJson(data);
  }

  /// 开启调试会话；离线/失败/超限由后端返回非 0 code → ApiBusinessException
  Future<DeviceDebugSessionStartResult> startDebugSession(
    String sn, {
    required int durationSeconds,
    required String requestId,
  }) async {
    final res = await _dio.post(
      '/devices/by-sn/$sn/debug-session',
      data: <String, dynamic>{
        'duration_seconds': durationSeconds,
        'request_id': requestId,
        'source': 'app',
      },
    );
    final data = unwrapApiResponse<Map<String, dynamic>>(
      res.data,
      validate: (value) => value is Map<String, dynamic>,
      expected: 'an object',
    );
    return DeviceDebugSessionStartResult.fromJson(data);
  }

  /// 停止调试会话，返回停止后的会话（可能为 null）
  Future<DeviceDebugSession?> stopDebugSession(String sn, String sessionId) async {
    final res = await _dio.delete('/devices/by-sn/$sn/debug-session/$sessionId');
    final data = unwrapApiResponse<Map<String, dynamic>>(
      res.data,
      validate: (value) => value is Map<String, dynamic>,
      expected: 'an object',
    );
    final sessionRaw = data['session'];
    return sessionRaw is Map<String, dynamic>
        ? DeviceDebugSession.fromJson(sessionRaw)
        : null;
  }

  /// 拉取采样数据。[after] 传上一次的 next_cursor 做增量拉取；
  /// 全量重拉（时间窗切换/新会话）不传 after。
  Future<DeviceDebugSamplesPage> getDebugSamples(
    String sn, {
    String? sessionId,
    int windowMinutes = 15,
    String? after,
    int limit = 200,
  }) async {
    final res = await _dio.get(
      '/devices/by-sn/$sn/debug-samples',
      queryParameters: <String, dynamic>{
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
        'window_minutes': windowMinutes,
        if (after != null && after.isNotEmpty) 'after': after,
        'limit': limit,
      },
    );
    final data = unwrapApiResponse<Map<String, dynamic>>(
      res.data,
      validate: (value) => value is Map<String, dynamic>,
      expected: 'an object',
    );
    return DeviceDebugSamplesPage.fromJson(data);
  }
}
