// 用 vector_graphics_compiler 的解析器严格校验导航 SVG（在 inv_app 目录下运行）
import 'dart:io';

import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

void main() {
  final dir = Directory('assets/icons/csergy');
  var ok = 0;
  var fail = 0;
  for (final f in dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.svg') && !f.path.contains('nav_ota'))) {
    try {
      final xml = f.readAsStringSync();
      parse(xml, key: f.path, warningsAsErrors: true);
      print('OK   ${f.path.split(Platform.pathSeparator).last}');
      ok++;
    } catch (e) {
      print('FAIL ${f.path.split(Platform.pathSeparator).last}: $e');
      fail++;
    }
  }
  print('=== $ok 通过, $fail 失败 ===');
}
