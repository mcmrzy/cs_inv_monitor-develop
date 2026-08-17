import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 已下载固件的信息（含离线升级所需的签名元数据）。
///
/// 元数据（目标芯片/版本/签名/安全版本）在下载时一并持久化，
/// 支持无网环境下从已下载列表选择固件直接本地升级。
class DownloadedFirmwareInfo {
  final int firmwareId;
  final String filePath;
  final String fileName;
  final int fileSize;

  /// 目标芯片（esp/arm），旧记录可能缺失
  final String? targetChip;

  /// 固件版本号，旧记录可能缺失
  final String? version;

  /// 固件 SHA-256（小写十六进制）
  final String? sha256;

  /// Ed25519 发布签名（Base64），旧记录可能缺失
  final String? signature;

  /// 防回滚安全版本号，旧记录可能缺失
  final int? securityVersion;

  const DownloadedFirmwareInfo({
    required this.firmwareId,
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    this.targetChip,
    this.version,
    this.sha256,
    this.signature,
    this.securityVersion,
  });

  /// 是否具备本地升级所需的完整元数据
  bool get hasUpgradeMetadata =>
      (targetChip?.isNotEmpty ?? false) &&
      (version?.isNotEmpty ?? false) &&
      (sha256?.isNotEmpty ?? false) &&
      (signature?.isNotEmpty ?? false) &&
      (securityVersion ?? 0) > 0;
}

/// 下载进度事件：携带 firmwareId，按任务分流，
/// 避免并发下载多个固件时进度事件互相污染
class DownloadProgressEvent {
  final int firmwareId;
  final double progress;

  const DownloadProgressEvent({required this.firmwareId, required this.progress});
}

class FirmwareDownloadService {
  final Dio _dio;
  final SharedPreferences _sharedPreferences;

  static const String _keyPrefix = 'firmware_path_';
  static const String _keySizePrefix = 'firmware_size_';
  static const String _keySHA256Prefix = 'firmware_sha256_';
  static const String _keyMetaPrefix = 'firmware_meta_';

  final StreamController<DownloadProgressEvent> _progressController =
      StreamController<DownloadProgressEvent>.broadcast();

  /// dispose 后下载协程可能仍在运行，守卫避免向已关闭的 controller add 抛异常
  bool _disposed = false;

  /// 并发守卫：同一时刻仅允许一个下载任务，
  /// 避免多页面/多次点击并发下载互相干扰
  int? _activeDownloadId;

  /// 下载进度流（按 firmwareId 分流，页面自行过滤关注的任务）
  Stream<DownloadProgressEvent> get progressStream =>
      _progressController.stream;

  FirmwareDownloadService(this._dio, this._sharedPreferences);

  void _emit(int firmwareId, double progress) {
    if (_disposed || _progressController.isClosed) return;
    _progressController.add(
      DownloadProgressEvent(firmwareId: firmwareId, progress: progress),
    );
  }

