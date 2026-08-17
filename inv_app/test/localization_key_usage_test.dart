import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/l10n/app_en.dart' as en_catalog;
import 'package:inv_app/l10n/app_zh.dart' as zh_catalog;

/// l10n 动态 key 校验（CI 门禁）：
///
/// 项目使用手写 l10n（app_localizations.str('key') 动态查表），
/// 写错 key 只会静默显示 key 名，线上难以发现。
/// 本测试扫描 lib/ 下所有 `str('...')` 字面量 key，
/// 强制要求每个 key 在中英文文案表中都存在。
void main() {
  test('all dynamic str() keys exist in zh and en catalogs', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ directory must exist');

    // str('key' / str(\n 'key' 两种写法；key 为小写字母/数字/下划线
    final keyPattern = RegExp(r"""\.str\(\s*'([a-z][a-z0-9_]*)'""");

    final missing = <String, List<String>>{};
    for (final file in libDir.listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final content = file.readAsStringSync();
      for (final match in keyPattern.allMatches(content)) {
        final key = match.group(1)!;
        final inZh = zh_catalog.zh.containsKey(key);
        final inEn = en_catalog.en.containsKey(key);
        if (!inZh || !inEn) {
          missing.putIfAbsent(key, () => []).add(file.path);
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'str() 动态 key 缺失于 zh/en 文案表（写错 key 会静默显示 key 名）: '
          '${missing.entries.map((e) => '${e.key} <- ${e.value}').join('; ')}',
    );
  });
}
