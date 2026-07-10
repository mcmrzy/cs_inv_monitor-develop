import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/core/services/api_service.dart';
import 'package:inv_app/core/errors/failures.dart';

/// Mock Dio for testing.
class MockDio extends Mock implements Dio {}

/// Mock Response for testing.
class MockResponse extends Mock implements Response {}

void main() {
  late ApiService apiService;
  late MockDio mockDio;

  setUpAll(() {
    registerFallbackValue(Options());
    registerFallbackValue(RequestOptions());
  });

  setUp(() {
    mockDio = MockDio();
    apiService = ApiService(mockDio);
  });

  // ---------------------------------------------------------------------------
  // GET
  // ---------------------------------------------------------------------------
  group('GET', () {
    test('returns Right on successful response with code 0', () async {
      final response = Response(
        requestOptions: RequestOptions(),
        statusCode: 200,
        data: {
          'code': 0,
          'data': {'name': 'test'},
        },
      );
      when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => response);

      final result = await apiService.get(
        '/test',
        fromJson: (json) => json['name'] as String,
      );

      expect(result.isRight(), true);
      result.fold((_) {}, (value) => expect(value, 'test'));
    });

    test('returns Left with ServerFailure on non-zero code', () async {
      final response = Response(
        requestOptions: RequestOptions(),
        statusCode: 200,
        data: {
          'code': 1001,
          'message': 'Invalid input',
        },
      );
      when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => response);

      final result = await apiService.get(
        '/test',
        fromJson: (json) => json,
      );

      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('1001'));
        },
        (_) {},
      );
    });

    test('returns Left with UnauthorizedFailure on 401', () async {
      when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
          .thenThrow(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(),
            statusCode: 401,
          ),
        ),
      );

      final result = await apiService.get(
        '/test',
        fromJson: (json) => json,
      );

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<UnauthorizedFailure>()),
        (_) {},
      );
    });

    test('returns Left with NetworkFailure on connection timeout', () async {
      when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
          .thenThrow(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      final result = await apiService.get(
        '/test',
        fromJson: (json) => json,
      );

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<NetworkFailure>()),
        (_) {},
      );
    });

    test('returns Left with NetworkFailure on connection error', () async {
      when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
          .thenThrow(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.connectionError,
        ),
      );

      final result = await apiService.get(
        '/test',
        fromJson: (json) => json,
      );

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<NetworkFailure>()),
        (_) {},
      );
    });

    test('returns Left with ServerFailure on generic exception', () async {
      when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
          .thenThrow(Exception('Unknown error'));

      final result = await apiService.get(
        '/test',
        fromJson: (json) => json,
      );

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) {},
      );
    });
  });

  // ---------------------------------------------------------------------------
  // POST
  // ---------------------------------------------------------------------------
  group('POST', () {
    test('returns Right on successful response', () async {
      final response = Response(
        requestOptions: RequestOptions(),
        statusCode: 201,
        data: {
          'code': 0,
          'data': {'id': 1},
        },
      );
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
          ),).thenAnswer((_) async => response);

      final result = await apiService.post(
        '/test',
        data: {'name': 'test'},
        fromJson: (json) => json['id'] as int,
      );

      expect(result.isRight(), true);
      result.fold((_) {}, (value) => expect(value, 1));
    });

    test('returns Left on DioException', () async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
          ),).thenThrow(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(),
            statusCode: 403,
          ),
        ),
      );

      final result = await apiService.post(
        '/test',
        fromJson: (json) => json,
      );

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ForbiddenFailure>()),
        (_) {},
      );
    });
  });

  // ---------------------------------------------------------------------------
  // PUT
  // ---------------------------------------------------------------------------
  group('PUT', () {
    test('returns Right on successful response', () async {
      final response = Response(
        requestOptions: RequestOptions(),
        statusCode: 200,
        data: {
          'code': 0,
          'data': {'updated': true},
        },
      );
      when(() => mockDio.put(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
          ),).thenAnswer((_) async => response);

      final result = await apiService.put(
        '/test/1',
        data: {'name': 'updated'},
        fromJson: (json) => json['updated'] as bool,
      );

      expect(result.isRight(), true);
      result.fold((_) {}, (value) => expect(value, true));
    });
  });

  // ---------------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------------
  group('DELETE', () {
    test(
      'returns Right on successful response', () async {
      final response = Response(
        requestOptions: RequestOptions(),
        statusCode: 200,
        data: {
          'code': 0,
          'data': {},
        },
      );
      when(() => mockDio.delete(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
          ),).thenAnswer((_) async => response);

      final result = await apiService.delete(
        '/test/1',
        fromJson: (json) => json,
      );

      expect(result.isRight(), true);
    });

    test(
      'returns Left with NotFoundFailure on 404', () async {
      when(() => mockDio.delete(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
          ),).thenThrow(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(),
            statusCode: 404,
          ),
        ),
      );

      final result = await apiService.delete(
        '/test/1',
        fromJson: (json) => json,
      );

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<NotFoundFailure>()),
        (_) {},
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Response edge cases
  // ---------------------------------------------------------------------------
  group('Response edge cases', () {
    test('returns Left on invalid response format (non-map)', () async {
      final response = Response(
        requestOptions: RequestOptions(),
        statusCode: 200,
        data: 'not a map',
      );
      when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => response);

      final result = await apiService.get(
        '/test',
        fromJson: (json) => json,
      );

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure.message, 'Invalid response format'),
        (_) {},
      );
    });

    test('returns Left on non-200/201 status code', () async {
      final response = Response(
        requestOptions: RequestOptions(),
        statusCode: 500,
        data: {'code': 0, 'data': {}},
      );
      when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => response);

      final result = await apiService.get(
        '/test',
        fromJson: (json) => json,
      );

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure.message, contains('500')),
        (_) {},
      );
    });
  });
}
