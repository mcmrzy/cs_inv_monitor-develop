class CommandResult {
  final String status;
  final String message;
  final int timestamp;
  final String deviceSn;

  const CommandResult({
    required this.status,
    required this.message,
    required this.timestamp,
    required this.deviceSn,
  });

  factory CommandResult.fromJson(
    Map<String, dynamic> json, {
    String deviceSn = '',
  }) {
    return CommandResult(
      status: json['status'] as String? ?? '',
      message: json['message'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? 0,
      deviceSn: deviceSn,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'message': message,
      'timestamp': timestamp,
      'device_sn': deviceSn,
    };
  }

  bool get isSuccess => status == 'success';
}
