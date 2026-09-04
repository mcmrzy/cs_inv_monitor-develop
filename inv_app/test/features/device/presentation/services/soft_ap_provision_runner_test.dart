import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/provision_service.dart';
import 'package:inv_app/features/device/presentation/services/soft_ap_provision_runner.dart';

ProvisionResult _result({
  required bool success,
  String message = '',
  String? ssid,
  String? ip,
}) {
  return ProvisionResult(
    success: success,
    message: message,
    ssid: ssid,
    ip: ip,
  );
}

void main() {
  test('配置成功后按顺序轮询，连接成功即返回设备网络信息', () async {
    final calls = <String>[];
    var pollCount = 0;
    final runner = SoftApProvisionRunner(
      configure: (ssid, password) async {
        calls.add('configure:$ssid:$password');
        return _result(success: true);
      },
      checkStatus: () async {
        pollCount++;
        calls.add('poll:$pollCount');
        return pollCount == 2
            ? _result(
                success: true,
                ssid: 'Office WiFi',
                ip: '192.168.1.9',
              )
            : _result(success: false);
      },
      ensureWifiRoute: () async => calls.add('route'),
      delay: (_) async => calls.add('delay'),
    );

    final waiting = <int>[];
    final outcome = await runner.run(
      ssid: 'Office WiFi',
      password: ' secret ',
      isActive: () => true,
      onConfigured: () => calls.add('configured'),
      onWaiting: waiting.add,
    );

    expect(outcome.type, SoftApProvisionOutcomeType.connected);
    expect(outcome.ssid, 'Office WiFi');
    expect(outcome.ip, '192.168.1.9');
    expect(waiting, [1]);
    expect(
      calls,
      [
        'route',
        'configure:Office WiFi: secret ',
        'configured',
        'delay',
        'route',
        'poll:1',
        'delay',
        'route',
        'poll:2',
      ],
    );
  });

  test('配置请求失败时不开始轮询', () async {
    var polls = 0;
    final runner = SoftApProvisionRunner(
      configure: (_, __) async => _result(
        success: false,
        message: 'device rejected',
      ),
      checkStatus: () async {
        polls++;
        return _result(success: false);
      },
      ensureWifiRoute: () async {},
      delay: (_) async {},
    );

    final outcome = await runner.run(
      ssid: 'ssid',
      password: 'password',
      isActive: () => true,
      onConfigured: () {},
      onWaiting: (_) {},
    );

    expect(outcome.type, SoftApProvisionOutcomeType.failed);
    expect(outcome.message, 'device rejected');
    expect(polls, 0);
  });

  test('操作失效后停止轮询并返回 cancelled', () async {
    var active = true;
    var polls = 0;
    final runner = SoftApProvisionRunner(
      configure: (_, __) async => _result(success: true),
      checkStatus: () async {
        polls++;
        return _result(success: false);
      },
      ensureWifiRoute: () async {},
      delay: (_) async {},
    );

    final outcome = await runner.run(
      ssid: 'ssid',
      password: 'password',
      isActive: () => active,
      onConfigured: () => active = false,
      onWaiting: (_) {},
    );

    expect(outcome.type, SoftApProvisionOutcomeType.cancelled);
    expect(polls, 0);
  });

  test('轮询次数耗尽返回 timedOut，不伪装为成功', () async {
    var polls = 0;
    var delays = 0;
    final runner = SoftApProvisionRunner(
      configure: (_, __) async => _result(success: true),
      checkStatus: () async {
        polls++;
        return _result(success: false);
      },
      ensureWifiRoute: () async {},
      delay: (_) async => delays++,
      maxPollAttempts: 2,
    );

    final outcome = await runner.run(
      ssid: 'ssid',
      password: 'password',
      isActive: () => true,
      onConfigured: () {},
      onWaiting: (_) {},
    );

    expect(outcome.type, SoftApProvisionOutcomeType.timedOut);
    expect(polls, 2);
    // 初始等待一次、两次轮询之间等待一次；最后一次失败后不再空等。
    expect(delays, 2);
  });

  test('开始前已取消时不再切换 WiFi 路由', () async {
    var routeCalls = 0;
    final runner = SoftApProvisionRunner(
      configure: (_, __) async => _result(success: true),
      checkStatus: () async => _result(success: false),
      ensureWifiRoute: () async => routeCalls++,
      delay: (_) async {},
    );

    final outcome = await runner.run(
      ssid: 'ssid',
      password: 'password',
      isActive: () => false,
      onConfigured: () {},
      onWaiting: (_) {},
    );

    expect(outcome.type, SoftApProvisionOutcomeType.cancelled);
    expect(routeCalls, 0);
  });

  test('平台路由异常转成可展示失败结果', () async {
    final runner = SoftApProvisionRunner(
      configure: (_, __) async => _result(success: true),
      checkStatus: () async => _result(success: false),
      ensureWifiRoute: () async => throw StateError('route failed'),
      delay: (_) async {},
    );

    final outcome = await runner.run(
      ssid: 'ssid',
      password: 'password',
      isActive: () => true,
      onConfigured: () {},
      onWaiting: (_) {},
    );

    expect(outcome.type, SoftApProvisionOutcomeType.failed);
    expect(outcome.message, contains('route failed'));
  });
}