  Future<String> downloadFirmware({
    required String url,
    required String fileName,
    required int firmwareId,
    int? expectedSize,
    String? expectedSha256,
    String? targetChip,
    String? version,
    String? signature,
    int? securityVersion,
    void Function(int received, int total)? onProgress,
  }) async {
    // 并发守卫：已有下载任务进行中时拒绝新任务，由调用方提示用户
    if (_activeDownloadId != null) {
      throw StateError(
        'Another firmware download is in progress (id=$_activeDownloadId)',
      );
    }
    _activeDownloadId = firmwareId;

    final dir = await _getFirmwareDir();
    final filePath = '${dir.path}/$fileName';
    final file = File(filePath);

    int downloadedBytes = 0;
    if (await file.exists()) {
      downloadedBytes = await file.length();
    }

    _emit(firmwareId, 0.0);

    try {
      try {
        // 断点续传
        if (downloadedBytes > 0) {
          try {
            final response = await _dio.download(
              url,
              filePath,
              fileAccessMode: FileAccessMode.append,
              options: Options(
                headers: {'Range': 'bytes=$downloadedBytes-'},
              ),
              onReceiveProgress: (received, total) {
                final overallTotal = total > 0 ? total + downloadedBytes : 0;
                final progress = overallTotal > 0
                    ? (downloadedBytes + received) / overallTotal
                    : 0.0;
                _emit(firmwareId, progress.clamp(0.0, 1.0));
                onProgress?.call(downloadedBytes + received, overallTotal);
              },
              deleteOnError: false,
            );
            // A server that ignores Range returns 200. Appending that response would
            // corrupt the file, so restart once from byte zero.
            if (response.statusCode != HttpStatus.partialContent) {
              await file.delete();
              await _dio.download(
                url,
                filePath,
                onReceiveProgress: onProgress,
                deleteOnError: false,
              );
            }
          } on DioException catch (e) {
            // 416 only means the range is unsatisfiable; integrity still must pass.
            if (e.response?.statusCode == 416) {
              final savedFile = File(filePath);
              await _verifyFirmware(savedFile, expectedSize, expectedSha256);
              final fileSize = await savedFile.length();
              await _sharedPreferences.setString(
                '$_keyPrefix$firmwareId',
                filePath,
              );
              await _sharedPreferences.setInt(
                '$_keySizePrefix$firmwareId',
                fileSize,
              );
              if (expectedSha256 != null) {
                await _sharedPreferences.setString(
                  '$_keySHA256Prefix$firmwareId',
                  expectedSha256.toLowerCase(),
                );
              }
              await _saveMetadata(
                firmwareId,
                targetChip: targetChip,
                version: version,
                signature: signature,
                securityVersion: securityVersion,
              );
              _emit(firmwareId, 1.0);
              return filePath;
            }
            rethrow;
          }
        } else {
          await _dio.download(
            url,
            filePath,
            onReceiveProgress: (received, total) {
              final progress = total > 0 ? received / total : 0.0;
              _emit(firmwareId, progress.clamp(0.0, 1.0));
              onProgress?.call(received, total);
            },
            deleteOnError: false,
          );
        }

        final savedFile = File(filePath);
        await _verifyFirmware(savedFile, expectedSize, expectedSha256);
        final fileSize = await savedFile.length();

        await _sharedPreferences.setString('$_keyPrefix$firmwareId', filePath);
        await _sharedPreferences.setInt('$_keySizePrefix$firmwareId', fileSize);
        if (expectedSha256 != null) {
          await _sharedPreferences.setString(
            '$_keySHA256Prefix$firmwareId',
            expectedSha256.toLowerCase(),
          );
        }
        // 持久化离线升级所需元数据（无网时从已下载列表直接本地升级）
        await _saveMetadata(
          firmwareId,
          targetChip: targetChip,
          version: version,
          signature: signature,
          securityVersion: securityVersion,
        );

        _emit(firmwareId, 1.0);

        return filePath;
      } catch (e) {
        _emit(firmwareId, -1.0);
        rethrow;
      }
    } finally {
      // 无论成功/失败/取消都释放并发守卫
      _activeDownloadId = null;
    }
  }

  /// 持久化固件升级元数据（目标芯片/版本/签名/安全版本）。
  /// 元数据非空时才写入，避免覆盖已有记录为空值。
  Future<void> _saveMetadata(
    int firmwareId, {
    String? targetChip,
    String? version,
    String? signature,
    int? securityVersion,
  }) async {
    if ((targetChip?.isEmpty ?? true) &&
        (version?.isEmpty ?? true) &&
        (signature?.isEmpty ?? true) &&
        (securityVersion ?? 0) <= 0) {
      return;
    }
    final meta = <String, dynamic>{
      if (targetChip != null && targetChip.isNotEmpty) 'target_chip': targetChip,
      if (version != null && version.isNotEmpty) 'version': version,
      if (signature != null && signature.isNotEmpty) 'signature': signature,
      if (securityVersion != null && securityVersion > 0)
        'security_version': securityVersion,
    };
    await _sharedPreferences.setString(
      '$_keyMetaPrefix$firmwareId',
      jsonEncode(meta),
    );
  }

  /// 读取固件元数据（旧记录缺失时返回空 Map）
  Map<String, dynamic> _readMetadata(int firmwareId) {
    final raw = _sharedPreferences.getString('$_keyMetaPrefix$firmwareId');
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return const {};
  }

