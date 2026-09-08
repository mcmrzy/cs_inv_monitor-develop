import 'package:flutter_test/flutter_test.dart';

/// 让真实事件循环跑一拍，用于等待跨 zone 的异步链落定。
///
/// 背景（widget 测试坑）：被测页面内部通过 `bloc.stream.listen` 订阅并在
/// 流程结束后 `await subscription.cancel()`。FakeAsync 测试 zone 内无论
/// pump 多少帧，broadcast StreamSubscription.cancel() 返回的 future 都不会
/// 完成——它只在真实事件循环上落定。因此凡是断言"监听已释放 / 页面已解锁"
/// 之前，需要用本方法把真实事件循环跑一轮，再用 pump 让 FakeAsync 侧的
/// setState / 重建收敛。
///
/// 典型用法（emit 终态之后）：
/// ```dart
/// states.add(successState);
/// await tester.pump();
/// await drainRealEventLoop(tester);
/// expect(states.hasListener, isFalse);
/// ```
Future<void> drainRealEventLoop(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pump();
  await tester.pump();
}
