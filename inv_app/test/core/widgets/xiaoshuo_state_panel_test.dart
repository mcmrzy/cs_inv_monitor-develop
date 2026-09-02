import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';

void main() {
  test('decode width rounds physical pixels up to the configured bucket', () {
    expect(
      calculateXiaoshuoDecodeWidth(
        logicalWidth: 172.8,
        devicePixelRatio: 2,
      ),
      384,
    );
    expect(
      calculateXiaoshuoDecodeWidth(
        logicalWidth: 0,
        devicePixelRatio: 2,
      ),
      greaterThan(0),
    );
  });

  testWidgets('uses a bounded physical decode width without changing layout',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1624);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => const MaterialApp(
          home: Scaffold(
            body: XiaoshuoStatePanel(
              asset: CsergyAssets.xiaoshuoSuccess,
              title: 'Success',
              size: 160,
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, closeTo(172.8, 0.01));
    expect(image.height, closeTo(172.8, 0.01));
    expect(image.fit, BoxFit.contain);
    expect(image.errorBuilder, isNotNull);
  });
}
