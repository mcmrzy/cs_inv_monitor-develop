import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/ota/presentation/pages/local_upgrade_page.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/pump_app.dart';

class _MockBleAdapter extends Mock implements BleAdapter {}

void main() {
  late _MockBleAdapter adapter;

  setUp(() async {
    await getIt.reset();
    adapter = _MockBleAdapter();
    when(() => adapter.stopScan()).thenAnswer((_) async {});
    getIt.registerSingleton<BleAdapter>(adapter);
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('empty scan state uses the Xiaoshuo OTA guide', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    await pumpMinimalApp(
      tester,
      const LocalUpgradePage(deviceSN: '', deviceModel: ''),
    );

    final illustration = tester.widget<Image>(find.byType(Image).first);
    final imageProvider = illustration.image;
    final assetImage = imageProvider is ResizeImage
        ? imageProvider.imageProvider as AssetImage
        : imageProvider as AssetImage;
    expect(
      assetImage.assetName,
      CsergyAssets.xiaoshuoOtaGuide,
    );
  });
}
