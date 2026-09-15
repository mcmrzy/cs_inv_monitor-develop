import 'dart:async';
import 'dart:io' show InternetAddress;

import 'package:flutter/foundation.dart';

import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/network/api_client.dart';

/// 站点域名配置（GET /config/public，无需登录）。
///
/// 后端统一下发部署域名，App 不在构建期硬编码：
/// 迁移服务器时在管理后台「域名配置」改一处，所有端自动跟随。
/// 拉取失败（离线、旧后端无此接口）时静默保留构建期默认值。
/// 仅使用前端域（邀请链接等分享场景）；下载 URL 以服务端下发为准，
/// 不做受信域名白名单（换下载域无需发版）。
class DomainConfigService {
  DomainConfigService(this._apiClient);

  final ApiClient _apiClient;

  String _frontendBaseUrl = AppConfig.frontendBaseUrl;

  /// Web 管理后台地址（邀请链接等分享场景）。
  String get frontendBaseUrl => _frontendBaseUrl;

  /// 拉取后端域名配置。任何失败都静默忽略——构建期默认值始终可用。
  Future<void> refresh() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>('/config/public');
      final body = response.data;
      if (body is! Map<String, dynamic> || body['code'] != 0) return;
      final data = (body['data'] as Map<String, dynamic>?) ?? const {};
      final frontend = _normalizeBaseURL(data['frontend_base_url'] as String?);
      if (frontend != null) {
        _frontendBaseUrl = frontend;
      }
    } catch (e) {
      debugPrint('DomainConfigService.refresh error: $e');
    }
  }

  /// 仅接受 http/https 且主机非 localhost / 私网 / 环回；
  /// 非法值返回 null（保留构建期默认），与后端 normalizeBaseURL 规则一致。
  String? _normalizeBaseURL(String? raw) {
    if (raw == null) return null;
    final v = raw.trim();
    if (v.isEmpty) return null;
    final uri = Uri.tryParse(v);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal')) {
      return null;
    }
    final address = InternetAddress.tryParse(host);
    if (address != null && _isRestrictedAddress(address)) {
      return null;
    }
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  /// 环回 / 链路本地 / 多播 / 私网（IPv4 RFC1918、IPv6 fc00::/7）/ 未指定地址
  bool _isRestrictedAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
      return true;
    }
    final o = address.rawAddress;
    if (o.length == 4) {
      return o[0] == 0 ||
          o[0] == 10 ||
          (o[0] == 100 && o[1] >= 64 && o[1] < 128) || // CGNAT 100.64/10
          (o[0] == 127) ||
          (o[0] == 169 && o[1] == 254) ||
          (o[0] == 172 && o[1] >= 16 && o[1] <= 31) ||
          (o[0] == 192 && o[1] == 168);
    }
    if (o.length == 16) {
      return (o[0] & 0xfe) == 0xfc; // IPv6 unique local fc00::/7
    }
    return false;
  }
}
