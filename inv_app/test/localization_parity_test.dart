import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/l10n/app_en.dart' as en_catalog;
import 'package:inv_app/l10n/app_zh.dart' as zh_catalog;

void main() {
  test('Chinese and English locale catalogs have identical keys', () {
    expect(en_catalog.en.keys.toSet(), zh_catalog.zh.keys.toSet());
  });

  test('locale keys and values are valid', () {
    for (final catalog in [en_catalog.en, zh_catalog.zh]) {
      for (final entry in catalog.entries) {
        expect(entry.key, entry.key.trim());
        expect(entry.key.contains(RegExp(r'\s')), isFalse, reason: entry.key);
        if (entry.key != 'unit_devices') {
          expect(entry.value, isNotEmpty, reason: entry.key);
        }
      }
    }
  });
}
