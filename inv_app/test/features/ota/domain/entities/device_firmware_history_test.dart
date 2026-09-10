import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';

void main() {
  test('normalizes an omitted changelog and parses pagination', () {
    final item = DeviceFirmwareHistory.fromJson({
      'id': 9,
      'device_sn': 'INV-001',
      'target_chip': 'arm',
      'old_version': '1.0.0',
      'firmware_version': '1.1.0',
      'status': 'success',
      'updated_at': '2026-09-10T08:00:00Z',
    });

    expect(item.changelog, isEmpty);
    expect(item.updatedAt, DateTime.utc(2026, 9, 10, 8));
    expect(item.target, 'arm');
  });
}
