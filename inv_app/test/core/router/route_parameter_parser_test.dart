import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/router/route_parameter_parser.dart';

void main() {
  group('parsePositiveRouteInt', () {
    test('accepts positive integer values', () {
      expect(parsePositiveRouteInt('1'), 1);
      expect(parsePositiveRouteInt('42'), 42);
    });

    test('returns null when an optional value is missing', () {
      expect(parsePositiveRouteInt(null), isNull);
      expect(parsePositiveRouteInt(''), isNull);
    });

    test('rejects non-numeric values', () {
      expect(parsePositiveRouteInt('station-a'), isNull);
    });

    test('rejects zero and negative values', () {
      expect(parsePositiveRouteInt('0'), isNull);
      expect(parsePositiveRouteInt('-1'), isNull);
    });
  });

  group('parseNonNegativeRouteInt', () {
    test('accepts zero and positive integer values', () {
      expect(parseNonNegativeRouteInt('0'), 0);
      expect(parseNonNegativeRouteInt('42'), 42);
    });

    test('uses the fallback for missing, non-numeric, or negative values', () {
      expect(parseNonNegativeRouteInt(null), 0);
      expect(parseNonNegativeRouteInt('task-a'), 0);
      expect(parseNonNegativeRouteInt('-1'), 0);
    });

    test('supports an explicit fallback', () {
      expect(parseNonNegativeRouteInt('task-a', fallback: 7), 7);
    });
  });

  test('describes an invalid required parameter clearly', () {
    expect(
      invalidPositiveRouteParameterMessage('id'),
      'Invalid route parameter "id": expected a positive integer.',
    );
  });
}
