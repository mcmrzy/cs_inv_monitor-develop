import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/station/data/datasources/station_remote_data_source.dart';
import 'package:inv_app/features/station/data/repositories/station_repository_impl.dart';

void main() {
  late Map<String, dynamic> station;
  late List<Map<String, dynamic>> devices;
  late Map<String, Map<String, dynamic>> readings;
  late List<String> requests;
  late StationRepositoryImpl repository;

  Map<String, dynamic> live(Map<String, dynamic> values,
          {bool online = true, DateTime? time,}) =>
      {
        'online': online,
        'realtime': {
          '_updated_at': (time ?? DateTime.now().toUtc()).toIso8601String(),
          ...values,
        },
      };

  Future<Map<String, dynamic>> load() async {
    final result = await repository.getDetail(7);
    return result.fold((failure) => throw StateError('$failure'),
        (data) => data['station'] as Map<String, dynamic>,);
  }

  setUp(() {
    station = {
      'id': 7,
      'online_count': 1,
      'pv_power': 0.0,
      'load_power': 0.0,
      'batt_power': 0.0,
      'batt_soc': 0.0,
      'grid_power': null,
    };
    devices = [
      {'sn': 'A', 'status': 1},
      {'sn': 'OFF', 'status': 0},
    ];
    readings = {};
    requests = [];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.path);
            final body = options.path == '/stations/7'
                ? {'station': station, 'devices': devices}
                : readings[Uri.decodeComponent(options.path.split('/')[3])];
            if (body == null) {
              handler.reject(DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,),);
            } else {
              handler.resolve(Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'code': 0, 'data': body},),);
            }
          },
        ),
      );
    repository = StationRepositoryImpl(StationRemoteDataSource(dio));
  });

  test('all-device overview uses fresh realtime when station summary is zero',
      () async {
    readings['A'] = live({
      'pv': {'pv_total_power': 2400},
      'ac': {'output_power': 1600, 'ac_input_power': 500},
      'bat': {
        'battery_charge_power': 1300,
        'battery_discharge_power': 0,
        'battery_soc': 78,
      },
    });
    final result = await load();
    expect(result['pv_power'], 2400);
    expect(result['load_power'], 1600);
    expect(result['batt_power'], 1300);
    expect(result['batt_soc'], 78);
    expect(result['grid_power'], 500);
    expect(DateTime.tryParse(result['grid_updated_at'] as String), isNotNull);
    expect(requests, ['/stations/7', '/devices/by-sn/A/realtime']);
  });

  test('fresh measured zero replaces old nonzero summary', () async {
    station['pv_power'] = 900.0;
    readings['A'] = live({
      'pv_total_power': 0,
      'output_power': 0,
      'battery_power': 0,
      'grid_power': 0,
    });
    final result = await load();
    expect(result['pv_power'], 0);
    expect(result['grid_power'], 0);
  });

  test('offline and expired realtime never override station readings',
      () async {
    for (final reading in [
      live({'pv_total_power': 9999}, online: false),
      live({'pv_total_power': 9999},
          time: DateTime.now().toUtc().subtract(const Duration(minutes: 6)),),
      {
        'online': true,
        'realtime': {'pv_total_power': 9999},
      },
    ]) {
      readings['A'] = reading;
      expect((await load())['pv_power'], 0);
    }
  });

  test('failed device read preserves authorized station aggregate', () async {
    station['pv_power'] = 600.0;
    expect((await load())['pv_power'], 600);
  });

  test('deduplicates devices and sums faulted online inverter power', () async {
    devices = [
      {'sn': 'A', 'status': 1},
      {'sn': 'A', 'status': 1},
      {'sn': 'B', 'status': 2},
    ];
    readings['A'] = live({
      'pv_total_power': 1000,
      'battery_discharge_power': 300,
      'battery_soc': 0,
      'grid_power': -100,
    });
    readings['B'] = live({
      'pv_total_power': 400,
      'battery_charge_power': 100,
      'battery_soc': 80,
      'grid_power': 200,
    });
    final result = await load();
    expect(result['pv_power'], 1400);
    expect(result['batt_power'], -200);
    expect(result['batt_soc'], 40);
    expect(result['grid_power'], 100);
    expect(requests.where((path) => path.contains('/A/')), hasLength(1));
  });

  test('partial realtime cannot silently replace a complete station total',
      () async {
    devices = [
      {'sn': 'A', 'status': 1},
      {'sn': 'B', 'status': 1},
    ];
    station['pv_power'] = 1600.0;
    readings['A'] = live({'pv_total_power': 400});
    expect((await load())['pv_power'], 1600);
  });

  test('wrapper data_time is accepted without changing the sample time',
      () async {
    final stamp = DateTime.now().toUtc().subtract(const Duration(seconds: 30));
    readings['A'] = {
      'online': true,
      'data_time': stamp.toIso8601String(),
      'realtime': {'pv_total_power': 700, 'grid_power': -200},
    };
    final result = await load();
    expect(result['pv_power'], 700);
    expect(DateTime.parse(result['grid_updated_at'] as String), stamp);
  });

  test('missing grid fields do not block measured PV and load power', () async {
    readings['A'] = live({'pv_total_power': 900, 'output_power': 500});
    final result = await load();
    expect(result['pv_power'], 900);
    expect(result['load_power'], 500);
    expect(result['grid_power'], isNull);
  });

  test('old BMS link status does not erase fresh inverter-side battery power',
      () async {
    readings['A'] = live({
      'battery_voltage': 48,
      'battery_power': -600,
      'battery_soc': 55,
      'bms_summary': {
        'bms_online': 0,
        'battery_count': 0,
        'layout': 0,
        'updated_at': '2026-10-13T05:58:45Z',
        'expires_at': '2026-10-13T06:02:18Z',
      },
    });
    final result = await load();
    expect(result['batt_power'], -600);
    expect(result['batt_soc'], 55);
  });

  test('legacy inverter with empty category still receives realtime power',
      () async {
    devices = [
      {
        'sn': 'A',
        'status': 1,
        'model_category': '',
        'device_type': 'off_grid_inverter',
      },
      {'sn': 'COLLECTOR', 'status': 1, 'model_category': 'collector'},
    ];
    readings['A'] = live({'pv_total_power': 800});
    expect((await load())['pv_power'], 800);
    expect(requests, ['/stations/7', '/devices/by-sn/A/realtime']);
  });

  test('V2 numeric sample timestamp is recognized', () async {
    readings['A'] = {
      'online': true,
      'realtime': {
        '_timestamp': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        'output_power': 750,
      },
    };
    expect((await load())['load_power'], 750);
  });
}
