import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/utils/api_response.dart';

void main() {
  group('unwrapApiResponse', () {
    test('returns valid data', () {
      final result = unwrapApiResponse<List<dynamic>>(
        {'code': 0, 'data': <dynamic>[]},
        validate: (data) => data is List,
        expected: 'a list',
      );

      expect(result, isEmpty);
    });

    test('rejects a HTTP-200 business failure', () {
      expect(
        () => unwrapApiResponse<Map<String, dynamic>>(
          {'code': 500, 'message': 'database failed'},
          validate: (data) => data is Map<String, dynamic>,
          expected: 'an object',
        ),
        throwsA(isA<ApiBusinessException>()),
      );
    });

    test('rejects missing or malformed data', () {
      expect(
        () => unwrapApiResponse<List<dynamic>>(
          {'code': 0, 'data': <String, dynamic>{}},
          validate: (data) => data is List,
          expected: 'a list',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => unwrapApiResponse<List<dynamic>>(
          {'code': 0},
          validate: (data) => data is List,
          expected: 'a list',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
