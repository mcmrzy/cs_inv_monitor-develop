import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/domain/services/config_param_apply.dart';

class _CaptureAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<Object> bodies = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    bodies.add(options.data);
    return ResponseBody.fromString(
      '{"code":0,"message":"success","data":{"task_id":"task-${requests.length}"}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  test('applyConfigParamWrites sends one command per param_key', () async {
    final adapter = _CaptureAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/api/v1'))
      ..httpClientAdapter = adapter;

    await applyConfigParamWrites(
      dio: dio,
      sn: 'SN001',
      changes: {
        'set_output_voltage': 230,
        'set_output_priority': 1,
      },
    );

    expect(adapter.requests, hasLength(2));
    expect(adapter.requests[0].path, '/devices/by-sn/SN001/control');
    expect(adapter.bodies[0], {
      'command': 'set_output_voltage',
      'params': {'value': 230},
    });
    expect(adapter.bodies[1], {
      'command': 'set_output_priority',
      'params': {'value': 1},
    });
  });
}
