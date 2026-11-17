import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inv_app/core/auth/token_refresh_service.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/api_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';

import '../../helpers/mock_providers.dart';

class StubAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) respond;
  StubAdapter(this.respond);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      respond(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio dio;
  late MockStorageService storage;
  late MockAuthBloc authBloc;
  late Dio refreshDio;
  late String token;
  late String refreshToken;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await ServiceLocator.init();
    storage = MockStorageService();
    authBloc = MockAuthBloc();
    token = 'old-token';
    refreshToken = 'refresh-token';
    when(() => storage.getToken()).thenAnswer((_) async => token);
    when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
    when(() => storage.saveToken(any())).thenAnswer((call) async {
      token = call.positionalArguments.first as String;
    });
    when(() => storage.saveRefreshToken(any())).thenAnswer((call) async {
      refreshToken = call.positionalArguments.first as String;
    });
    await getIt.unregister<StorageService>();
    getIt.registerSingleton<StorageService>(storage);
    await getIt.unregister<AuthBloc>();
    getIt.registerSingleton<AuthBloc>(authBloc);
    dio = getIt<Dio>();
    refreshDio = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
    refreshDio.httpClientAdapter = StubAdapter((_) async {
      throw StateError('Unexpected refresh request');
    });
    await getIt.unregister<TokenRefreshService>();
    getIt.registerSingleton<TokenRefreshService>(
      TokenRefreshService(
        refreshDio,
        storage,
        () => authBloc.add(AuthLogoutRequested()),
      ),
    );
  });

  tearDown(() async {
    dio.close(force: true);
    refreshDio.close(force: true);
    await getIt.reset();
  });

  test(
      'legacy HTTP 200/code 401 enters session recovery instead of returning data',
      () async {
    dio.httpClientAdapter = StubAdapter(
      (_) async =>
          jsonResponse(200, {'code': 401, 'message': 'access session revoked'}),
    );

    await expectLater(
      dio.get<dynamic>('/stations'),
      throwsA(isA<DioException>()),
    );
    verify(() => authBloc.add(AuthLogoutRequested())).called(1);
  });

  test('HTTP 401 without a refresh token requests login', () async {
    dio.httpClientAdapter = StubAdapter(
      (_) async => jsonResponse(401, {'code': 401, 'message': 'invalid token'}),
    );

    await expectLater(
      dio.get<dynamic>('/stations'),
      throwsA(isA<DioException>()),
    );
    verify(() => authBloc.add(AuthLogoutRequested())).called(1);
  });

  for (final status in [200, 401]) {
    test('HTTP $status/code 401 refreshes and replays the failed request',
        () async {
      when(() => storage.getRefreshToken())
          .thenAnswer((_) async => refreshToken);
      var refreshes = 0;
      refreshDio.httpClientAdapter = StubAdapter((options) async {
        refreshes++;
        expect(options.path, '/auth/refresh');
        return jsonResponse(200, {
          'code': 0,
          'data': {'access_token': 'new-token', 'refresh_token': 'new-refresh'},
        });
      });
      var requests = 0;
      dio.httpClientAdapter = StubAdapter((options) async {
        requests++;
        expect(options.queryParameters['page'], 2);
        if (options.headers['Authorization'] == 'Bearer old-token') {
          return jsonResponse(status, {'code': 401});
        }
        expect(options.headers['Authorization'], 'Bearer new-token');
        return jsonResponse(200, {
          'code': 0,
          'data': {'items': []},
        });
      });

      final result =
          await dio.get<dynamic>('/stations', queryParameters: {'page': 2});
      expect(result.data['code'], 0);
      expect(requests, 2);
      expect(refreshes, 1);
      expect(refreshToken, 'new-refresh');
      verifyNever(() => authBloc.add(AuthLogoutRequested()));
    });
  }

  for (final status in [200, 401, 403]) {
    test('refresh HTTP $status authentication rejection requests login',
        () async {
      when(() => storage.getRefreshToken())
          .thenAnswer((_) async => refreshToken);
      refreshDio.httpClientAdapter = StubAdapter(
        (_) async =>
            jsonResponse(status, {'code': status == 200 ? 401 : status}),
      );
      dio.httpClientAdapter =
          StubAdapter((_) async => jsonResponse(401, {'code': 401}));

      final result = await getIt<ApiService>()
          .get<dynamic>('/stations', fromJson: (data) => data);
      expect(
        result.fold((failure) => failure, (_) => null),
        isA<UnauthorizedFailure>(),
      );
      verify(() => authBloc.add(AuthLogoutRequested())).called(1);
    });
  }

  for (final status in [200, 500, 503]) {
    test(
        'refresh HTTP $status server failure keeps credentials and can recover',
        () async {
      when(() => storage.getRefreshToken())
          .thenAnswer((_) async => refreshToken);
      refreshDio.httpClientAdapter =
          StubAdapter((_) async => jsonResponse(status, {'code': 500}));
      expect(await ServiceLocator.refreshAccessToken(), isFalse);
      expect(token, 'old-token');
      expect(refreshToken, 'refresh-token');
      verifyNever(() => authBloc.add(AuthLogoutRequested()));

      refreshDio.httpClientAdapter = StubAdapter(
        (_) async => jsonResponse(200, {
          'code': 0,
          'data': {
            'access_token': 'recovered',
            'refresh_token': 'rotated',
          },
        }),
      );
      expect(await ServiceLocator.refreshAccessToken(), isTrue);
      expect(token, 'recovered');
    });
  }

  test('refresh timeout preserves the session', () async {
    when(() => storage.getRefreshToken()).thenAnswer((_) async => refreshToken);
    refreshDio.httpClientAdapter = StubAdapter(
      (options) async => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      ),
    );
    expect(await ServiceLocator.refreshAccessToken(), isFalse);
    expect(token, 'old-token');
    verifyNever(() => authBloc.add(AuthLogoutRequested()));
  });

  test('API and SSE concurrent refresh callers share one rotation', () async {
    when(() => storage.getRefreshToken()).thenAnswer((_) async => refreshToken);
    final release = Completer<void>();
    var refreshes = 0;
    refreshDio.httpClientAdapter = StubAdapter((_) async {
      refreshes++;
      await release.future;
      return jsonResponse(200, {
        'code': 0,
        'data': {'access_token': 'new-token'},
      });
    });
    final calls = List.generate(5, (_) => ServiceLocator.refreshAccessToken());
    release.complete();
    expect(await Future.wait(calls), everyElement(isTrue));
    expect(refreshes, 1);
  });

  test('late 401 from an old request reuses the token already refreshed by SSE',
      () async {
    var requests = 0;
    dio.httpClientAdapter = StubAdapter((options) async {
      requests++;
      if (requests == 1) {
        token = 'refreshed-by-sse';
        return jsonResponse(401, {'code': 401});
      }
      expect(options.headers['Authorization'], 'Bearer refreshed-by-sse');
      return jsonResponse(200, {'code': 0});
    });
    expect((await dio.get<dynamic>('/stations')).data['code'], 0);
    verifyNever(() => storage.getRefreshToken());
    verifyNever(() => authBloc.add(AuthLogoutRequested()));
  });

  test('a replay still returning legacy code 401 logs out without looping',
      () async {
    when(() => storage.getRefreshToken()).thenAnswer((_) async => refreshToken);
    var refreshes = 0;
    refreshDio.httpClientAdapter = StubAdapter((_) async {
      refreshes++;
      return jsonResponse(200, {
        'code': 0,
        'data': {'access_token': 'new-token'},
      });
    });
    dio.httpClientAdapter =
        StubAdapter((_) async => jsonResponse(200, {'code': 401}));
    await expectLater(
      dio.get<dynamic>('/stations'),
      throwsA(isA<DioException>()),
    );
    expect(refreshes, 1);
    verify(() => authBloc.add(AuthLogoutRequested())).called(1);
  });

  test('guest requests and organization context errors do not start refresh',
      () async {
    dio.httpClientAdapter =
        StubAdapter((_) async => jsonResponse(200, {'code': 401}));
    await expectLater(
      dio.post<dynamic>('/auth/context'),
      throwsA(isA<DioException>()),
    );
    when(() => storage.getToken()).thenAnswer((_) async => null);
    await expectLater(
      dio.get<dynamic>('/stations'),
      throwsA(isA<DioException>()),
    );
    verifyNever(() => storage.getRefreshToken());
    verifyNever(() => authBloc.add(AuthLogoutRequested()));
  });

  test('permission denied does not expire the session', () async {
    dio.httpClientAdapter =
        StubAdapter((_) async => jsonResponse(403, {'code': 403}));
    await expectLater(
      dio.get<dynamic>('/stations'),
      throwsA(isA<DioException>()),
    );
    verifyNever(() => storage.getRefreshToken());
    verifyNever(() => authBloc.add(AuthLogoutRequested()));
  });
}
