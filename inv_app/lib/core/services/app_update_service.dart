import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

/// 当下载URL返回的是网页而非直接安装包时抛出此异常
class WebPageUrlException implements Exception {
  final String url;
  WebPageUrlException(this.url);
  @override
  String toString() => 'WebPageUrlException: $url 返回的是网页而非安装包';
}

/// 下载URL不满足安全约束（非 https / 非受信域名）时抛出此异常
class InsecureDownloadUrlException implements Exception {
  final String url;
  final String reason;
  InsecureDownloadUrlException(this.url, this.reason);
  @override
  String toString() => 'InsecureDownloadUrlException: $url ($reason)';
}

/// 下载文件哈希校验失败时抛出此异常（安装包可能被篡改，禁止安装）
class ChecksumMismatchException implements Exception {
  final String expected;
  final String actual;
  ChecksumMismatchException(this.expected, this.actual);
  @override
  String toString() => 'ChecksumMismatchException: expected $expected, got $actual';
}

class AppUpdateInfo {
  final bool hasUpdate;
  final String latestVersionName;
  final int latestVersionCode;
  final String downloadUrl;
  final int fileSize;
  final String fileMd5;
  final String fileSha256;
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
    this.fileSha256 = '',
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
          fileSha256: d['file_sha256'] ?? '',
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
  /// [expectedSha256]/[expectedMd5] 服务端下发的安装包哈希，
  ///   SHA-256 优先；下载完成后强制比对，不匹配则删除文件并拒绝安装。
  /// 如果返回的是网页而非安装包，会抛出 [WebPageUrlException]；
  /// 下载URL不满足安全约束时抛出 [InsecureDownloadUrlException]；
  /// 哈希校验失败时抛出 [ChecksumMismatchException]。
  Future<void> downloadAndInstall(
    String url,
    String fileName, {
    String expectedSha256 = '',
    String expectedMd5 = '',
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // 安全约束：仅允许 https（调试模式豁免本机/局域网地址），且域名需受信
    _assertSecureDownloadUrl(url);

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

    // 完整性校验：哈希不匹配说明安装包可能被篡改，删除文件并拒绝安装
    await _verifyPackageHash(
      filePath,
      expectedSha256: expectedSha256,
      expectedMd5: expectedMd5,
    );

    // 打开APK安装
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      throw Exception('Cannot open installer: ${result.message}');
    }
  }

  /// 下载URL安全约束：
  /// 1. 必须为 https（调试模式豁免回环/私有网段，便于本地联调）；
  /// 2. 域名必须与 API/前端基址同源（受信域名白名单）。
  void _assertSecureDownloadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw InsecureDownloadUrlException(url, 'invalid url');
    }

    final isLocalHost = _isLoopbackOrPrivateHost(uri.host);
    if (uri.scheme != 'https') {
      if (kDebugMode && isLocalHost) return; // 本地联调豁免
      throw InsecureDownloadUrlException(url, 'https required');
    }
    if (isLocalHost) return;

    final trustedHosts = <String>{
      Uri.tryParse(AppConfig.apiBaseUrl)?.host ?? '',
      Uri.tryParse(AppConfig.frontendBaseUrl)?.host ?? '',
    }..remove('');
    if (trustedHosts.isNotEmpty && !trustedHosts.contains(uri.host)) {
      throw InsecureDownloadUrlException(url, 'host not in trusted list');
    }
  }

  static bool _isLoopbackOrPrivateHost(String host) {
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return true;
    }
    final ip = InternetAddress.tryParse(host);
    if (ip == null || ip.type != InternetAddressType.IPv4) return false;
    final parts = ip.rawAddress;
    return parts[0] == 10 ||
        parts[0] == 192 && parts[1] == 168 ||
        parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31;
  }

  /// 流式计算文件哈希并比对：SHA-256 优先，其次 MD5。
  /// 两者均未提供时记录警告（此时依赖 https 传输层保护）。
  Future<void> _verifyPackageHash(
    String filePath, {
    required String expectedSha256,
    required String expectedMd5,
  }) async {
    final file = File(filePath);

    Future<String> digestOf(Hash hash) async {
      // 流式计算摘要，避免大 APK 全量读入内存
      final digest = await hash.bind(file.openRead()).first;
      return digest.toString();
    }

    if (expectedSha256.isNotEmpty) {
      final actual = await digestOf(sha256);
      if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
        if (await file.exists()) await file.delete();
        throw ChecksumMismatchException(expectedSha256, actual);
      }
      return;
    }
    if (expectedMd5.isNotEmpty) {
      final actual = await digestOf(md5);
      if (actual.toLowerCase() != expectedMd5.toLowerCase()) {
        if (await file.exists()) await file.delete();
        throw ChecksumMismatchException(expectedMd5, actual);
      }
      return;
    }
    debugPrint('AppUpdateService: no hash provided by server, '
        'skipping package integrity check (https transport only)');
  }
}
