class OfflineAction {
  final String id;
  final String type;
  final String sn;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final bool synced;

  const OfflineAction({
    required this.id,
    required this.type,
    required this.sn,
    required this.data,
    required this.timestamp,
    this.synced = false,
  });

  OfflineAction copyWith({
    String? id,
    String? type,
    String? sn,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    bool? synced,
  }) {
    return OfflineAction(
      id: id ?? this.id,
      type: type ?? this.type,
      sn: sn ?? this.sn,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      synced: synced ?? this.synced,
    );
  }

  factory OfflineAction.fromJson(Map<String, dynamic> json) {
    return OfflineAction(
      id: json['id'] as String,
      type: json['type'] as String,
      sn: json['sn'] as String,
      data: (json['data'] as Map<String, dynamic>?) ?? {},
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      synced: json['synced'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'sn': sn,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
        'synced': synced,
      };
}
