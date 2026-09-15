/// 设备固件总览（GET /ota/devices/{sn}/firmware-overview）
///
/// 按模块（target ∈ arm|esp|dsp|bms）返回当前版本与最新可升级固件，
/// 服务端保证 modules 顺序 ESP 最后。
class DeviceFirmwareOverview {
  const DeviceFirmwareOverview({
    required this.deviceSn,
    required this.deviceModel,
    required this.isOnline,
    required this.modules,
  });

  final String deviceSn;
  final String deviceModel;
  final bool isOnline;
  final List<FirmwareModuleOverview> modules;

  factory DeviceFirmwareOverview.fromJson(Map<String, dynamic> json) {
    final rawModules = json['modules'];
    return DeviceFirmwareOverview(
      deviceSn: json['device_sn']?.toString() ?? '',
      deviceModel: json['device_model']?.toString() ?? '',
      isOnline: json['is_online'] == true,
      modules: rawModules is List
          ? rawModules
              .whereType<Map>()
              .map((e) => FirmwareModuleOverview.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : const [],
    );
  }
}

/// 单模块固件状态
class FirmwareModuleOverview {
  const FirmwareModuleOverview({
    required this.target,
    required this.currentVersion,
    required this.latestFirmwareId,
    required this.latestVersion,
    required this.versionState,
    required this.updateAvailable,
    this.changelog = '',
    this.publishedAt,
  });

  /// arm|esp|dsp|bms
  final String target;
  final String currentVersion;

  /// 最新固件 ID；无可用固件时为 0
  final int latestFirmwareId;
  final String latestVersion;

  /// unreported|current|outdated
  final String versionState;
  final bool updateAvailable;
  final String changelog;
  final DateTime? publishedAt;

  bool get isUnreported => versionState == 'unreported';
  bool get isCurrent => versionState == 'current';
  bool get isOutdated => versionState == 'outdated';

  factory FirmwareModuleOverview.fromJson(Map<String, dynamic> json) {
    return FirmwareModuleOverview(
      target: json['target']?.toString() ?? '',
      currentVersion: json['current_version']?.toString() ?? '',
      latestFirmwareId: (json['latest_firmware_id'] as num?)?.toInt() ?? 0,
      latestVersion: json['latest_version']?.toString() ?? '',
      versionState: json['version_state']?.toString() ?? '',
      updateAvailable: json['update_available'] == true,
      changelog: json['changelog']?.toString() ?? '',
      publishedAt:
          DateTime.tryParse(json['published_at']?.toString() ?? ''),
    );
  }
}

/// 单条已发布固件（GET /ota/devices/{sn}/firmware-resources）
class FirmwareResource {
  const FirmwareResource({
    required this.id,
    required this.model,
    required this.version,
    required this.fileUrl,
    required this.targetChip,
    this.changelog = '',
    this.publishedAt,
    this.releaseStatus = '',
    this.fileName = '',
    this.fileSize,
    this.fileSha256 = '',
    this.securityVersion,
    this.releaseSignature = '',
  });

  final int id;
  final String model;
  final String version;
  final String fileUrl;
  final String targetChip;
  final String changelog;
  final DateTime? publishedAt;
  final String releaseStatus;
  final String fileName;
  final int? fileSize;
  final String fileSha256;
  final int? securityVersion;
  final String releaseSignature;

  factory FirmwareResource.fromJson(Map<String, dynamic> json) {
    return FirmwareResource(
      id: (json['id'] as num?)?.toInt() ?? 0,
      model: json['model']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      fileUrl: (json['file_url'] ?? json['download_url'] ?? '').toString(),
      targetChip: json['target_chip']?.toString() ?? '',
      changelog: json['changelog']?.toString() ?? '',
      publishedAt:
          DateTime.tryParse(json['published_at']?.toString() ?? ''),
      releaseStatus: json['release_status']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      fileSize: (json['file_size'] as num?)?.toInt(),
      fileSha256: json['file_sha256']?.toString() ?? '',
      securityVersion: (json['security_version'] as num?)?.toInt(),
      releaseSignature: json['release_signature']?.toString() ?? '',
    );
  }
}

/// POST /ota/trigger 返回的单任务
class OtaTriggerTask {
  const OtaTriggerTask({
    required this.taskId,
    required this.firmwareId,
    required this.targetChip,
    required this.version,
    required this.status,
  });

  final int taskId;
  final int firmwareId;
  final String targetChip;
  final String version;
  final String status;

  factory OtaTriggerTask.fromJson(Map<String, dynamic> json) {
    return OtaTriggerTask(
      taskId: (json['task_id'] as num?)?.toInt() ?? 0,
      firmwareId: (json['firmware_id'] as num?)?.toInt() ?? 0,
      targetChip: json['target_chip']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }
}

/// 历史列表四类筛选 DTO
class FirmwareHistoryFilter {
  const FirmwareHistoryFilter({
    this.deviceSn,
    this.targetChip,
    this.status,
    this.startTime,
    this.endTime,
    this.page = 1,
    this.pageSize = 20,
  });

  final String? deviceSn;
  final String? targetChip;
  final String? status;

  /// UI 本地时区时间，请求时转 ISO8601 UTC
  final DateTime? startTime;
  final DateTime? endTime;
  final int page;
  final int pageSize;

  Map<String, dynamic> toQueryParameters() {
    return {
      if (deviceSn != null && deviceSn!.isNotEmpty) 'device_sn': deviceSn,
      if (targetChip != null && targetChip!.isNotEmpty)
        'target_chip': targetChip,
      if (status != null && status!.isNotEmpty) 'status': status,
      if (startTime != null)
        'start_time': startTime!.toUtc().toIso8601String(),
      if (endTime != null) 'end_time': endTime!.toUtc().toIso8601String(),
      'page': page,
      'page_size': pageSize,
    };
  }

  FirmwareHistoryFilter copyWith({
    String? deviceSn,
    String? targetChip,
    String? status,
    DateTime? startTime,
    DateTime? endTime,
    int? page,
    int? pageSize,
    bool clearDeviceSn = false,
    bool clearTargetChip = false,
    bool clearStatus = false,
    bool clearStartTime = false,
    bool clearEndTime = false,
  }) {
    return FirmwareHistoryFilter(
      deviceSn: clearDeviceSn ? null : (deviceSn ?? this.deviceSn),
      targetChip: clearTargetChip ? null : (targetChip ?? this.targetChip),
      status: clearStatus ? null : (status ?? this.status),
      startTime: clearStartTime ? null : (startTime ?? this.startTime),
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }
}