  /// 扫描 SharedPreferences 中所有 `firmware_path_*` 记录，返回有效（文件存在且
  /// 大小/SHA-256 校验通过）的已下载固件列表。
  /// 失效记录（文件缺失 / 校验失败）会被自动清理，与 [isFirmwareDownloaded] 行为一致。
  Future<List<DownloadedFirmwareInfo>> listDownloadedFirmwares() async {
    final result = <DownloadedFirmwareInfo>[];
    for (final key in _sharedPreferences.getKeys()) {
      if (!key.startsWith(_keyPrefix)) continue;
      final id = int.tryParse(key.substring(_keyPrefix.length));
      if (id == null || id <= 0) continue;

      final path = _sharedPreferences.getString(key);
      if (path == null || path.isEmpty) {
        await _clearDownloadedRecord(id);
        continue;
      }

      final file = File(path);
      if (!await file.exists()) {
        await _clearDownloadedRecord(id);
        continue;
      }

      // 与 isFirmwareDownloaded 等价的完整性校验（校验失败时内部自动清理记录）
      if (await isFirmwareDownloaded(id)) {
        final meta = _readMetadata(id);
        result.add(
          DownloadedFirmwareInfo(
            firmwareId: id,
            filePath: path,
            fileName: path.split(RegExp(r'[/\\]')).last,
            fileSize: await file.length(),
            targetChip: meta['target_chip'] as String?,
            version: meta['version'] as String?,
            sha256:
                _sharedPreferences.getString('$_keySHA256Prefix$id'),
            signature: meta['signature'] as String?,
            securityVersion: (meta['security_version'] as num?)?.toInt(),
          ),
        );
      }
    }
    // 按 id 升序排序，保证列表顺序稳定
    result.sort((a, b) => a.firmwareId.compareTo(b.firmwareId));
    // 终态清理：删除无持久化记录的孤儿固件文件，避免缓存持续膨胀
    await cleanupOrphanedFiles();
    return result;
  }

  /// 清理孤儿固件文件：固件目录中存在但无 `firmware_path_*` 记录指向的文件
  /// （下载中断后记录丢失/记录被清理后的残留）在终态统一删除
  Future<void> cleanupOrphanedFiles() async {
    try {
      final recorded = <String>{};
      for (final key in _sharedPreferences.getKeys()) {
        if (!key.startsWith(_keyPrefix)) continue;
        final path = _sharedPreferences.getString(key);
        if (path != null && path.isNotEmpty) {
          recorded.add(path);
        }
      }
      final dir = await _getFirmwareDir();
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && !recorded.contains(entity.path)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {
      // 清理失败不影响主流程
    }
  }

  /// 清理某个 firmwareId 的全部持久化记录（路径/大小/SHA-256/元数据）。
  Future<void> _clearDownloadedRecord(int firmwareId) async {
    await _sharedPreferences.remove('$_keyPrefix$firmwareId');
    await _sharedPreferences.remove('$_keySizePrefix$firmwareId');
    await _sharedPreferences.remove('$_keySHA256Prefix$firmwareId');
    await _sharedPreferences.remove('$_keyMetaPrefix$firmwareId');
  }

  Future<void> _verifyFirmware(
    File file,
    int? expectedSize,
    String? expectedSha256,
  ) async {
    if (expectedSize != null &&
        expectedSize > 0 &&
        await file.length() != expectedSize) {
      await file.delete();
      throw const FormatException('Firmware size verification failed');
    }
    final normalized = expectedSha256?.trim().toLowerCase() ?? '';
    if (normalized.isNotEmpty) {
      final actual = (await sha256.bind(file.openRead()).first).toString();
      if (actual != normalized) {
        await file.delete();
        throw const FormatException('Firmware SHA-256 verification failed');
      }
    }
  }

  Future<bool> isFirmwareDownloaded(int firmwareId) async {
    final path = _sharedPreferences.getString('$_keyPrefix$firmwareId');
    if (path == null) return false;
    final file = File(path);
    if (!await file.exists()) return false;
    final storedSize = _sharedPreferences.getInt('$_keySizePrefix$firmwareId');
    final storedSha256 =
        _sharedPreferences.getString('$_keySHA256Prefix$firmwareId');
    try {
      await _verifyFirmware(file, storedSize, storedSha256);
      return true;
    } on FormatException {
      await _clearDownloadedRecord(firmwareId);
      return false;
    }
  }

  Future<String?> getDownloadedFirmwarePath(int firmwareId) async {
    final path = _sharedPreferences.getString('$_keyPrefix$firmwareId');
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return path;
  }

  Future<void> deleteDownloadedFirmware(int firmwareId) async {
    final path = _sharedPreferences.getString('$_keyPrefix$firmwareId');
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      await _clearDownloadedRecord(firmwareId);
    }
  }

  Future<int> getDownloadedFirmwareSize(int firmwareId) async {
    final size = _sharedPreferences.getInt('$_keySizePrefix$firmwareId');
    if (size != null) return size;
    final path = _sharedPreferences.getString('$_keyPrefix$firmwareId');
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        return await file.length();
      }
    }
    return 0;
  }

  Future<Directory> _getFirmwareDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final firmwareDir = Directory('${docDir.path}/firmware');
    if (!await firmwareDir.exists()) {
      await firmwareDir.create(recursive: true);
    }
    return firmwareDir;
  }

  void dispose() {
    // 先置位再关闭：仍在运行的下载协程调 _emit 时会被守卫拦下，
    // 避免向已关闭的 StreamSink add 抛 StateError
    _disposed = true;
    _progressController.close();
  }
}
