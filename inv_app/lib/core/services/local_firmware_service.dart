import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/ota_error_types.dart';
import 'package:inv_app/core/services/local_communication_service.dart';

class LocalFirmwareService {
  final LocalCommunicationService _localComm;

  LocalFirmwareService(this._localComm);

  /// 上传固件文件到设备
  /// target: 'esp' 或 'arm'，决定上传方式
  Future<void> uploadFirmware({
    required String deviceIP,
    required String filePath,
    String target = 'esp',
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw LocalFirmwareException('Firmware file not found: $filePath');
    }

    try {
      await _localComm.connect(deviceIP);
      await _localComm.uploadFirmware(filePath, target: target, onProgress: onProgress);
    } catch (e) {
      throw LocalFirmwareException('Upload firmware failed: $e');
    }
  }

  Future<String> _calculateMD5(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final hash = _md5(bytes);
    return hash;
  }

  Future<String> calculateFileMD5(String filePath) async {
    return _calculateMD5(filePath);
  }

  Future<Map<String, dynamic>> getLocalOTAProgress({required String deviceIP}) async {
    try {
      await _localComm.connect(deviceIP);
      return await _localComm.getOTAProgress();
    } on DeviceConnectionException {
      rethrow; // 保留原始异常类型，让上层处理连接异常
    } catch (e) {
      throw LocalFirmwareException('Failed to get upgrade progress: $e');
    }
  }

  Future<bool> testDeviceConnection(String deviceIP) async {
    await _localComm.connect(deviceIP);
    return await _localComm.testConnection();
  }

  /// 获取设备信息（版本号等）
  Future<Map<String, dynamic>> getDeviceInfo({required String deviceIP}) async {
    await _localComm.connect(deviceIP);
    return await _localComm.getDeviceInfo();
  }

