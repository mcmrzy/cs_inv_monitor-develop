import 'dart:io';

import 'package:flutter/services.dart';

/// Golden 测试字体基建。
///
/// flutter test 默认用 Ahem 字体渲染所有文本（每个字形都是实心色块），
/// 直接生成 golden 毫无回归检测价值。本 helper 在 golden 测试前加载真实字体：
///
/// - [kGoldenFontFamily]（'GoldenFont'）：项目自带
///   `assets/fonts/NotoSansSC-VF.ttf`（思源黑体可变字体，中英文字形全覆盖）。
///   golden 页面的 ThemeData 需要设置 `fontFamily: kGoldenFontFamily`。
/// - 'MaterialIcons'：Flutter SDK 缓存中的图标字体，让 Icons.* 渲染为真实
///   图形而非方块；取自 `FLUTTER_ROOT` 环境变量指向的 SDK 缓存。
///
/// 两个来源都允许失败（静默跳过）：字体缺失时 golden 仍可生成，只是字形退化。
///
/// 已知局限：经由 AnimatedDefaultTextStyle 等显式 TextStyle 组件渲染的文本
/// （如登录页品牌名/页签/链接、概览页 Hero 数值），其目标样式未携带
/// fontFamily，动画结束后整段样式落回测试默认字体，golden 中显示为方块。
/// 这些区域保留几何/颜色回归价值，但不具备字形回归价值；如需完全真实字形，
/// 需在产品样式中补 fontFamily（涉及产品代码，暂不做）。
const String kGoldenFontFamily = 'GoldenFont';

Future<void> loadGoldenFonts() async {
  // 1) 项目字体：直接按文件读（assets/fonts 未在 pubspec 声明为 bundle 资产，
  //    rootBundle 读不到，但 flutter test 的工作目录就是包根目录）。
  try {
    final noto = File('assets/fonts/NotoSansSC-VF.ttf');
    if (await noto.exists()) {
      final bytes = await noto.readAsBytes();
      // 除自定义族名外，同时覆盖 Flutter 测试默认字体族（'FlutterTest'/
      // 'Ahem'）：部分文本样式不继承主题 fontFamily，会落到默认族渲染成
      // 方块，覆盖后这些文本也能以真实字形参与 golden 比对。
      for (final family in <String>[kGoldenFontFamily, 'FlutterTest', 'Ahem']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
      }
    }
  } catch (_) {
    // 字体加载失败时退化为默认测试字体，golden 仍可生成。
  }

  // 2) Material Icons：位于 Flutter SDK 缓存中，随 FLUTTER_ROOT 定位。
  try {
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null && flutterRoot.isNotEmpty) {
      final icons = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/'
        'MaterialIcons-Regular.otf',
      );
      if (await icons.exists()) {
        final bytes = await icons.readAsBytes();
        final loader = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
      }
    }
  } catch (_) {
    // 图标字体不可用时图标退化为方块，不影响布局回归检测。
  }
}
