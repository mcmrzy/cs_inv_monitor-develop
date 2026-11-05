// 集成测试：App 启动 → 跳过首次引导 → 登录页渲染。
//
// 运行要求：必须有一台真实设备或已启动的模拟器。运行方式：
//
//   # 列出可用模拟器并启动其一
//   cmd /c flutter.bat emulators
//   cmd /c flutter.bat emulators --launch <emulator-id>
//
//   # 在目标设备上运行集成测试（不能用普通 `flutter test`）
//   cmd /c flutter.bat test integration_test/app_startup_test.dart -d <device-id>
//
// 说明：`flutter test` 只扫描 test/ 目录，不会拾取 integration_test/，
// 因此 host 端测试套件与 CI 不受本文件影响。
//
// InvApp 的 main() 会初始化 JPush / BLE / 深链 / 网络状态等真实服务，
// 这些服务依赖设备平台通道——这正是该用例必须在真机/模拟器上运行的原因。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:inv_app/features/auth/presentation/pages/auth_page.dart';
import 'package:inv_app/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('App 启动到登录页渲染', (tester) async {
    // 启动真实 App（含全部服务初始化）。
    final testErrorHandler = FlutterError.onError;
    app.main();
    FlutterError.onError = testErrorHandler;
    final loginPage = find.byType(AuthPage);
    final skipOnboarding = find.byKey(const Key('onboarding-skip'));
    var skippedOnboarding = false;

    // 登录页的循环装饰动画会持续请求帧，因此等待目标页面出现。
    for (var attempt = 0; attempt < 120; attempt++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (loginPage.evaluate().isNotEmpty) break;
      if (!skippedOnboarding && skipOnboarding.evaluate().isNotEmpty) {
        await tester.tap(skipOnboarding);
        skippedOnboarding = true;
      }
    }
    expect(loginPage, findsOneWidget);
  });
}
