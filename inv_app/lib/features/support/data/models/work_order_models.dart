import 'package:inv_app/core/config/app_config.dart';

/// 工单模板兜底数据，与后端 /work-orders/templates 结构一致。
class WorkOrderTemplate {
  static const List<Map<String, dynamic>> fallback = [
    {
      'templateId': 'repair',
      'title': '设备故障',
      'description': '设备运行异常，需要检修',
      'priority': 'high',
    },
    {
      'templateId': 'maintenance',
      'title': '定期维护',
      'description': '设备定期保养维护',
      'priority': 'medium',
    },
    {
      'templateId': 'inspection',
      'title': '设备巡检',
      'description': '设备运行状态巡检',
      'priority': 'low',
    },
    {
      'templateId': 'installation',
      'title': '安装调试',
      'description': '设备安装与参数调试',
      'priority': 'medium',
    },
  ];
}

class WorkOrderItem {
  final String id;
  final String title;
  final String status;
  final String priority;
  final String deviceSn;
  final DateTime createdAt;

  const WorkOrderItem({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.deviceSn,
    required this.createdAt,
  });

  /// 后端同时输出 camelCase 与 snake_case 字段，双兼容解析；
  /// 时间解析失败回退当前时间，避免整条数据丢失。
  factory WorkOrderItem.fromJson(Map<String, dynamic> json) {
    return WorkOrderItem(
      id: json['id']?.toString() ?? '',
      title: (json['title'] ?? '').toString(),
      status: (json['status'] ?? 'open').toString(),
      priority: (json['priority'] ?? '').toString(),
      deviceSn: (json['deviceSn'] ?? json['device_sn'] ?? '').toString(),
      createdAt: _parseTime(json['createdAt'] ?? json['created_at']),
    );
  }

  static DateTime _parseTime(dynamic raw) {
    if (raw == null) return DateTime.now();
    return DateTime.tryParse(raw.toString()) ?? DateTime.now();
  }
}

/// 本地时间格式化：yyyy-MM-dd HH:mm。
String formatWorkOrderTime(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// 工单详情数据模型（GET /work-orders/:id 全字段，camel/snake 双兼容）。
class WorkOrderDetail {
  final String id;
  final String title;
  final String description;
  final String status;
  final String priority;
  final String deviceSn;
  final String creatorName;
  final String assigneeName;
  final String templateType;
  final String resolution;
  final DateTime? slaDeadline;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WorkOrderTimelineEvent> timeline;
  final List<WorkOrderAttachment> attachments;

  const WorkOrderDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.deviceSn,
    required this.creatorName,
    required this.assigneeName,
    required this.templateType,
    required this.resolution,
    this.slaDeadline,
    required this.createdAt,
    required this.updatedAt,
    required this.timeline,
    required this.attachments,
  });

  factory WorkOrderDetail.fromJson(Map<String, dynamic> json) {
    return WorkOrderDetail(
      id: json['id']?.toString() ?? '',
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      status: (json['status'] ?? 'open').toString(),
      priority: (json['priority'] ?? '').toString(),
      deviceSn: (json['deviceSn'] ?? json['device_sn'] ?? '').toString(),
      creatorName:
          (json['creatorName'] ?? json['creator_name'] ?? '').toString(),
      assigneeName:
          (json['assigneeName'] ?? json['assignee_name'] ?? '').toString(),
      templateType:
          (json['templateType'] ?? json['template_type'] ?? '').toString(),
      resolution: (json['resolution'] ?? '').toString(),
      slaDeadline: _tryParse(json['slaDeadline'] ?? json['sla_deadline']),
      createdAt:
          _tryParse(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      updatedAt:
          _tryParse(json['updatedAt'] ?? json['updated_at']) ?? DateTime.now(),
      timeline: (json['timeline'] as List? ?? const [])
          .map((e) => WorkOrderTimelineEvent.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
      attachments: (json['attachments'] as List? ?? const [])
          .map((e) => WorkOrderAttachment.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  static DateTime? _tryParse(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }
}

/// 时间线事件（状态流转记录）。
class WorkOrderTimelineEvent {
  final String status;
  final String operator;
  final String remark;
  final DateTime timestamp;

  const WorkOrderTimelineEvent({
    required this.status,
    required this.operator,
    required this.remark,
    required this.timestamp,
  });

  factory WorkOrderTimelineEvent.fromJson(Map<String, dynamic> json) {
    return WorkOrderTimelineEvent(
      status: (json['status'] ?? '').toString(),
      operator: (json['operator'] ?? '').toString(),
      remark: (json['remark'] ?? '').toString(),
      timestamp: DateTime.tryParse((json['timestamp'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// 工单附件（图片）。
class WorkOrderAttachment {
  final String name;
  final String url;

  const WorkOrderAttachment({required this.name, required this.url});

  factory WorkOrderAttachment.fromJson(Map<String, dynamic> json) {
    return WorkOrderAttachment(
      name: (json['name'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
    );
  }

  /// 后端返回相对路径 /firmware/...；相对路径拼接 API 主机地址。
  String get fullUrl {
    final base = AppConfig.apiBaseUrl;
    final host = base.replaceFirst(RegExp(r'/api/v1/*$'), '');
    return url.startsWith('http') ? url : '$host$url';
  }
}