  String _md5(Uint8List data) {
    final digest = _MD5Digest();
    digest.update(data, 0, data.length);
    final out = Uint8List(16);
    digest.doFinal(out, 0);
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _MD5Digest {
  int _x0 = 0, _x1 = 0, _x2 = 0, _x3 = 0;
  int _h0 = 0x67452301;
  int _h1 = 0xefcdab89;
  int _h2 = 0x98badcfe;
  int _h3 = 0x10325476;

  int _bytesProcessed = 0;

  void update(Uint8List data, int offset, int length) {
    _bytesProcessed += length;

    var pos = offset;
    var remaining = length;

    while (remaining >= 64) {
      _processBlock(Uint8List.sublistView(data, pos, pos + 64));
      pos += 64;
      remaining -= 64;
    }

    if (remaining > 0) {
      final lastBlock = Uint8List(64);
      lastBlock.setRange(0, remaining, data, pos);
      _processBlock(lastBlock);
    }

    final bitLength = _bytesProcessed * 8;
    _processBlock(_createPaddingWithLength(bitLength));
  }

  Uint8List _createPaddingWithLength(int bitLength) {
    final result = Uint8List(64);
    result[0] = 0x80;
    for (var i = 0; i < 8; i++) {
      result[56 + i] = (bitLength >> (i * 8)) & 0xff;
    }
    return result;
  }

  void _processBlock(Uint8List block) {
    _decodeBlock(block);

    var a = _h0;
    var b = _h1;
    var c = _h2;
    var d = _h3;

    a = _ff(a, b, c, d, _x0, 7, 0xd76aa478);
    d = _ff(d, a, b, c, _x1, 12, 0xe8c7b756);
    c = _ff(c, d, a, b, _x2, 17, 0x242070db);
    b = _ff(b, c, d, a, _x3, 22, 0xc1bdceee);
    a = _ff(a, b, c, d, 0, 7, 0xf57c0faf);
    d = _ff(d, a, b, c, 0, 12, 0x4787c62a);
    c = _ff(c, d, a, b, 0, 17, 0xa8304613);
    b = _ff(b, c, d, a, 0, 22, 0xfd469501);
    a = _ff(a, b, c, d, 0, 7, 0x698098d8);
    d = _ff(d, a, b, c, 0, 12, 0x8b44f7af);
    c = _ff(c, d, a, b, 0, 17, 0xffff5bb1);
    b = _ff(b, c, d, a, 0, 22, 0x895cd7be);
    a = _ff(a, b, c, d, 0, 7, 0x6b901122);
    d = _ff(d, a, b, c, 0, 12, 0xfd987193);
    c = _ff(c, d, a, b, 0, 17, 0xa679438e);
    b = _ff(b, c, d, a, 0, 22, 0x49b40821);

    a = _gg(a, b, c, d, _x1, 5, 0xf61e2562);
    d = _gg(d, a, b, c, 0, 9, 0xc040b340);
    c = _gg(c, d, a, b, 0, 14, 0x265e5a51);
    b = _gg(b, c, d, a, _x0, 20, 0xe9b6c7aa);
    a = _gg(a, b, c, d, 0, 5, 0xd62f105d);
    d = _gg(d, a, b, c, 0, 9, 0x02441453);
    c = _gg(c, d, a, b, 0, 14, 0xd8a1e681);
    b = _gg(b, c, d, a, _x3, 20, 0xe7d3fbc8);
    a = _gg(a, b, c, d, 0, 5, 0x21e1cde6);
    d = _gg(d, a, b, c, _x2, 9, 0xc33707d6);
    c = _gg(c, d, a, b, 0, 14, 0xf4d50d87);
    b = _gg(b, c, d, a, 0, 20, 0x455a14ed);
    a = _gg(a, b, c, d, 0, 5, 0xa9e3e905);
    d = _gg(d, a, b, c, 0, 9, 0xfcefa3f8);
    c = _gg(c, d, a, b, 0, 14, 0x676f02d9);
    b = _gg(b, c, d, a, 0, 20, 0x8d2a4c8a);

    a = _hh(a, b, c, d, 0, 4, 0xfffa3942);
    d = _hh(d, a, b, c, 0, 11, 0x8771f681);
    c = _hh(c, d, a, b, 0, 16, 0x6d9d6122);
    b = _hh(b, c, d, a, _x2, 23, 0xfde5380c);
    a = _hh(a, b, c, d, 0, 4, 0xa4beea44);
    d = _hh(d, a, b, c, _x3, 11, 0x4bdecfa9);
    c = _hh(c, d, a, b, 0, 16, 0xf6bb4b60);
    b = _hh(b, c, d, a, 0, 23, 0xbebfbc70);
    a = _hh(a, b, c, d, _x1, 4, 0x289b7ec6);
    d = _hh(d, a, b, c, 0, 11, 0xeaa127fa);
    c = _hh(c, d, a, b, _x0, 16, 0xd4ef3085);
    b = _hh(b, c, d, a, 0, 23, 0x04881d05);
    a = _hh(a, b, c, d, 0, 4, 0xd9d4d039);
    d = _hh(d, a, b, c, 0, 11, 0xe6db99e5);
    c = _hh(c, d, a, b, 0, 16, 0x1fa27cf8);
    b = _hh(b, c, d, a, 0, 23, 0xc4ac5665);

    a = _ii(a, b, c, d, _x0, 6, 0xf4292244);
    d = _ii(d, a, b, c, 0, 10, 0x432aff97);
    c = _ii(c, d, a, b, _x2, 15, 0xab9423a7);
    b = _ii(b, c, d, a, 0, 21, 0xfc93a039);
    a = _ii(a, b, c, d, 0, 6, 0x655b59c3);
    d = _ii(d, a, b, c, 0, 10, 0x8f0ccc92);
    c = _ii(c, d, a, b, 0, 15, 0xffeff47d);
    b = _ii(b, c, d, a, _x1, 21, 0x85845dd1);
    a = _ii(a, b, c, d, 0, 6, 0x6fa87e4f);
    d = _ii(d, a, b, c, 0, 10, 0xfe2ce6e0);
    c = _ii(c, d, a, b, _x3, 15, 0xa3014314);
    b = _ii(b, c, d, a, 0, 21, 0x4e0811a1);
    a = _ii(a, b, c, d, 0, 6, 0xf7537e82);
    d = _ii(d, a, b, c, _x2, 10, 0xbd3af235);
    c = _ii(c, d, a, b, 0, 15, 0x2ad7d2bb);
    b = _ii(b, c, d, a, 0, 21, 0xeb86d391);

    _h0 = _mask(_h0 + a);
    _h1 = _mask(_h1 + b);
    _h2 = _mask(_h2 + c);
    _h3 = _mask(_h3 + d);
  }

  void doFinal(Uint8List out, int offset) {
    _pack32(_h0, out, offset);
    _pack32(_h1, out, offset + 4);
    _pack32(_h2, out, offset + 8);
    _pack32(_h3, out, offset + 12);
  }

  void _decodeBlock(Uint8List block) {
    _x0 = _unpack32(block, 0);
    _x1 = _unpack32(block, 4);
    _x2 = _unpack32(block, 8);
    _x3 = _unpack32(block, 12);
  }

  static int _unpack32(Uint8List block, int offset) {
    return (block[offset] & 0xff) |
        ((block[offset + 1] & 0xff) << 8) |
        ((block[offset + 2] & 0xff) << 16) |
        ((block[offset + 3] & 0xff) << 24);
  }

  static void _pack32(int value, Uint8List out, int offset) {
    out[offset] = value & 0xff;
    out[offset + 1] = (value >> 8) & 0xff;
    out[offset + 2] = (value >> 16) & 0xff;
    out[offset + 3] = (value >> 24) & 0xff;
  }

  static int _mask(int x) => x & 0xffffffff;

  static int _rotl(int x, int n) => _mask((_mask(x) << n) | (_mask(x) >> (32 - n)));

  static int _ff(int a, int b, int c, int d, int x, int s, int ac) {
    return _rotl(_mask(a + ((b & c) | (~b & d)) + x + ac), s) + b;
  }

  static int _gg(int a, int b, int c, int d, int x, int s, int ac) {
    return _rotl(_mask(a + ((b & d) | (c & ~d)) + x + ac), s) + b;
  }

  static int _hh(int a, int b, int c, int d, int x, int s, int ac) {
    return _rotl(_mask(a + (b ^ c ^ d) + x + ac), s) + b;
  }

  static int _ii(int a, int b, int c, int d, int x, int s, int ac) {
    return _rotl(_mask(a + (c ^ (b | ~d)) + x + ac), s) + b;
  }
}

class LocalFirmwareException implements Exception {
  final String message;
  LocalFirmwareException(this.message);

  @override
  String toString() => message;
}
