import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/presentation/models/firmware_module_presentation.dart';
import 'package:inv_app/l10n/app_localizations.dart';

void main() {
  test('maps internal firmware targets to functional module names', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));

    // 用户端中英文均不展示芯片内部后缀
    final cases = <String, String>{
      'esp': '通信采集',
      'ARM': '系统中控',
      'dsp': '计算控制',
      'bms': '电池管理',
      'vendor_x': '设备组件',
    };

    for (final entry in cases.entries) {
      final module = FirmwareModulePresentation.fromTarget(entry.key);
      expect(module.displayLabel(zh), entry.value);
    }
  });

  test('localizes module labels in English as well', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));

    final cases = <String, String>{
      'esp': 'Communication',
      'ARM': 'System Control',
      'dsp': 'Power Control',
      'bms': 'Battery Management',
      'vendor_x': 'Device Component',
    };

    for (final entry in cases.entries) {
      final module = FirmwareModulePresentation.fromTarget(entry.key);
      expect(module.displayLabel(en), entry.value);
    }
  });

  test('keeps raw target for requests but never uses it as fallback label', () {
    final module = FirmwareModulePresentation.fromTarget('vendor_x');

    expect(module.kind, FirmwareModuleKind.generic);
    expect(module.rawTarget, 'vendor_x');
    expect(module.labelKey, 'firmware_module_generic');
  });

  test('maps firmware fields to the same presentation units', () {
    expect(
      FirmwareModulePresentation.fromFirmwareField('firmware_esp').kind,
      FirmwareModuleKind.communication,
    );
    expect(
      FirmwareModulePresentation.fromFirmwareField('firmware_arm').kind,
      FirmwareModuleKind.systemControl,
    );
    expect(
      FirmwareModulePresentation.fromFirmwareField('firmware_dsp').kind,
      FirmwareModuleKind.powerControl,
    );
    expect(
      FirmwareModulePresentation.fromFirmwareField('firmware_bms').kind,
      FirmwareModuleKind.batteryManagement,
    );
  });

  group('sanitizeLegacyLabel', () {
    test('strips trailing parenthesized chip suffixes', () {
      expect(
        FirmwareModulePresentation.sanitizeLegacyLabel('通信采集（ESP）'),
        '通信采集',
      );
      expect(
        FirmwareModulePresentation.sanitizeLegacyLabel('System Control (ARM)'),
        'System Control',
      );
      expect(
        FirmwareModulePresentation.sanitizeLegacyLabel('Computation (dsp)'),
        'Computation',
      );
      expect(
        FirmwareModulePresentation.sanitizeLegacyLabel('Battery (BMS)'),
        'Battery',
      );
    });

    test('strips trailing bare chip words', () {
      expect(
        FirmwareModulePresentation.sanitizeLegacyLabel('Communication ESP'),
        'Communication',
      );
      expect(
        FirmwareModulePresentation.sanitizeLegacyLabel('Main Control eSp'),
        'Main Control',
      );
      expect(
        FirmwareModulePresentation.sanitizeLegacyLabel('数字信号 ARM'),
        '数字信号',
      );
    });

    test('leaves labels without chip suffixes unchanged', () {
      expect(
        FirmwareModulePresentation.sanitizeLegacyLabel('通信采集'),
        '通信采集',
      );
      expect(
        FirmwareModulePresentation.sanitizeLegacyLabel('Main Control'),
        'Main Control',
      );
    });
  });

  test('customer copy replaces internal chip abbreviations everywhere', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));

    expect(
      FirmwareModulePresentation.sanitizeCustomerCopy(
        'ARM 升级完成，ESP 等待重启，vendor_x 保持不变',
        zh,
      ),
      '系统中控 升级完成，通信采集 等待重启，vendor_x 保持不变',
    );
  });

  test('only communication and system-control modules support local OTA', () {
    expect(FirmwareModulePresentation.fromTarget('esp').supportsLocalUpgrade,
        isTrue);
    expect(FirmwareModulePresentation.fromTarget('arm').supportsLocalUpgrade,
        isTrue);
    expect(FirmwareModulePresentation.fromTarget('dsp').supportsLocalUpgrade,
        isFalse);
    expect(FirmwareModulePresentation.fromTarget('bms').supportsLocalUpgrade,
        isFalse);
    expect(
        FirmwareModulePresentation.fromTarget('vendor_x').supportsLocalUpgrade,
        isFalse);
  });

  test('device firmware routes always target the independent flow', () {
    expect(
      FirmwareModulePresentation.deviceRoute('INV / 001'),
      '/ota/device/INV%20%2F%20001',
    );
  });
}
