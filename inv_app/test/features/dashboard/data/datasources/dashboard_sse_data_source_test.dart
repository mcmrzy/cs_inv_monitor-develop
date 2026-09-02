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
}
