class DeviceFirmwareHistory {
  const DeviceFirmwareHistory({
    required this.id,
    required this.deviceSn,
    required this.target,
    required this.oldVersion,
    required this.newVersion,
    required this.status,
    required this.changelog,
    required this.updatedAt,
    this.errorMessage = '',
  });

  final int id;
  final String deviceSn;
  final String target;
  final String oldVersion;
  final String newVersion;
  final String status;
  final String changelog;
  final DateTime? updatedAt;
  final String errorMessage;

  factory DeviceFirmwareHistory.fromJson(Map<String, dynamic> json) {
    return DeviceFirmwareHistory(
      id: (json['id'] as num?)?.toInt() ?? 0,
      deviceSn: json['device_sn']?.toString() ?? '',
      target: json['target_chip']?.toString() ?? '',
      oldVersion: json['old_version']?.toString() ?? '',
      newVersion: json['firmware_version']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      changelog: json['changelog']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
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
