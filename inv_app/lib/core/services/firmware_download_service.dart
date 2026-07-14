import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirmwareDownloadService {
  final Dio _dio;
  final SharedPreferences _sharedPreferences;

  static const String _keyPrefix = 'firmware_path_';
  static const String _keySizePrefix = 'firmware_size_';
  static const String _keySHA256Prefix = 'firmware_sha256_';

  final StreamController<double> _progressController =
      StreamController<double>.broadcast();

  Stream<double> get downloadProgressStream => _progressController.stream;

  FirmwareDownloadService(this._dio, this._sharedPreferences);

  Future<String> downloadFirmware({
    required String url,
    required String fileName,
    required int firmwareId,
    int? expectedSize,
    String? expectedSha256,
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await _getFirmwareDir();
    final filePath = '${dir.path}/$fileName';
    final file = File(filePath);

    int downloadedBytes = 0;
    if (await file.exists()) {
      downloadedBytes = await file.length();
    }

    _progressController.add(0.0);

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
              _progressController.add(progress.clamp(0.0, 1.0));
              onProgress?.call(downloadedBytes + received, overallTotal);
            },
            deleteOnError: false,
          );
          // A server that ignores Range returns 200. Appending that response would
          // corrupt the file, so restart once from byte zero.
          if (response.statusCode != HttpStatus.partialContent) {
            await file.delete();
            await _dio.download(url, filePath,
                onReceiveProgress: onProgress, deleteOnError: false);
          }
        } on DioException catch (e) {
          // 416 only means the range is unsatisfiable; integrity still must pass.
          if (e.response?.statusCode == 416) {
            final savedFile = File(filePath);
            await _verifyFirmware(savedFile, expectedSize, expectedSha256);
            final fileSize = await savedFile.length();
            await _sharedPreferences.setString(
                '$_keyPrefix$firmwareId', filePath);
            await _sharedPreferences.setInt(
                '$_keySizePrefix$firmwareId', fileSize);
            if (expectedSha256 != null) {
              await _sharedPreferences.setString(
                  '$_keySHA256Prefix$firmwareId', expectedSha256.toLowerCase());
            }
            _progressController.add(1.0);
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
            _progressController.add(progress.clamp(0.0, 1.0));
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
            '$_keySHA256Prefix$firmwareId', expectedSha256.toLowerCase());
      }

      _progressController.add(1.0);

      return filePath;
    } catch (e) {
      _progressController.add(-1.0);
      rethrow;
    }
  }

  Future<void> _verifyFirmware(
      File file, int? expectedSize, String? expectedSha256) async {
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
      await _sharedPreferences.remove('$_keyPrefix$firmwareId');
      await _sharedPreferences.remove('$_keySizePrefix$firmwareId');
      await _sharedPreferences.remove('$_keySHA256Prefix$firmwareId');
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
      await _sharedPreferences.remove('$_keyPrefix$firmwareId');
      await _sharedPreferences.remove('$_keySizePrefix$firmwareId');
      await _sharedPreferences.remove('$_keySHA256Prefix$firmwareId');
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
    _progressController.close();
  }
}
