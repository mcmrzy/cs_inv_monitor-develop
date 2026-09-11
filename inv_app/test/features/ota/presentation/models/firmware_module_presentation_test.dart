import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/presentation/models/firmware_module_presentation.dart';
import 'package:inv_app/l10n/app_localizations.dart';

void main() {
  test('maps internal firmware targets to functional module names', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));

    // 展示名统一为「中文模块名（芯片）」，见 e14f20575
    final cases = <String, String>{
      'esp': '通信采集（ESP）',
      'ARM': '系统中控（ARM）',
      'dsp': '计算控制（DSP）',
      'bms': '电池管理（BMS）',
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
      'esp': 'Communication (ESP)',
      'ARM': 'System Control (ARM)',
      'dsp': 'Computation (DSP)',
      'bms': 'Battery Management (BMS)',
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
}
