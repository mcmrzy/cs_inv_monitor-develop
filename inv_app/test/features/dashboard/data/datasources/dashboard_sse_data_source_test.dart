import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/dashboard/data/datasources/dashboard_sse_data_source.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late DashboardSSEDataSource dataSource;

  setUpAll(() {
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  setUp(() {
    dio = MockDio();
    dataSource = DashboardSSEDataSource(dio);
  });

  Response<ResponseBody> responseFor(
    StreamController<Uint8List> controller,
  ) {
    return Response<ResponseBody>(
      requestOptions: RequestOptions(path: '/dashboard/sse'),
      data: ResponseBody(controller.stream, 200),
    );
  }

  test(
    'disconnect while request is pending ignores the late response',
    () {
      fakeAsync((async) {
        final responseCompleter = Completer<Response<ResponseBody>>();
        final responseStream = StreamController<Uint8List>();
        late CancelToken requestCancelToken;
        when(
          () => dio.get<ResponseBody>(
            '/dashboard/sse',
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          ),
        ).thenAnswer((invocation) {
          requestCancelToken =
              invocation.namedArguments[#cancelToken] as CancelToken;
          return responseCompleter.future;
        });

        dataSource.connectToSSE();
        async.flushMicrotasks();
        dataSource.disconnect();
        expect(requestCancelToken.isCancelled, isTrue);

        responseCompleter.complete(responseFor(responseStream));
        async.flushMicrotasks();

        expect(dataSource.isConnected, isFalse);
        expect(responseStream.hasListener, isFalse);

        responseStream.close();
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        verify(
          () => dio.get<ResponseBody>(
            '/dashboard/sse',
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          ),
        ).called(1);
      });
    },
  );

  for (final termination in ['done', 'error']) {
    test(
      'disconnect cancels the response subscription and $termination does not reconnect',
      () {
        fakeAsync((async) {
          final responseStream = StreamController<Uint8List>();
          when(
            () => dio.get<ResponseBody>(
              '/dashboard/sse',
              cancelToken: any(named: 'cancelToken'),
              options: any(named: 'options'),
            ),
          ).thenAnswer((_) async => responseFor(responseStream));

          dataSource.connectToSSE();
          async.flushMicrotasks();
          expect(dataSource.isConnected, isTrue);
          expect(responseStream.hasListener, isTrue);

          dataSource.disconnect();
          async.flushMicrotasks();
          expect(dataSource.isConnected, isFalse);
          expect(responseStream.hasListener, isFalse);

          if (termination == 'done') {
            responseStream.close();
          } else {
            responseStream.addError(StateError('connection closed'));
          }
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 30));
          async.flushMicrotasks();

          expect(dataSource.isConnected, isFalse);
          verify(
            () => dio.get<ResponseBody>(
              '/dashboard/sse',
              cancelToken: any(named: 'cancelToken'),
              options: any(named: 'options'),
            ),
          ).called(1);
        });
      },
    );
  }

  test('a late callback from an old session cannot pollute a new session', () {
    fakeAsync((async) {
      final firstResponse = Completer<Response<ResponseBody>>();
      final firstStream = StreamController<Uint8List>();
      final secondStream = StreamController<Uint8List>();
      var requests = 0;
      when(
        () => dio.get<ResponseBody>(
          '/dashboard/sse',
          cancelToken: any(named: 'cancelToken'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) {
        requests++;
        if (requests == 1) {
          return firstResponse.future;
        }
        return Future.value(responseFor(secondStream));
      });

      dataSource.connectToSSE();
      async.flushMicrotasks();
      final events = <Map<String, dynamic>>[];
      dataSource.connectToSSE().listen(events.add);
      async.flushMicrotasks();

      expect(dataSource.isConnected, isTrue);
      expect(secondStream.hasListener, isTrue);

      firstResponse.complete(responseFor(firstStream));
      async.flushMicrotasks();
      expect(firstStream.hasListener, isFalse);

      firstStream.add(
        Uint8List.fromList(utf8.encode('data: {"source":"old"}\n')),
      );
      secondStream.add(
        Uint8List.fromList(utf8.encode('data: {"source":"new"}\n')),
      );
      async.flushMicrotasks();

      expect(events, [
        {'source': 'new'},
      ]);

      dataSource.disconnect();
      firstStream.close();
      secondStream.close();
      async.flushMicrotasks();
    });
  });

  test('immediate stream failures back off and stop after five reconnects', () {
    fakeAsync((async) {
      var requests = 0;
      when(
        () => dio.get<ResponseBody>(
          '/dashboard/sse',
          cancelToken: any(named: 'cancelToken'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        requests++;
        return Response<ResponseBody>(
          requestOptions: RequestOptions(path: '/dashboard/sse'),
          data: ResponseBody(const Stream<Uint8List>.empty(), 200),
        );
      });

      dataSource.connectToSSE();
      async.flushMicrotasks();
      expect(requests, 1);

      for (final delaySeconds in [5, 10, 15, 20, 25]) {
        async.elapse(Duration(seconds: delaySeconds));
        async.flushMicrotasks();
      }
      expect(requests, 6);

      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(requests, 6);

      // A caller-created session starts a fresh reconnect budget.
      dataSource.connectToSSE();
      async.flushMicrotasks();
      expect(requests, 7);
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(requests, 8);

      dataSource.disconnect();
    });
  });

  test(
    'a data line split across chunks at a CJK char boundary is reassembled',
    () {
      fakeAsync((async) {
        final responseStream = StreamController<Uint8List>();
        when(
          () => dio.get<ResponseBody>(
            '/dashboard/sse',
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => responseFor(responseStream));

        final events = <Map<String, dynamic>>[];
        dataSource.connectToSSE().listen(events.add);
        async.flushMicrotasks();
        expect(responseStream.hasListener, isTrue);

        // “文”的 UTF-8 编码为 3 字节：chunk1 在其中间截断，多字节字符被劈开。
        // 旧实现按单个 chunk utf8.decode 会抛 FormatException 并中断订阅；
        // 增量解码必须等齐字节后重组，且跨 chunk 的 data 行不能丢。
        final wen = utf8.encode('文');
        expect(wen.length, 3);
        final chunk1 = <int>[
          ...utf8.encode('data: {"msg":"中'),
          ...wen.sublist(0, 2),
        ];
        final chunk2 = <int>[
          ...wen.sublist(2),
          ...utf8.encode('事件"}\n'),
          ...utf8.encode('data: {"n":2}\n'),
        ];

        responseStream.add(Uint8List.fromList(chunk1));
        async.flushMicrotasks();
        // 半截事件不解析、不丢，等待后续 chunk
        expect(events, isEmpty);

        responseStream.add(Uint8List.fromList(chunk2));
        async.flushMicrotasks();
        expect(events, [
          {'msg': '中文事件'},
          {'n': 2},
        ]);

        dataSource.disconnect();
        responseStream.close();
        async.flushMicrotasks();
      });
    },
  );

  test('a malformed data line is skipped without killing the subscription', () {
    fakeAsync((async) {
      final responseStream = StreamController<Uint8List>();
      when(
        () => dio.get<ResponseBody>(
          '/dashboard/sse',
          cancelToken: any(named: 'cancelToken'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => responseFor(responseStream));

      final events = <Map<String, dynamic>>[];
      dataSource.connectToSSE().listen(events.add);
      async.flushMicrotasks();

      responseStream.add(
        Uint8List.fromList(utf8.encode('data: {not-valid-json\n')),
      );
      responseStream.add(
        Uint8List.fromList(utf8.encode('data: {"ok":1}\n')),
      );
      async.flushMicrotasks();
      expect(events, [
        {'ok': 1},
      ]);

      // 坏行只跳过自身，订阅仍存活：后续完整事件继续送达
      responseStream.add(
        Uint8List.fromList(utf8.encode('data: {"ok":2}\n')),
      );
      async.flushMicrotasks();
      expect(events.last, {'ok': 2});

      dataSource.disconnect();
      responseStream.close();
      async.flushMicrotasks();
    });
  });

  test(
    'reconnect exhaustion surfaces SSEConnectionLostException on the stream',
    () {
      fakeAsync((async) {
        var requests = 0;
        when(
          () => dio.get<ResponseBody>(
            '/dashboard/sse',
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async {
          requests++;
          return Response<ResponseBody>(
            requestOptions: RequestOptions(path: '/dashboard/sse'),
            data: ResponseBody(const Stream<Uint8List>.empty(), 200),
          );
        });

        final errors = <Object>[];
        dataSource.connectToSSE().listen((_) {}, onError: errors.add);
        async.flushMicrotasks();

        for (final delaySeconds in [5, 10, 15, 20, 25]) {
          async.elapse(Duration(seconds: delaySeconds));
          async.flushMicrotasks();
        }
        expect(requests, 6);
        expect(errors, hasLength(1));
        final loss = errors.single as SSEConnectionLostException;
        expect(loss.attempts, DashboardSSEDataSource.maxReconnectAttempts);

        // 耗尽后放弃重连，不再发起新请求
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();
        expect(requests, 6);

        dataSource.disconnect();
      });
    },
  );
}
