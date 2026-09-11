import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/presentation/models/firmware_module_presentation.dart';
import 'package:inv_app/l10n/app_localizations.dart';

void main() {
  test('maps internal firmware targets to functional module names', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));

    final cases = <String, String>{
      'esp': '通信采集',
      'ARM': '系统主控',
      'dsp': '功率控制',
      'bms': '电池管理',
      'vendor_x': '设备组件',
    };

    for (final entry in cases.entries) {
      final module = FirmwareModulePresentation.fromTarget(entry.key);
      expect(module.displayLabel(zh), entry.value);
      expect(
        module.displayLabel(zh).toUpperCase(),
        isNot(anyOf(contains('ESP'), contains('ARM'), contains('DSP'),
            contains('BMS'))),
      );
      expect(
        module.displayLabel(en).toUpperCase(),
        isNot(anyOf(contains('ESP'), contains('ARM'), contains('DSP'),
            contains('BMS'))),
      );
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
