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

  /// 内置默认值（FAQ 与后端缺省配置/database/help_center_config.sql 一致）
  static const HelpCenterConfig fallback = HelpCenterConfig(
    docs: {'device': '', 'app': '', 'system': ''},
    servicePhone: '400-888-8888',
    faqs: [
      FaqItem(
        question: '如何绑定光伏逆变器设备？',
        answer: '在App「设备」页面点击右上角「+添加设备」，扫描设备铭牌上的二维码或手动输入序列号（SN），设备会自动绑定到您的账号。',
      ),
      FaqItem(
        question: '设备显示离线怎么办？',
        answer: '请检查设备电源和WiFi网络是否正常。可尝试重启设备（断电30秒后重新上电），或在App中重新配网。如长时间离线，可通过帮助中心提交工单。',
      ),
      FaqItem(
        question: '如何查看实时发电数据？',
        answer: '进入「电站」页面选择对应电站，可查看发电功率、日发电量等实时数据。点击设备可查看详细的直流/交流参数。',
      ),
      FaqItem(
        question: '如何升级设备固件？',
        answer: '当有新固件可用时，App会在设备详情页显示升级提示。点击「立即升级」即可。升级期间不影响正常发电，升级完成后设备自动重启。',
      ),
      FaqItem(
        question: '如何提交故障工单？',
        answer: '进入帮助中心「我的工单」，点击右下角「提交工单」按钮，填写标题和问题描述，可附上现场图片（最多5张），便于技术人员快速定位问题。',
      ),
      FaqItem(
        question: '如何联系客服？',
        answer: '工作日9:00-18:00可拨打客服热线400-888-8888，或通过帮助中心的「在线客服」功能。非工作时间请提交工单，我们会在次日回复。',
      ),
      FaqItem(
        question: '设备绑定后可以转移给其他人吗？',
        answer: '可以。在App中解绑设备后，其他人可重新绑定。代理商和安装商可通过管理后台批量转移设备归属。',
      ),
      FaqItem(
        question: 'App支持哪些功能？',
        answer: '支持实时监控（发电功率、电量）、远程控制（开关机、功率限制）、告警通知（设备故障推送）、OTA固件升级、工单管理、WiFi配网等。',
      ),
      FaqItem(
        question: '能量流图显示的数据准确吗？',
        answer: '能量流图展示的是设备实时上报的数据，每3秒自动刷新。数据精确到小数点后两位，与设备显示屏数值基本一致。',
      ),
      FaqItem(
        question: '如何修改App的语言？',
        answer: '进入「设置→个人资料」，点击语言切换按钮。目前支持中文和English，切换后界面语言立即生效。',
      ),
    ],
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
        // 后端成功返回但 faqs 为空时，回退内置 FAQ，避免页面空白
        final effective = cfg.faqs.isEmpty
            ? HelpCenterConfig(
                docs: cfg.docs,
                servicePhone: cfg.servicePhone,
                faqs: HelpCenterConfig.fallback.faqs,
              )
            : cfg;
        _cached = effective;
        return effective;
      }
    } catch (e) {
      debugPrint('[HelpCenterConfigService] fetch failed: $e');
    }
    return HelpCenterConfig.fallback;
  }
}
