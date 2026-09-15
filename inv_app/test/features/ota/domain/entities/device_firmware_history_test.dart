import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';

void main() {
  test('normalizes an omitted changelog and parses pagination', () {
    final item = DeviceFirmwareHistory.fromJson({
      'id': 9,
      'device_sn': 'INV-001',
      'firmware_id': 42,
      'target_chip': 'arm',
      'old_version': '1.0.0',
      'firmware_version': '1.1.0',
      'status': 'success',
      'progress': 100,
      'created_at': '2026-09-10T08:00:00Z',
      'completed_at': '2026-09-10T08:05:00Z',
    });

    expect(item.changelog, isEmpty);
    expect(item.firmwareId, 42);
    expect(item.target, 'arm');
    expect(item.firmwareVersion, '1.1.0');
    expect(item.newVersion, '1.1.0');
    expect(item.canRollback, isTrue);
    expect(item.createdAt, DateTime.utc(2026, 9, 10, 8));
  });

  test('history without firmware_id cannot rollback', () {
    final item = DeviceFirmwareHistory.fromJson({
      'id': 1,
      'device_sn': 'INV-001',
      'firmware_id': 0,
      'target_chip': 'esp',
      'old_version': '1.0.0',
      'firmware_version': '1.1.0',
      'status': 'success',
    });
    expect(item.canRollback, isFalse);
  });

  test('failed history cannot rollback even with firmware_id', () {
    final item = DeviceFirmwareHistory.fromJson({
      'id': 2,
      'device_sn': 'INV-001',
      'firmware_id': 10,
      'target_chip': 'esp',
      'old_version': '1.0.0',
      'firmware_version': '1.1.0',
      'status': 'failed',
    });
    expect(item.canRollback, isFalse);
  });
}
