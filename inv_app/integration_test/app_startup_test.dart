// 集成测试最小骨架：App 启动 → 登录页渲染。
//
// ⚠️ 运行要求：必须有一台真实设备或已启动的模拟器（当前环境未启动模拟器，
// 本文件仅作为骨架交付，不在 host 端执行）。运行方式：
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
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:inv_app/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('App 启动到登录页渲染', (tester) async {
    // 启动真实 App（含全部服务初始化）。
    app.main();
    // 等待闪屏/首帧渲染收敛；启动链路有真实网络与平台通道调用，
    // 用宽松的超时分段 pump，避免单次长 pump 冻结动画。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 登录页可见：存在"登录"相关文案（按钮或页签）。
    expect(find.textContaining('登录'), findsWidgets);
  });
}
