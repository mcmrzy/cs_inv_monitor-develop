import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/presentation/models/firmware_module_presentation.dart';
import 'package:inv_app/l10n/app_localizations.dart';

void main() {
  test('maps internal firmware targets to functional module names', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));

    // 展示名固定为功能名，不带芯片后缀
    final cases = <String, String>{
      'esp': '通信采集',
      'ARM': '主控',
      'dsp': '数字信号',
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
      'ARM': 'Main Control',
      'dsp': 'Digital Signal',
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
}
