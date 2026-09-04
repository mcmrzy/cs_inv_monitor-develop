import 'package:uuid/uuid.dart';

/// 生成离线操作日志 ID（UUID v4，服务端按 user_id + log_id 幂等去重）
String newOfflineLogId() => const Uuid().v4();
