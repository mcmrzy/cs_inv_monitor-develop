import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import 'domain_config_service.dart';

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

  /// 站点域名配置：后端下发的下载域会合并进受信主机白名单；可空（单测直连）。
  final DomainConfigService? _domainConfig;

  AppUpdateService(this._dio, {DomainConfigService? domainConfig})
      : _domainConfig = domainConfig;

  /// 分片并发下载的启用阈值（小于该体积不值得分片）
  static const int _chunkThresholdBytes = 4 << 20;

  /// 分片数量：CDN 单连接限速时，并发分片可显著提速
  static const int _chunkCount = 4;

  /// 读取当前安装包的真实版本号（整数）：
  /// Android 取 versionCode，桌面端取可执行文件版本信息中的 build number。
  /// 读取失败时回退到编译期常量 [AppConfig.versionCode]。
  Future<int> resolveCurrentVersionCode() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final parsed = int.tryParse(info.buildNumber.trim());
      if (parsed != null && parsed > 0) return parsed;
    } catch (e) {
      debugPrint('AppUpdateService.resolveCurrentVersionCode fallback: $e');
    }
    return AppConfig.versionCode;
  }

  /// 检查App是否有新版本
  /// [currentVersionCode] 当前App的版本号（整数），传 [resolveCurrentVersionCode] 的返回值
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
  /// [expectedSize] 服务端下发的安装包字节数；响应缺少 Content-Length（如 CDN
  ///   分块传输）时用它计算进度，仍拿不到则回调 progress < 0（进度未知）。
  /// [onProgress] 下载进度回调：progress 为 0.0 ~ 1.0，< 0 表示总大小未知；
  ///   第二参数为已接收字节数。
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
    int expectedSize = 0,
    void Function(double progress, int receivedBytes)? onProgress,
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

    // CDN 往往对单连接限速（实测 4 并发吞吐可达单连接的数倍到数十倍）：
    // 已知文件大小且足够大时用 Range 分片并发下载，任何异常都回退到单流。
    var downloaded = false;
    if (expectedSize >= _chunkThresholdBytes) {
      downloaded = await _downloadInChunks(
        url,
        filePath,
        expectedSize,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      if (!downloaded) onProgress?.call(0, 0);
    }

    if (!downloaded) {
      // 使用独立的 Dio 实例下载外部文件，避免带上 baseUrl 和 Auth 头；
      // 设置接收超时，避免 CDN 卡住时界面永远停在"下载中"。
      final downloadDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final response = await downloadDio.download(
        url,
        filePath,
        cancelToken: cancelToken,
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
        onReceiveProgress: (received, total) {
          if (onProgress == null) return;
          // 分块传输（无 Content-Length）时退回服务端下发的文件大小
          final effectiveTotal = total > 0 ? total : expectedSize;
          onProgress(effectiveTotal > 0 ? received / effectiveTotal : -1, received);
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

  /// 计算 [total] 字节切分为 [count] 片后的字节区间（闭区间），末片对齐到 total-1。
  /// 纯函数，便于单测。
  static List<(int, int)> chunkRanges(int total, int count) {
    if (total <= 0 || count <= 0) return const [];
    final chunkSize = (total / count).ceil();
    final ranges = <(int, int)>[];
    for (var i = 0; i < count; i++) {
      final start = i * chunkSize;
      if (start >= total) break;
      final end = start + chunkSize - 1 >= total ? total - 1 : start + chunkSize - 1;
      ranges.add((start, end));
    }
    return ranges;
  }

  /// 分片并发下载：各片写入独立临时文件后顺序合并为 [filePath]。
  /// 任一分片不是 206、字节数不符或发生异常都返回 false（并清理分片），
  /// 由调用方回退到单流下载。
  Future<bool> _downloadInChunks(
    String url,
    String filePath,
    int total, {
    void Function(double progress, int receivedBytes)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final ranges = chunkRanges(total, _chunkCount);
    if (ranges.length < 2) return false;

    final received = List<int>.filled(ranges.length, 0);
    final partPaths = <String>[];

    void report() {
      if (onProgress == null) return;
      final sum = received.fold<int>(0, (a, b) => a + b);
      onProgress(sum / total, sum);
    }

    try {
      final futures = <Future<void>>[];
      for (var i = 0; i < ranges.length; i++) {
        final (start, end) = ranges[i];
        final partPath = '$filePath.part$i';
        partPaths.add(partPath);
        futures.add(
          _downloadChunk(
            url,
            partPath,
            start,
            end,
            index: i,
            received: received,
            onProgress: report,
            cancelToken: cancelToken,
          ),
        );
      }
      await Future.wait(futures);

      final out = File(filePath).openWrite();
      try {
        for (final partPath in partPaths) {
          await out.addStream(File(partPath).openRead());
        }
      } finally {
        await out.close();
      }
      return await File(filePath).length() == total;
    } catch (e) {
      debugPrint('AppUpdateService chunked download fallback: $e');
      return false;
    } finally {
      for (final partPath in partPaths) {
        final part = File(partPath);
        if (await part.exists()) {
          try {
            await part.delete();
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _downloadChunk(
    String url,
    String partPath,
    int start,
    int end, {
    required int index,
    required List<int> received,
    required void Function() onProgress,
    CancelToken? cancelToken,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    final response = await dio.download(
      url,
      partPath,
      cancelToken: cancelToken,
      options: Options(
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
        headers: {'Range': 'bytes=$start-$end'},
      ),
      onReceiveProgress: (count, _) {
        received[index] = count;
        onProgress();
      },
    );
    if (response.statusCode != 206) {
      throw StateError('range not honored: HTTP ${response.statusCode}');
    }
    final expected = end - start + 1;
    final actual = await File(partPath).length();
    if (actual != expected) {
      throw StateError('chunk size mismatch: $actual != $expected');
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
      ...AppConfig.trustedDownloadHosts.split(',').map((h) => h.trim()),
      // 后端「域名配置」下发的下载域（管理后台改域名后无需发新版）
      ...?_domainConfig?.trustedDownloadHosts,
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
