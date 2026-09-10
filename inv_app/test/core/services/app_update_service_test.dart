import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/app_update_service.dart';

void main() {
  late AppUpdateService service;

  setUp(() {
    service = AppUpdateService(Dio());
  });

  group('resolveCurrentVersionCode', () {
    test('读取安装包真实 versionCode 而非编译期常量', () async {
      PackageInfo.setMockInitialValues(
        appName: '辰烁光伏',
        packageName: 'com.csergy.app1',
        version: '1.0.0',
        buildNumber: '5',
        buildSignature: '',
      );

      expect(await service.resolveCurrentVersionCode(), 5);
    });

    test('buildNumber 为空时回退到编译期常量', () async {
      PackageInfo.setMockInitialValues(
        appName: '辰烁光伏',
        packageName: 'com.csergy.app1',
        version: '1.0.0',
        buildNumber: '',
        buildSignature: '',
      );

      expect(await service.resolveCurrentVersionCode(), AppConfig.versionCode);
    });

    test('buildNumber 非数字时回退到编译期常量', () async {
      PackageInfo.setMockInitialValues(
        appName: '辰烁光伏',
        packageName: 'com.csergy.app1',
        version: '1.0.0',
        buildNumber: 'abc',
        buildSignature: '',
      );

      expect(await service.resolveCurrentVersionCode(), AppConfig.versionCode);
    });

    test('buildNumber 带空白时按数字解析', () async {
      PackageInfo.setMockInitialValues(
        appName: '辰烁光伏',
        packageName: 'com.csergy.app1',
        version: '1.0.0',
        buildNumber: ' 7 ',
        buildSignature: '',
      );

      expect(await service.resolveCurrentVersionCode(), 7);
    });
  });

  group('chunkRanges', () {
    test('整除时均分且末片对齐 total-1', () {
      expect(AppUpdateService.chunkRanges(100, 4), [
        (0, 24),
        (25, 49),
        (50, 74),
        (75, 99),
      ]);
    });

    test('不整除时向上取整切分', () {
      expect(AppUpdateService.chunkRanges(10, 4), [
        (0, 2),
        (3, 5),
        (6, 8),
        (9, 9),
      ]);
    });

    test('文件小于分片数时只产生必要的分片', () {
      expect(AppUpdateService.chunkRanges(3, 4), [
        (0, 0),
        (1, 1),
        (2, 2),
      ]);
    });

    test('非正数输入返回空列表', () {
      expect(AppUpdateService.chunkRanges(0, 4), isEmpty);
      expect(AppUpdateService.chunkRanges(100, 0), isEmpty);
    });

    test('真实 APK 大小切片连续且覆盖完整', () {
      const total = 44251369;
      final ranges = AppUpdateService.chunkRanges(total, 4);

      expect(ranges.first.$1, 0);
      expect(ranges.last.$2, total - 1);
      for (var i = 1; i < ranges.length; i++) {
        expect(ranges[i].$1, ranges[i - 1].$2 + 1);
      }
    });
  });
}
