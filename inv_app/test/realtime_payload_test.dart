import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/utils/realtime_payload.dart';

void main() {
  test('explicit offline wins and faulty online status is supported', () {
    expect(
        deviceCloudOnline({
          'online_status': {'online': false},
          'device': {'status': 1}
        }),
        false);
    expect(
        deviceCloudOnline({
          'device': {'status': 2}
        }),
        true);
    expect(
        deviceCloudOnline({
          'device': {'status': 0}
        }),
        false);
    expect(
        deviceCloudOnline({
          'online_status': {'online': true},
          'device': {'status': 0}
        }),
        true);
  });
  test('derived health score remains available to the health page', () {
    expect(
        normalizeRealtimePayload({
          'derived': {'health_score': 30},
        })['derived_health_score'],
        30);
    expect(
        normalizeRealtimePayload({
          'derived': {
            'data': {'health_score': 30}
          },
        })['derived_health_score'],
        30);
  });
  test('delayed or undated detail response cannot replace a newer poll', () {
    final current = DateTime.utc(2026, 10, 9, 3);
    expect(canReplaceTelemetry(current, DateTime.utc(2026, 10, 9, 2)), false);
    expect(canReplaceTelemetry(current, null), false);
    expect(canReplaceTelemetry(current, current), true);
    expect(
        canReplaceTelemetry(current, current.add(const Duration(seconds: 1))),
        true);
    expect(canReplaceTelemetry(null, null), true);
  });
  test('actual server V1 groups and compact latest fallback preserve values',
      () {
    final rt = InverterRealtime.fromJson({
      'ac': {
        'data': {
          'voltage': 230,
          'active_power': 510,
          'apparent_power': 600,
          'power_factor': 0.85
        }
      },
      'pv': {
        'data': {'total_power': 650, 'pv1_power': 432}
      },
      'energy': {
        'data': {'daily_pv': 3.7, 'total_pv': 1234}
      },
      '_timestamp': 1791511200,
      '_updated_at': '2026-10-09T02:01:00Z',
    });
    expect(rt.ac?.power, 510);
    expect(rt.ac?.pf, 0.85);
    expect(rt.pv?.pvPower, 650);
    expect(rt.energy?.totalPV, 1234);
    expect(rt.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(1791511200000, isUtc: true));
    final fallback = InverterRealtime.fromJson({
      'ac_power': 510,
      'daily_pv': 3.7,
      'total_pv': 1234,
      'event_time': '2026-10-09T02:00:00Z',
    });
    expect(fallback.ac?.power, 510);
    expect(fallback.energy?.dailyPV, 3.7);
    expect(fallback.updatedAt, DateTime.utc(2026, 10, 9, 2));
  });
  test('cloud flattened realtime retains AC, PV, battery and energy', () {
    final rt = InverterRealtime.fromJson({
      'device_sn': 'H1ZZX0013900002H',
      'ac_output_voltage': 230.5,
      'output_current': 2.4,
      'output_power': 550,
      'pv1_voltage': 135,
      'pv1_current': 3.2,
      'pv1_power': 432,
      'pv_total_power': 650,
      'battery_soc': 76,
      'battery_power': -120,
      'work_state': 1,
      'daily_pv_energy': 3.7,
      'updated_at': '2026-10-09T02:00:00Z',
    });
    expect(rt.ac?.voltage, 230.5);
    expect(rt.pv?.pv1Power, 432);
    expect(rt.battery?.power, -120);
    expect(rt.energy?.dailyPV, 3.7);
    expect(rt.sysStatus?.state, '1');
    expect(rt.updatedAt, DateTime.utc(2026, 10, 9, 2));
  });

  test('database fallback uses real column names, including numeric MPPT', () {
    final rt = InverterRealtime.fromJson({
      'ac_voltage': '228.4',
      'ac_active_power': 400,
      'ac_frequency': 50,
      'ac_power_factor': 0.95,
      'battery_cycle_count': 12,
      'battery_capacity_remain': 45,
      'battery_power': 0,
      'pv_total_power': 0,
      'mppt_state': 2,
      'runtime_hours': 15,
      'online': 1,
    });
    expect(rt.ac?.voltage, 228.4);
    expect(rt.ac?.power, 400);
    expect(rt.ac?.pf, 0.95);
    expect(rt.battery?.cycleCount, 12);
    expect(rt.pv?.mpptState, '2');
    expect(rt.workTimeTotalSec, 54000);
    expect(rt.onlineStatus?.online, true);
  });

  test('nested cache and legacy keys are normalized without conflating groups',
      () {
    final rt = InverterRealtime.fromJson({
      'ac': {
        'data': {'voltage': 220, 'power': 500}
      },
      'battery': {'soc': 80, 'voltage': 51, 'power': -50},
      'pv': {'pv_voltage': 120, 'pv_power': 600},
      'sys': {
        'data': {'temp_inv': 43, 'state': 1}
      },
      'energy': {'daily_pv': 2.5},
    });
    expect(rt.ac?.power, 500);
    expect(rt.battery?.power, -50);
    expect(rt.pv?.pvPower, 600);
    expect(rt.sysStatus?.tempInv, 43);
    expect(rt.energy?.dailyPV, 2.5);
  });

  test('zero is real data, absent groups remain absent', () {
    final rt = InverterRealtime.fromJson({'output_power': 0});
    expect(rt.ac?.power, 0);
    expect(rt.pv, isNull);
    expect(rt.battery, isNull);
    expect(rt.energy, isNull);
    expect(rt.updatedAt, isNull);
  });
}
