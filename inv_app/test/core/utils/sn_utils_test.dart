import 'package:flutter_test/flutter_test.dart';

import 'package:inv_app/core/utils/sn_utils.dart';

void main() {
  group('parseQRCode smart-link URL format', () {
    // 与 core_logic_coverage_test.dart 一致的合法 15 位 base + 校验位
    const base15 = 'H1CNA1238B12345';
    final validSn = base15 + calculateCheckDigit(base15);

    test('URL 格式：sn + pin 正确解析', () {
      final result = parseQRCode(
        'https://jiuxiaoyw.online/bind?sn=$validSn&pin=123456',
      );
      expect(result, isNotNull);
      expect(result!.sn, validSn);
      expect(result.pin, '123456');
    });

    test('URL 格式：无 pin 变体解析成功（pin 为 null）', () {
      final result = parseQRCode('https://jiuxiaoyw.online/bind?sn=$validSn');
      expect(result, isNotNull);
      expect(result!.sn, validSn);
      expect(result.pin, isNull);
    });

    test('URL 格式：host 不做白名单限制（域名可变更）', () {
      final result = parseQRCode(
        'https://other-domain.org/bind?sn=$validSn&pin=000000',
      );
      expect(result, isNotNull);
      expect(result!.sn, validSn);
      expect(result.pin, '000000');
    });

    test('URL 格式：路径非 /bind → null', () {
      expect(
        parseQRCode(
          'https://jiuxiaoyw.online/other?sn=$validSn&pin=123456',
        ),
        isNull,
      );
    });

    test('URL 格式：sn 长度非法 → null', () {
      // 12 位示例 SN（铭牌旧文案）不满足 16 位校验
      expect(
        parseQRCode(
          'https://jiuxiaoyw.online/bind?sn=H1CNA6K20001&pin=123456',
        ),
        isNull,
      );
    });

    test('旧格式回归：SN:PIN / 纯 SN 不被破坏', () {
      final r1 = parseQRCode('SN:$validSn PIN:1234');
      expect(r1, isNotNull);
      expect(r1!.sn, validSn);
      expect(r1.pin, '1234');

      final r2 = parseQRCode(validSn.toLowerCase());
      expect(r2, isNotNull);
      expect(r2!.sn, validSn);
      expect(r2.pin, isNull);

      expect(parseQRCode(''), isNull);
      expect(parseQRCode('not-a-qr-code'), isNull);
      expect(parseQRCode('SN:12345'), isNull); // wrong length
    });
  });
}
