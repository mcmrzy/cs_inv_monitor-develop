import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/utils/sn_utils.dart';
import 'package:inv_app/core/services/deep_link_service.dart';

void main() {
  const sn = 'H1ZZX0013900001P';
  test('camera and deep link agree; leading zeros preserved', () {
    for (final prefix in ['csinv://bind', 'https://example.com/bind']) {
      final payload = '$prefix?sn=$sn&pin=000012';
      expect(parseQRCode(payload)?.pin, '000012');
      expect(DeepLinkService.parse(Uri.parse(payload))?.sn, sn);
    }
  });
  test('invalid or ambiguous credentials rejected by both entry points', () {
    for (final suffix in [
      'pin=12345',
      'pin=12A456',
      'pin=',
      'pin=123456&pin=654321',
      'pin=123456&sn=$sn',
    ]) {
      final payload = 'csinv://bind?sn=$sn&$suffix';
      expect(parseQRCode(payload), isNull);
      expect(DeepLinkService.parse(Uri.parse(payload)), isNull);
    }
    expect(parseQRCode('ftp://example.com/bind?sn=$sn&pin=123456'), isNull);
  });
  test('legacy labels and single SN work without allowing malformed PIN', () {
    expect(parseQRCode('SN:$sn PIN:000000')?.pin, '000000');
    expect(parseQRCode(sn)?.pin, isNull);
    expect(parseQRCode('SN:$sn PIN:1234'), isNull);
  });
}
