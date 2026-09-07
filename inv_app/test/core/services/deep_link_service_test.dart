import 'package:flutter_test/flutter_test.dart';

import 'package:inv_app/core/services/deep_link_service.dart';

void main() {
  group('DeepLinkService.parse', () {
    // 16 位字母数字 SN（parse 只校验长度/字符集，无需通过 parseSN 语义校验）
    const validSn = 'H1CNA1238B12345X';

    test('csinv://bind?sn=&pin= 正确解析', () {
      final link = DeepLinkService.parse(
        Uri.parse('csinv://bind?sn=$validSn&pin=123456'),
      );
      expect(link, isNotNull);
      expect(link!.sn, validSn);
      expect(link.pin, '123456');
    });

    test('sn 小写输入统一转为大写', () {
      final link = DeepLinkService.parse(
        Uri.parse('csinv://bind?sn=${validSn.toLowerCase()}&pin=123456'),
      );
      expect(link, isNotNull);
      expect(link!.sn, validSn);
    });

    test('非 csinv scheme → null', () {
      expect(
        DeepLinkService.parse(
          Uri.parse('https://jiuxiaoyw.online/bind?sn=$validSn&pin=123456'),
        ),
        isNull,
      );
    });

    test('host 非 bind → null', () {
      expect(
        DeepLinkService.parse(
          Uri.parse('csinv://other?sn=$validSn&pin=123456'),
        ),
        isNull,
      );
    });

    test('sn 格式错误（长度不足 16 位）→ null', () {
      expect(
        DeepLinkService.parse(
          Uri.parse('csinv://bind?sn=H1CNA6K20001&pin=123456'),
        ),
        isNull,
      );
    });

    test('sn 格式错误（含非法字符）→ null', () {
      expect(
        DeepLinkService.parse(
          Uri.parse('csinv://bind?sn=${validSn.substring(0, 15)}-&pin=123456'),
        ),
        isNull,
      );
    });

    test('缺 pin → pin 为空字符串', () {
      final link = DeepLinkService.parse(
        Uri.parse('csinv://bind?sn=$validSn'),
      );
      expect(link, isNotNull);
      expect(link!.sn, validSn);
      expect(link.pin, '');
    });

    test('缺 sn → null', () {
      expect(
        DeepLinkService.parse(Uri.parse('csinv://bind?pin=123456')),
        isNull,
      );
    });
  });
}
