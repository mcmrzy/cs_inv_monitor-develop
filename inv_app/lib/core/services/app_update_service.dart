import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// 当下载URL返回的是网页而非直接安装包时抛出此异常
class WebPageUrlException implements Exception {
  final String url;
  WebPageUrlException(this.url);
  @override
  String toString() => 'WebPageUrlException: $url 返回的是网页而非安装包';
}

class AppUpdateInfo {
  final bool hasUpdate;
  final String latestVersionName;
  final int latestVersionCode;
  final String downloadUrl;
  final int fileSize;
  final String fileMd5;
  final String changelog;
  final bool isForce;
  final bool shouldForceUpdate;

  AppUpdateInfo({
    required this.hasUpdate,
    this.latestVersionName = '',
    this.latestVersionCode = 0,
    this.downloadUrl = '',
    this.fileSize = 0,
    this.fileMd5 = '',
    this.changelog = '',
    this.isForce = false,
    this.shouldForceUpdate = false,
  });
}

class AppUpdateService {
  final Dio _dio;

  AppUpdateService(this._dio);

  /// 检查App是否有新版本
  /// [currentVersionCode] 当前App的版本号（整数），如 pubspec.yaml 中的 build number
  Future<AppUpdateInfo> checkUpdate(int currentVersionCode) async {
    final platform = Platform.isIOS ? 'ios' : 'android';
    try {
      final response = await _dio.get(
        '/ota/app/check',
        queryParameters: {
          'platform': platform,
          'version_code': currentVersionCode,
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        final d = data['data'] as Map<String, dynamic>? ?? {};
        return AppUpdateInfo(
          hasUpdate: d['has_update'] == true,
          latestVersionName: d['latest_version_name'] ?? '',
          latestVersionCode: d['latest_version_code'] ?? 0,
          downloadUrl: d['download_url'] ?? '',
          fileSize: d['file_size'] ?? 0,
          fileMd5: d['file_md5'] ?? '',
          changelog: d['changelog'] ?? '',
          isForce: d['is_force'] == true,
          shouldForceUpdate: d['should_force_update'] == true,
        );
      }
      return AppUpdateInfo(hasUpdate: false);
    } catch (e) {
      debugPrint('AppUpdateService.checkUpdate error: $e');
      return AppUpdateInfo(hasUpdate: false);
    }
  }

  /// 打开应用商店（iOS）
  Future<void> openAppStore(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 检测URL是否为外部网页（非直接下载链接）
  /// 通过 HEAD 请求检查 Content-Type
  Future<bool> _isWebPageUrl(String url) async {
    try {
      final checkDio = Dio();
      final response = await checkDio.head(
        url,
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final contentType = response.headers.value('content-type') ?? '';
      return contentType.contains('text/html');
    } catch (_) {
      // HEAD 请求失败时，无法判断，返回 false 继续尝试下载
      return false;
    }
  }

  /// 用浏览器打开URL
  Future<void> openUrlInBrowser(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('无法打开链接: $url');
    }
  }

  /// 下载APK并安装（Android）
  /// [onProgress] 下载进度回调 (0.0 ~ 1.0)
  /// 如果返回的是网页而非安装包，会抛出 [WebPageUrlException]
  Future<void> downloadAndInstall(
    String url,
    String fileName, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // 先检测是否为网页链接
    if (await _isWebPageUrl(url)) {
      throw WebPageUrlException(url);
    }

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$fileName';

    // 使用独立的 Dio 实例下载外部文件，避免带上 baseUrl 和 Auth 头
    final downloadDio = Dio();
    final response = await downloadDio.download(
      url,
      filePath,
      cancelToken: cancelToken,
      options: Options(
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
      ),
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );

    // 再次检查 Content-Type，防止 HEAD 请求不准确的情况
    final contentType = response.headers.value('content-type') ?? '';
    if (contentType.contains('text/html')) {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      throw WebPageUrlException(url);
    }

    // 打开APK安装
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      throw Exception('Cannot open installer: ${result.message}');
    }
  }
}
