class DeviceFirmwareHistory {
  const DeviceFirmwareHistory({
    required this.id,
    required this.deviceSn,
    required this.firmwareId,
    this.rollbackFirmwareId = 0,
    required this.target,
    required this.oldVersion,
    required this.firmwareVersion,
    required this.status,
    this.progress = 0,
    this.stage = '',
    this.changelog = '',
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.errorMessage = '',
  });

  final int id;
  final String deviceSn;

  /// 本次升级安装的固件 ID，无关联时为 0。
  final int firmwareId;

  /// 回退目标固件 ID。它指向 [oldVersion] 对应的固件资源，不能用本次
  /// 已安装的 [firmwareId] 代替。
  final int rollbackFirmwareId;
  final String target;
  final String oldVersion;

  /// 新版本号（JSON 字段 firmware_version）
  final String firmwareVersion;
  final String status;
  final int progress;

  /// 设备上报的原始阶段(accepted/downloading/verifying/installing/rebooting/
  /// succeeded/failed)，比 status 细，用于把「升级中」拆成分阶段展示。空=未知。
  final String stage;
  final String changelog;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final String errorMessage;

  /// 兼容旧命名：升级目标版本
  String get newVersion => firmwareVersion;

  /// 成功且服务端明确给出旧版本固件 ID 的记录才可回退。
  bool get canRollback =>
      status == 'success' && rollbackFirmwareId > 0;

  factory DeviceFirmwareHistory.fromJson(Map<String, dynamic> json) {
    return DeviceFirmwareHistory(
      id: (json['id'] as num?)?.toInt() ?? 0,
      deviceSn: json['device_sn']?.toString() ?? '',
      firmwareId: (json['firmware_id'] as num?)?.toInt() ?? 0,
      rollbackFirmwareId:
          (json['rollback_firmware_id'] as num?)?.toInt() ?? 0,
      target: json['target_chip']?.toString() ?? '',
      oldVersion: json['old_version']?.toString() ?? '',
      firmwareVersion: json['firmware_version']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      stage: json['stage']?.toString() ?? '',
      changelog: json['changelog']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(
          (json['updated_at'] ?? json['created_at'])?.toString() ?? ''),
      completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? ''),
      errorMessage: json['error_message']?.toString() ?? '',
    );
  }
}

class DeviceFirmwareHistoryPage {
  const DeviceFirmwareHistoryPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<DeviceFirmwareHistory> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => items.length < total && page * pageSize < total;
}
