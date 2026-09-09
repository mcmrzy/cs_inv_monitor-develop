import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:inv_app/features/ota/presentation/pages/ota_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockOtaBloc extends MockBloc<OtaEvent, OtaState> implements OtaBloc {}

/// OTAPage 内存在持续的帧调度（页面常驻动画），pumpAndSettle 无法收敛，
/// 因此用固定帧推进代替。
void main() {
  Future<void> pumpPage(
    WidgetTester tester,
    _MockOtaBloc otaBloc,
  ) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [BlocProvider<OtaBloc>.value(value: otaBloc)],
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Material(
            child: ScreenUtilInit(
              designSize: const Size(375, 812),
              minTextAdapt: true,
              builder: (context, child) => child!,
              child: const OTAPage(deviceSN: 'SN1234567890'),
            ),
          ),
        ),
      ),
    );
    // 首帧布局 + 若干固定帧：等状态流入、缓存命中并完成页面过渡
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets(
    'remote OTA trigger asks for confirmation before dispatching the command',
    (tester) async {
      // OTAPage 依赖应用级下载服务单例（仅订阅进度流，测试中不触达真实 IO）。
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      if (!getIt.isRegistered<FirmwareDownloadService>()) {
        getIt.registerSingleton<FirmwareDownloadService>(
          FirmwareDownloadService(Dio(), prefs),
        );
      }

      final otaBloc = _MockOtaBloc();
      const info = <String, dynamic>{
        'upgrade_mode': 'single',
        'firmware_id': 42,
        'version': '1.2.3',
      };
      const updateAvailable = OTAUpdateAvailable(info: info);
      // 页面仅在 BlocListener 缓存状态后渲染检查结果（与真实检查-更新流一致），
      // 因此让状态通过流到达。
      whenListen(
        otaBloc,
        Stream<OtaState>.value(updateAvailable),
        initialState: OTAInitial(),
      );

      // 页面内容超出默认 800x600 测试视口，使用接近真机的分辨率
      tester.view.physicalSize = const Size(750, 1624);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpPage(tester, otaBloc);

      // 升级按钮可见（zh 文案：执行升级）
      expect(find.text('执行升级'), findsOneWidget);

      // 未确认前不触发升级
      verifyNever(
        () => otaBloc.add(
          const OTATriggerRequested(sn: 'SN1234567890', packageId: 42),
        ),
      );

      // 点击升级按钮 → 弹出确认对话框（含风险说明与预计时长）
      await tester.tap(find.text('执行升级'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('开始远程升级'), findsOneWidget);
      expect(find.textContaining('暂停上报与输出'), findsOneWidget);
      expect(find.textContaining('10 分钟'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('确认'), findsOneWidget);

      // 取消 → 不下发升级命令
      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));
      verifyNever(
        () => otaBloc.add(
          const OTATriggerRequested(sn: 'SN1234567890', packageId: 42),
        ),
      );

      // 再次点击并确认 → 下发一次升级命令
      await tester.tap(find.text('执行升级'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('确认'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      verify(
        () => otaBloc.add(
          const OTATriggerRequested(sn: 'SN1234567890', packageId: 42),
        ),
      ).called(1);
    },
  );
}
