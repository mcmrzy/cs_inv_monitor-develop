import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:inv_app/core/services/service_locator.dart';

/// 帮助中心配置（文档 URL / 客服电话 / FAQ 列表）
///
/// 从后端 GET /config/help-center 动态拉取（登录即可，Dio 相对路径，
/// apiBaseUrl 已含 /api/v1）；失败时回退内置默认值，并缓存会话内
/// 最近一次成功响应，保证离线/后端异常时页面仍可用。
class HelpCenterConfig {
  final Map<String, String> docs;
  final String servicePhone;
  final List<FaqItem> faqs;

  const HelpCenterConfig({
    required this.docs,
    required this.servicePhone,
    required this.faqs,
  });

  /// 设备说明书 URL（空串表示未配置，前端提示"文档暂未开放"）
  String get deviceManualUrl => docs['device'] ?? '';

  /// App 说明书 URL
  String get appManualUrl => docs['app'] ?? '';

  /// 系统说明书 URL
  String get systemManualUrl => docs['system'] ?? '';

  factory HelpCenterConfig.fromJson(Map<String, dynamic> json) {
    final docs = (json['docs'] as Map? ?? const {})
        .map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    final faqs = (json['faqs'] as List? ?? const [])
        .map((e) => FaqItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return HelpCenterConfig(
      docs: Map<String, String>.from(docs),
      servicePhone: json['phone'] as String? ?? '',
      faqs: faqs,
    );
  }

  /// 内置默认值（与后端缺省配置一致）
  static const HelpCenterConfig fallback = HelpCenterConfig(
    docs: {'device': '', 'app': '', 'system': ''},
    servicePhone: '400-888-8888',
    faqs: [],
  );
}

/// 常见问题条目
class FaqItem {
  final String question;
  final String answer;

  const FaqItem({required this.question, required this.answer});

  factory FaqItem.fromJson(Map<String, dynamic> json) {
    return FaqItem(
      question: json['q'] as String? ?? '',
      answer: json['a'] as String? ?? '',
    );
  }
}

/// 帮助中心配置服务
class HelpCenterConfigService {
  HelpCenterConfigService({Dio? dio}) : _dio = dio;

  final Dio? _dio;

  /// 会话内最近一次成功响应（跨页面实例共享，离线时兜底）
  static HelpCenterConfig? _cached;

  /// 拉取配置；失败回退 [HelpCenterConfig.fallback]（不抛异常）
  Future<HelpCenterConfig> fetch() async {
    if (_cached != null) return _cached!;
    final dio = _dio ?? getIt<Dio>();
    try {
      final response = await dio.get('/config/help-center');
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        final cfg = HelpCenterConfig.fromJson(
          Map<String, dynamic>.from((data['data'] as Map?) ?? const {}),
        );
        _cached = cfg;
        return cfg;
      }
    } catch (e) {
      debugPrint('[HelpCenterConfigService] fetch failed: $e');
    }
    return HelpCenterConfig.fallback;
  }
}
