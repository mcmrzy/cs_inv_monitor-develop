import 'dart:async';

import 'package:app_links/app_links.dart';

/// 解析后的绑定链接参数
class BindLink {
  final String sn;
  final String pin;

  const BindLink({required this.sn, required this.pin});

  /// 去重键：同一链接（sn|pin 组合）只处理一次
  String get dedupeKey => '$sn|$pin';
}

/// 智能链接 Deep Link 服务：接收 csinv://bind?sn=&pin=
///
/// 铭牌二维码中的智能链接（`https://<host>/bind?sn=xxx&pin=xxx`）由网页中间页
/// bind.html 负责：已安装 App 时跳转到本 scheme；未安装时展示下载引导。
class DeepLinkService {
  final AppLinks _appLinks = AppLinks();

  /// 纯解析（可单测）：csinv://bind?sn=xxx&pin=yyy → BindLink
  static BindLink? parse(Uri uri) {
    if (uri.scheme != 'csinv' || uri.host != 'bind') return null;
    final sn = uri.queryParameters['sn']?.trim().toUpperCase();
    final pin = uri.queryParameters['pin']?.trim();
    if (sn == null || sn.isEmpty || !RegExp(r'^[A-Za-z0-9]{16}$').hasMatch(sn)) {
      return null;
    }
    return BindLink(sn: sn, pin: pin ?? '');
  }

  /// 冷启动初始链接
  Future<BindLink?> getInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      return uri == null ? null : parse(uri);
    } catch (_) {
      return null; // 非 AppLinks URI 或其他错误静默
    }
  }

  /// 热启动链接流
  Stream<BindLink?> get linkStream {
    return _appLinks.uriLinkStream
        .map(parse)
        .handleError((Object _) {}); // 避免流错误中断
  }
}
