import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/utils/energy_schedule.dart';

void main() {
  final first = <String, dynamic>{
    'start_time': '08:00',
    'end_time': '10:00',
    'mode': 'charge',
  };
  final duplicate = Map<String, dynamic>.from(first);

  test('validates and normalizes schedule payloads', () {
    expect(
      isEnergySchedulePayload({
        'periods': [first],
      }),
      isTrue,
    );
    expect(
      isEnergySchedulePayload({
        'periods': ['bad'],
      }),
      isFalse,
    );
    expect(
      normalizeSchedulePeriods([first]),
      equals([first]),
    );
  });

  test('replaces exactly one matching period', () {
    final result = replaceSchedulePeriod(
      [first, duplicate],
      first,
      {...first, 'mode': 'idle'},
    );

    expect(result, hasLength(2));
    expect(result.first['mode'], 'idle');
    expect(result.last['mode'], 'charge');
  });

  test('removes exactly one duplicate period', () {
    final result = removeSchedulePeriod([first, duplicate], first);

    expect(result, hasLength(1));
    expect(result.single, duplicate);
  });

  test('rejects edits and deletes for a missing period', () {
    final missing = {
      'start_time': '12:00',
      'end_time': '13:00',
      'mode': 'idle',
    };
    expect(
      () => replaceSchedulePeriod([first], missing, missing),
      throwsFormatException,
    );
    expect(
      () => removeSchedulePeriod([first], missing),
      throwsFormatException,
    );
  });
}
