import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/network/api_client.dart';
import 'package:inv_app/core/services/domain_config_service.dart';

/// 返回固定 JSON 的 Dio 适配器（模拟 /config/public 响应）
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final String body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }
}

/// 抛错的适配器：模拟网络失败
class _ThrowingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw Exception('network down');
  }
}

void main() {
  group('DomainConfigService.refresh', () {
    test('合法配置覆盖前端域并合并下载信任主机', () async {
      final dio = Dio()
        ..options.baseUrl = 'https://api.example.com'
        ..httpClientAdapter = _StubAdapter(
          '{"code":0,"message":"success","data":{'
          '"download_base_url":"https://download.example.com/",'
          '"frontend_base_url":"https://www.example-online.com"}}',
        );
      final service = DomainConfigService(ApiClient(dio));

      await service.refresh();

      expect(service.frontendBaseUrl, 'https://www.example-online.com');
      expect(
        service.trustedDownloadHosts,
        containsAll(<String>['download.example.com', 'download.jiuxiaoyw.online']),
      );
    });

    test('localhost/私网/非 http(s) 配置被拒绝，保留构建期默认值', () async {
      final dio = Dio()
        ..options.baseUrl = 'https://api.example.com'
        ..httpClientAdapter = _StubAdapter(
          '{"code":0,"message":"success","data":{'
          '"download_base_url":"http://192.168.1.1",'
          '"frontend_base_url":"https://localhost"}}',
        );
      final service = DomainConfigService(ApiClient(dio));

      await service.refresh();

      expect(service.frontendBaseUrl, AppConfig.frontendBaseUrl);
      expect(
        service.trustedDownloadHosts,
        equals(
          AppConfig.trustedDownloadHosts
              .split(',')
              .map((h) => h.trim().toLowerCase())
              .toList(),
        ),
      );
    });

    test('code 非 0 时保留默认值', () async {
      final dio = Dio()
        ..options.baseUrl = 'https://api.example.com'
        ..httpClientAdapter = _StubAdapter(
          '{"code":1,"message":"boom","data":null}',
        );
      final service = DomainConfigService(ApiClient(dio));

      await service.refresh();

      expect(service.frontendBaseUrl, AppConfig.frontendBaseUrl);
    });

    test('网络异常静默降级，不抛出', () async {
      final dio = Dio()
        ..options.baseUrl = 'https://api.example.com'
        ..httpClientAdapter = _ThrowingAdapter();
      final service = DomainConfigService(ApiClient(dio));

      await expectLater(service.refresh(), completes);
      expect(service.frontendBaseUrl, AppConfig.frontendBaseUrl);
    });
  });
}
