import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_overview.dart';

void main() {
  test('server eligibility permits published targets before version reporting', () {
    for (final target in ['esp', 'arm', 'dsp', 'bms']) {
      final module = FirmwareModuleOverview.fromJson({
        'target': target,
        'current_version': '',
        'latest_firmware_id': 7,
        'latest_version': '1.1.0',
        'version_state': 'unreported',
        'update_available': true,
        'supported': true,
        'connected': false,
        'eligible': true,
        'supported_channels': ['remote'],
      });
      expect(module.isUnreported, isTrue);
      expect(module.canRemoteUpgrade, isTrue, reason: target);
    }
    expect(FirmwareModuleOverview.fromJson({
      'target': 'esp', 'latest_firmware_id': 7,
      'version_state': 'unreported', 'update_available': true,
    },).canRemoteUpgrade, isFalse,);
    expect(FirmwareModuleOverview.fromJson({
      'target': 'esp', 'current_version': '1.0.0', 'latest_firmware_id': 7,
      'version_state': 'outdated', 'update_available': true,
      'supported': true, 'connected': false, 'eligible': true,
    },).canRemoteUpgrade, isTrue,);
  });

  test('ordinary remote resources do not require a hardware range', () {
    final resource = FirmwareResource.fromJson({
      'id': 12,
      'model': 'L10',
      'version': '1.2.0',
      'target_chip': 'esp',
      'supported_channels': ['remote', 'ble'],
    });
    expect(resource.canRemoteUpgrade, isTrue);
    // The separate trusted local flow retains its preflight requirements.
    expect(resource.canLocalUpgrade, isFalse);
    expect(FirmwareResource.fromJson({
      'target_chip': 'esp', 'supported_channels': ['ble'],
    },).canRemoteUpgrade, isFalse,);
  });

  test('parses raw device hardware and each module compatibility reason', () {
    final overview = DeviceFirmwareOverview.fromJson({
      'device_sn': 'SN1',
      'device_model': 'L10',
      'is_online': true,
      'hardware_version': ' hw-2 ',
      'hardware_state': 'known',
      'modules': [
        {
          'target': 'esp',
          'latest_firmware_id': 12,
          'update_available': true,
          'version_state': 'outdated',
          'compatibility_reason': 'no_compatible_firmware',
        }
      ],
    });
    expect(overview.hardwareVersion, ' hw-2 ');
    expect(overview.hardwareState, 'known');
    expect(
        overview.modules.single.compatibilityReason, 'no_compatible_firmware',);
    expect(overview.modules.single.canRemoteUpgrade, isFalse);
    expect(DeviceFirmwareOverview.fromJson({}).hardwareState, 'unknown');
    final resource = FirmwareResource.fromJson({
      'hardware_versions': ['HW-1', 'HW-2'],
    });
    expect(resource.hardwareVersions, ['HW-1', 'HW-2']);
    expect(FirmwareResource.fromJson({}).hardwareVersions, isEmpty);
    expect(FirmwareResource.fromJson({}).canLocalUpgrade, isFalse);
    expect(FirmwareResource.fromJson({}).canRemoteUpgrade, isFalse);
  });
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

  test('unsupported, ineligible and legacy disconnected modules cannot upgrade', () {
    final unsupported = FirmwareModuleOverview.fromJson({
      'target': 'arm',
      'latest_firmware_id': 7,
      'version_state': 'outdated',
      'update_available': true,
      'supported': false,
      'connected': true,
      'eligible': true,
    });
    final ineligible = FirmwareModuleOverview.fromJson({
      'target': 'esp',
      'latest_firmware_id': 8,
      'version_state': 'unreported',
      'update_available': true,
      'supported': true,
      'connected': false,
      'eligible': false,
    });
    final disconnected = FirmwareModuleOverview.fromJson({
      'target': 'esp',
      'latest_firmware_id': 8,
      'version_state': 'outdated',
      'update_available': true,
      'supported': true,
      'connected': false,
    });

    expect(unsupported.canRemoteUpgrade, isFalse);
    expect(disconnected.canRemoteUpgrade, isFalse);
    expect(ineligible.canRemoteUpgrade, isFalse);
  });

  test('firmware resources allow DSP and BMS only on advertised BLE channels',
      () {
    FirmwareResource resource(String target, {Object? channels}) =>
        FirmwareResource.fromJson({
          'id': 1,
          'hardware_versions': ['HW-1'],
          'target_chip': target,
          if (channels != null) 'supported_channels': channels,
        });

    expect(resource('esp').canLocalUpgrade, isTrue);
    expect(resource('arm').canLocalUpgrade, isTrue);
    expect(resource('dsp').canLocalUpgrade, isFalse);
    expect(resource('bms').canLocalUpgrade, isFalse);
    expect(
        resource('dsp', channels: ['remote', 'ble']).canLocalUpgrade, isTrue,);
    expect(
        resource('bms', channels: ['remote', 'ble']).canLocalUpgrade, isTrue,);
    expect(resource('bms', channels: ['remote', 'wifi_ap']).canLocalUpgrade,
        isFalse,);
    expect(resource('arm', channels: ['remote']).canLocalUpgrade, isFalse);
    expect(resource('arm', channels: ['ble']).canLocalUpgrade, isTrue);
  });
}
