import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/utils/qr_scan_guard.dart';

void main() {
  test('rejects duplicate payloads until the bind route is finished', () {
    final guard = QrScanGuard();
    const payload = 'csinv://bind?sn=TESTSN1234567890&pin=123456';

    expect(guard.tryAcquire(payload), isTrue);
    expect(guard.tryAcquire(payload), isFalse);

    guard.release(resetPayload: true);

    expect(guard.tryAcquire(payload), isTrue);
  });
}
