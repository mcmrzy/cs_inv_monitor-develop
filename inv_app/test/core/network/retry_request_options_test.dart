import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/network/retry_request_options.dart';

void main() {
  group('normalizeTokenValue', () {
    test('rejects null empty and whitespace-only token values', () {
      expect(normalizeTokenValue(null), isNull);
      expect(normalizeTokenValue(''), isNull);
      expect(normalizeTokenValue('   \t\n'), isNull);
    });

    test('trims a valid token value', () {
      expect(normalizeTokenValue('  valid-token \n'), 'valid-token');
    });
  });

  group('buildTokenRefreshRetryOptions', () {
    test('rejects a whitespace-only access token', () {
      expect(
        () => buildTokenRefreshRetryOptions(
          RequestOptions(path: '/devices'),
          accessToken: '   ',
        ),
        throwsArgumentError,
      );
    });

    test(
      'preserves request behavior and only replaces authorization metadata',
      () {
        bool validateStatus(int? status) => status == 202;
        final original = RequestOptions(
          path: '/firmware/upload',
          baseUrl: 'https://api.example.com',
          method: 'PUT',
          data: <String, dynamic>{'firmware': 'payload'},
          queryParameters: <String, dynamic>{'device_id': 42},
          headers: <String, dynamic>{
            'Authorization': 'Bearer expired-token',
            'X-Trace-Id': 'trace-1',
          },
          contentType: Headers.jsonContentType,
          responseType: ResponseType.bytes,
          extra: <String, dynamic>{'request_id': 'request-1'},
          validateStatus: validateStatus,
          followRedirects: false,
          connectTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 5),
        );

        final retried = buildTokenRefreshRetryOptions(
          original,
          accessToken: 'fresh-token',
        );

        expect(retried, isNot(same(original)));
        expect(retried.path, original.path);
        expect(retried.baseUrl, original.baseUrl);
        expect(retried.method, original.method);
        expect(retried.data, same(original.data));
        expect(retried.queryParameters, original.queryParameters);
        expect(retried.headers['X-Trace-Id'], 'trace-1');
        expect(retried.headers['Authorization'], 'Bearer fresh-token');
        expect(retried.contentType, original.contentType);
        expect(retried.responseType, original.responseType);
        expect(retried.extra['request_id'], 'request-1');
        expect(retried.validateStatus, same(original.validateStatus));
        expect(retried.followRedirects, original.followRedirects);
        expect(retried.connectTimeout, original.connectTimeout);
        expect(retried.sendTimeout, original.sendTimeout);
        expect(retried.receiveTimeout, original.receiveTimeout);
        expect(isTokenRefreshRetry(retried), isTrue);

        expect(original.headers['Authorization'], 'Bearer expired-token');
        expect(isTokenRefreshRetry(original), isFalse);
      },
    );

    test('deeply isolates header and extra collections from the original', () {
      final original = RequestOptions(
        path: '/devices',
        headers: <String, dynamic>{
          'Authorization': 'Bearer expired-token',
          'X-Metadata': <String, dynamic>{
            'nested': <String, dynamic>{'value': 'original'},
          },
        },
        extra: <String, dynamic>{
          'metadata': <String, dynamic>{
            'flags': <String>['original'],
          },
        },
      );

      final retried = buildTokenRefreshRetryOptions(
        original,
        accessToken: 'fresh-token',
      );

      final retriedHeader = retried.headers['X-Metadata']
          as Map<String, dynamic>;
      final retriedNested = retriedHeader['nested'] as Map<String, dynamic>;
      retriedNested['value'] = 'changed';

      final retriedExtra = retried.extra['metadata'] as Map<String, dynamic>;
      final retriedFlags = retriedExtra['flags'] as List<dynamic>;
      retriedFlags.add('changed');

      final originalHeader = original.headers['X-Metadata']
          as Map<String, dynamic>;
      final originalNested = originalHeader['nested'] as Map<String, dynamic>;
      final originalExtra = original.extra['metadata'] as Map<String, dynamic>;
      final originalFlags = originalExtra['flags'] as List<dynamic>;

      expect(originalNested['value'], 'original');
      expect(originalFlags, <String>['original']);
    });

    test('clones finalized multipart data so upload requests can retry', () async {
      final formData = FormData.fromMap(<String, dynamic>{
        'name': 'station-photo',
        'file': MultipartFile.fromBytes(
          <int>[1, 2, 3],
          filename: 'photo.png',
        ),
      });
      await formData.finalize().drain<void>();

      final original = RequestOptions(
        path: '/stations/1/image',
        method: 'POST',
        data: formData,
      );
      final retried = buildTokenRefreshRetryOptions(
        original,
        accessToken: 'fresh-token',
      );

      final retriedFormData = retried.data as FormData;
      expect(retriedFormData, isNot(same(formData)));
      expect(retriedFormData.fields, formData.fields);
      expect(retriedFormData.files.length, formData.files.length);
      expect(retriedFormData.isFinalized, isFalse);
      await retriedFormData.finalize().drain<void>();
    });
  });
}
