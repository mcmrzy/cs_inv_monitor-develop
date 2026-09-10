import 'package:flutter/material.dart';
import 'package:inv_app/l10n/app_localizations.dart';

enum FirmwareModuleKind {
  communication,
  systemControl,
  powerControl,
  batteryManagement,
  generic,
}

final class FirmwareModulePresentation {
  const FirmwareModulePresentation(
      {required this.kind, required this.rawTarget});

  final FirmwareModuleKind kind;
  final String rawTarget;

  String get labelKey => switch (kind) {
        FirmwareModuleKind.communication => 'firmware_module_communication',
        FirmwareModuleKind.systemControl => 'firmware_module_system_control',
        FirmwareModuleKind.powerControl => 'firmware_module_power_control',
        FirmwareModuleKind.batteryManagement =>
          'firmware_module_battery_management',
        FirmwareModuleKind.generic => 'firmware_module_generic',
      };

  String get descriptionKey => switch (kind) {
        FirmwareModuleKind.communication =>
          'firmware_module_communication_description',
        FirmwareModuleKind.systemControl =>
          'firmware_module_system_control_description',
        FirmwareModuleKind.powerControl =>
          'firmware_module_power_control_description',
        FirmwareModuleKind.batteryManagement =>
          'firmware_module_battery_management_description',
        FirmwareModuleKind.generic => 'firmware_module_generic_description',
      };

  IconData get icon => switch (kind) {
        FirmwareModuleKind.communication => Icons.sensors_rounded,
        FirmwareModuleKind.systemControl => Icons.memory_rounded,
        FirmwareModuleKind.powerControl => Icons.bolt_rounded,
        FirmwareModuleKind.batteryManagement => Icons.battery_5_bar_rounded,
        FirmwareModuleKind.generic => Icons.extension_rounded,
      };

  String displayLabel(AppLocalizations l10n) => l10n.str(labelKey);

  static FirmwareModulePresentation fromTarget(String? value) {
    final raw = value?.trim() ?? '';
    final kind = switch (raw.toLowerCase()) {
      'esp' => FirmwareModuleKind.communication,
      'arm' => FirmwareModuleKind.systemControl,
      'dsp' => FirmwareModuleKind.powerControl,
      'bms' => FirmwareModuleKind.batteryManagement,
      _ => FirmwareModuleKind.generic,
    };
    return FirmwareModulePresentation(kind: kind, rawTarget: raw);
  }

  static FirmwareModulePresentation fromFirmwareField(String field) {
    return fromTarget(field.replaceFirst(RegExp(r'^firmware_'), ''));
  }
}
