import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_overview.dart';

void main() {
  test('parses backend module eligibility and channel support', () {
    final module = FirmwareModuleOverview.fromJson({
      'target': 'bms',
      'current_version': '1.0.0',
      'latest_firmware_id': 7,
      'latest_version': '1.1.0',
      'version_state': 'outdated',
      'update_available': true,
      'supported': true,
      'connected': true,
      'eligible': true,
      'supported_channels': ['remote'],
    });

    expect(module.isSupported, isTrue);
    expect(module.isConnected, isTrue);
    expect(module.isEligible, isTrue);
    expect(module.supportedChannels, ['remote']);
    expect(module.canRemoteUpgrade, isTrue);
  });

  test('BMS and unknown modules fail closed without explicit eligibility', () {
    FirmwareModuleOverview module(String target) =>
        FirmwareModuleOverview.fromJson({
          'target': target,
          'current_version': '1.0.0',
          'latest_firmware_id': 7,
          'latest_version': '1.1.0',
          'version_state': 'outdated',
          'update_available': true,
        });

    expect(module('bms').canRemoteUpgrade, isFalse);
    expect(module('vendor_x').canRemoteUpgrade, isFalse);
    expect(module('arm').canRemoteUpgrade, isTrue);
  });

  test('an explicit unsupported or disconnected module cannot upgrade', () {
    final unsupported = FirmwareModuleOverview.fromJson({
      'target': 'arm',
      'latest_firmware_id': 7,
      'version_state': 'outdated',
      'update_available': true,
      'supported': false,
      'connected': true,
      'eligible': true,
    });
    final disconnected = FirmwareModuleOverview.fromJson({
      'target': 'esp',
      'latest_firmware_id': 8,
      'version_state': 'outdated',
      'update_available': true,
      'supported': true,
      'connected': false,
      'eligible': true,
    });

    expect(unsupported.canRemoteUpgrade, isFalse);
    expect(disconnected.canRemoteUpgrade, isFalse);
  });

  test('firmware resources allow DSP and BMS only on advertised BLE channels',
      () {
    FirmwareResource resource(String target, {Object? channels}) =>
        FirmwareResource.fromJson({
          'id': 1,
          'target_chip': target,
          if (channels != null) 'supported_channels': channels,
        });

    expect(resource('esp').canLocalUpgrade, isTrue);
    expect(resource('arm').canLocalUpgrade, isTrue);
    expect(resource('dsp').canLocalUpgrade, isFalse);
    expect(resource('bms').canLocalUpgrade, isFalse);
    expect(resource('dsp', channels: ['remote', 'ble']).canLocalUpgrade,
        isTrue);
    expect(resource('bms', channels: ['remote', 'ble']).canLocalUpgrade,
        isTrue);
    expect(resource('bms', channels: ['remote', 'wifi_ap']).canLocalUpgrade,
        isFalse);
    expect(resource('arm', channels: ['remote']).canLocalUpgrade, isFalse);
    expect(resource('arm', channels: ['ble']).canLocalUpgrade, isTrue);
  });
}
