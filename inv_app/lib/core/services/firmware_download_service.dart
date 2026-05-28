import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirmwareDownloadService {
  final Dio _dio;
  final SharedPreferences _sharedPreferences;

  static const String _keyPrefix = 'firmware_path_';
  static const String _keySizePrefix = 'firmware_size_';

  final StreamController<double> _progressController =
      StreamController<double>.broadcast();

  Stream<double> get downloadProgressStream => _progressController.stream;

  FirmwareDownloadService(this._dio, this._sharedPreferences);

  Future<String> downloadFirmware({
    required String url,
    required String fileName,
    required int firmwareId,
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await _getFirmwareDir();
    final filePath = '${dir.path}/$fileName';
    final file = File(filePath);

    int downloadedBytes = 0;
    if (await file.exists()) {
      downloadedBytes = await file.length();
    }

    final options = Options();
    if (downloadedBytes > 0) {
      options.headers = {'Range': 'bytes=$downloadedBytes-'};
    }

    _progressController.add(0.0);

    try {
      await _dio.download(
        url,
        filePath,
        options: Options(
          headers: downloadedBytes > 0 ? {'Range': 'bytes=$downloadedBytes-'} : null,
        ),
        onReceiveProgress: (received, total) {
          final overallTotal = total > 0 ? total : total + downloadedBytes;
          final progress = overallTotal > 0
              ? (downloadedBytes + received) / overallTotal
              : 0.0;
          _progressController.add(progress.clamp(0.0, 1.0));
          onProgress?.call(downloadedBytes + received, overallTotal);
        },
        deleteOnError: false,
      );

      final savedFile = File(filePath);
      final fileSize = await savedFile.length();

      await _sharedPreferences.setString('$_keyPrefix$firmwareId', filePath);
      await _sharedPreferences.setInt('$_keySizePrefix$firmwareId', fileSize);

      _progressController.add(1.0);

      return filePath;
    } catch (e) {
      _progressController.add(-1.0);
      rethrow;
    }
  }

  Future<bool> isFirmwareDownloaded(int firmwareId) async {
    final path = _sharedPreferences.getString('$_keyPrefix$firmwareId');
    if (path == null) return false;
    final file = File(path);
    return await file.exists();
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
