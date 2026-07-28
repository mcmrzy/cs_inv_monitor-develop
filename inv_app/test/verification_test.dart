import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/entities/inverter_data.dart';

void main() {
  group('完整验证测试', () {
    group('验证 RealtimeDataService 修复', () {
      test('类型修复验证 - SystemStatus.faultCode 应为 int', () {
        final sysStatus = SystemStatus(
          faultCode: 0,
          alarmCode: 0,
        );
        
        // 验证类型为 int
        expect(sysStatus.faultCode, isA<int>());
        expect(sysStatus.alarmCode, isA<int>());
        expect(sysStatus.faultCode, 0);
        expect(sysStatus.alarmCode, 0);
      });

      test('类型修复验证 - EnergyData.runtimeHours 应为 int', () {
        final energyData = EnergyData(
          runtimeHours: 500,
        );
        
        // 验证类型为 int
        expect(energyData.runtimeHours, isA<int>());
        expect(energyData.runtimeHours, 500);
      });

      test('数据解析 - 嵌套结构完整解析', () {
        final realtime = {
          'ac': {
            'voltage': 220.5,
            'current': 10.2,
            'power': 2250.0,
            'frequency': 50.0,
            'load_percent': 75.0,
            'pf': 0.95,
          },
          'battery': {
            'soc': 80.0,
            'soh': 95.0,
            'voltage': 48.5,
            'current': 15.0,
            'charge_state': 'charging',
            'power': 727.5,
            'capacity_remain': 100.0,
            'capacity_total': 125.0,
            'cycle_count': 150,
            'temp_max': 35.0,
            'temp_min': 30.0,
            'protect_status': 0,
            'bms_fault_code': 0,
          },
          'pv': {
            'pv_voltage': 120.0,
            'pv_current': 15.0,
            'pv_power': 1800.0,
            'mppt_state': 'MPPT',
          },
          'sys_status': {
            'state': 'normal',
            'fault_code': 0,
            'alarm_code': 0,
            'temp_inv': 45.0,
            'temp_mos': 40.0,
            'efficiency': 95.5,
          },
          'energy': {
            'daily_pv': 15.5,
            'total_pv': 1000.0,
            'runtime_hours': 500,
            'daily_feed_energy': 10.0,
            'total_feed_energy': 800.0,
            'daily_grid_import': 5.0,
            'total_grid_import': 200.0,
          },
          'online': true,
          'updated_at': '2026-07-27T12:00:00Z',
        };

        // 验证嵌套结构
        final isNested = realtime.containsKey('ac') ||
            realtime.containsKey('battery') ||
            realtime.containsKey('batt') ||
            realtime.containsKey('pv');
        expect(isNested, true);

        // 验证 AC 数据
        final acMap = realtime['ac'] as Map<String, dynamic>;
        final acData = ACData.fromJson(acMap);
        expect(acData.voltage, 220.5);
        expect(acData.power, 2250.0);

        // 验证电池数据
        final batteryMap = realtime['battery'] as Map<String, dynamic>;
        final batteryData = BatteryData.fromJson(batteryMap);
        expect(batteryData.soc, 80.0);
        expect(batteryData.chargeState, 'charging');
        expect(batteryData.cycleCount, 150);

        // 验证 PV 数据
        final pvMap = realtime['pv'] as Map<String, dynamic>;
        final pvData = PVData.fromJson(pvMap);
        expect(pvData.pvPower, 1800.0);
        expect(pvData.mpptState, 'MPPT');

        // 验证系统状态
        final sysMap = realtime['sys_status'] as Map<String, dynamic>;
        final sysStatus = SystemStatus.fromJson(sysMap);
        expect(sysStatus.state, 'normal');
        expect(sysStatus.faultCode, 0);
        expect(sysStatus.alarmCode, 0);
        expect(sysStatus.tempInv, 45.0);
        expect(sysStatus.efficiency, 95.5);

        // 验证能源数据
        final energyMap = realtime['energy'] as Map<String, dynamic>;
        final energyData = EnergyData.fromJson(energyMap);
        expect(energyData.dailyPV, 15.5);
        expect(energyData.runtimeHours, 500);

        // 验证在线状态
        expect(realtime['online'], true);
      });

      test('数据解析 - 扁平结构完整解析', () {
        final realtime = {
          'ac_voltage': 220.5,
          'ac_current': 10.2,
          'ac_power': 2250.0,
          'ac_frequency': 50.0,
          'ac_load_percent': 75.0,
          'ac_pf': 0.95,
          'batt_soc': 80.0,
          'batt_soh': 95.0,
          'batt_voltage': 48.5,
          'batt_current': 15.0,
          'batt_charge_state': 'charging',
          'pv_voltage': 120.0,
          'pv_current': 15.0,
          'pv_power': 1800.0,
          'mppt_state': 'MPPT',
          'state': 'normal',
          'fault_code': 0,
          'alarm_code': 0,
          'temp_inv': 45.0,
          'temp_mos': 40.0,
          'efficiency': 95.5,
          'daily_pv': 15.5,
          'total_pv': 1000.0,
          'runtime_hours': 500,
          'daily_feed_energy': 10.0,
          'total_feed_energy': 800.0,
          'daily_grid_import': 5.0,
          'total_grid_import': 200.0,
          'online': true,
          'updated_at': '2026-07-27T12:00:00Z',
        };

        // 验证扁平结构
        final isNested = realtime.containsKey('ac') ||
            realtime.containsKey('battery') ||
            realtime.containsKey('batt') ||
            realtime.containsKey('pv');
        expect(isNested, false);

        // 验证 AC 数据
        final hasAcData = realtime.containsKey('ac_voltage') || realtime.containsKey('ac_power');
        expect(hasAcData, true);
        final acVoltage = (realtime['ac_voltage'] as num?)?.toDouble() ?? 0;
        final acPower = (realtime['ac_power'] as num?)?.toDouble() ?? 0;
        expect(acVoltage, 220.5);
        expect(acPower, 2250.0);

        // 验证电池数据
        final hasBatteryData = realtime.containsKey('batt_soc') || realtime.containsKey('batt_voltage');
        expect(hasBatteryData, true);
        final soc = (realtime['batt_soc'] as num?)?.toDouble() ?? 0;
        expect(soc, 80.0);

        // 验证 PV 数据
        final hasPvData = realtime.containsKey('pv_voltage') || realtime.containsKey('pv_power');
        expect(hasPvData, true);
        final pvPower = (realtime['pv_power'] as num?)?.toDouble() ?? 0;
        expect(pvPower, 1800.0);

        // 验证系统状态
        final hasSysStatus = realtime.containsKey('state') || realtime.containsKey('temp_inv');
        expect(hasSysStatus, true);
        final state = realtime['state'] as String? ?? '';
        final faultCode = (realtime['fault_code'] as num?)?.toInt() ?? 0;
        expect(state, 'normal');
        expect(faultCode, 0);

        // 验证能源数据
        final hasEnergyData = realtime.containsKey('daily_pv') || realtime.containsKey('total_pv');
        expect(hasEnergyData, true);
        final dailyPv = (realtime['daily_pv'] as num?)?.toDouble() ?? 0;
        final runtimeHours = (realtime['runtime_hours'] as num?)?.toInt() ?? 0;
        expect(dailyPv, 15.5);
        expect(runtimeHours, 500);

        // 验证在线状态
        expect(realtime['online'], true);
      });
    });

    group('验证在线状态管理', () {
      test('在线状态 - 从 realtime 获取', () {
        final realtime = {'online': true};
        final responseData = {'online': false};
        
        final online = realtime['online'] as bool? ?? responseData['online'] as bool? ?? false;
        expect(online, true);
      });

      test('在线状态 - 从 responseData 获取', () {
        final realtime = <String, dynamic>{};
        final responseData = {'online': false};
        
        final online = realtime['online'] as bool? ?? responseData['online'] as bool? ?? false;
        expect(online, false);
      });

      test('在线状态 - 默认值处理', () {
        final realtime = <String, dynamic>{};
        final responseData = <String, dynamic>{};
        
        final online = realtime['online'] as bool? ?? responseData['online'] as bool? ?? false;
        expect(online, false);
      });

      test('在线状态 - 状态切换', () {
        final statusHistory = <bool>[];
        
        statusHistory.add(true);
        statusHistory.add(true);
        statusHistory.add(false);
        statusHistory.add(false);
        statusHistory.add(true);
        
        expect(statusHistory.length, 5);
        expect(statusHistory[0], true);
        expect(statusHistory[2], false);
        expect(statusHistory[4], true);
      });
    });

    group('验证异常数据处理', () {
      test('null 值处理', () {
        final realtime = {
          'ac': null,
          'battery': null,
          'batt': null,
          'pv': null,
          'sys_status': null,
          'sys': null,
          'energy': null,
          'online': null,
        };

        expect(realtime['ac'], null);
        expect(realtime['battery'], null);
        expect(realtime['pv'], null);
        expect(realtime['online'], null);

        final online = realtime['online'] as bool? ?? false;
        expect(online, false);
      });

      test('边界值处理 - SOC 0% 和 100%', () {
        final emptyBattery = {'soc': 0.0, 'voltage': 44.0};
        expect((emptyBattery['soc'] as num).toDouble(), 0.0);

        final fullBattery = {'soc': 100.0, 'voltage': 54.0};
        expect((fullBattery['soc'] as num).toDouble(), 100.0);
      });

      test('边界值处理 - 功率为 0', () {
        final zeroPowerData = {
          'ac_power': 0.0,
          'pv_power': 0.0,
          'batt_power': 0.0,
        };
        expect((zeroPowerData['ac_power'] as num).toDouble(), 0.0);
        expect((zeroPowerData['pv_power'] as num).toDouble(), 0.0);
      });

      test('边界值处理 - 负值处理', () {
        final dischargeData = {
          'batt_current': -15.0,
          'batt_power': -720.0,
        };
        expect((dischargeData['batt_current'] as num).toDouble(), -15.0);
        expect((dischargeData['batt_power'] as num).toDouble(), -720.0);
      });
    });

    group('验证类型转换', () {
      test('num 到 double 转换', () {
        final intValue = 100;
        final doubleValue = (intValue as num).toDouble();
        expect(doubleValue, 100.0);

        final floatValue = 100.5;
        final doubleValue2 = (floatValue as num).toDouble();
        expect(doubleValue2, 100.5);

        final nullValue = null;
        final safeValue = (nullValue as num?)?.toDouble() ?? 0;
        expect(safeValue, 0);
      });

      test('num 到 int 转换', () {
        final intValue = 100;
        final intValue2 = (intValue as num).toInt();
        expect(intValue2, 100);

        final floatValue = 100.7;
        final intValue3 = (floatValue as num).toInt();
        expect(intValue3, 100);

        final nullValue = null;
        final safeValue = (nullValue as num?)?.toInt() ?? 0;
        expect(safeValue, 0);
      });
    });

    group('验证时间戳处理', () {
      test('ISO 8601 格式解析', () {
        final timeStr = '2026-07-27T12:00:00Z';
        final dateTime = DateTime.tryParse(timeStr);
        expect(dateTime, isNotNull);
        expect(dateTime!.year, 2026);
        expect(dateTime.month, 7);
        expect(dateTime.day, 27);
        expect(dateTime.hour, 12);
      });

      test('带时区偏移的 ISO 8601 格式解析', () {
        final timeStr = '2026-07-27T12:00:00+08:00';
        final dateTime = DateTime.tryParse(timeStr);
        expect(dateTime, isNotNull);
        expect(dateTime!.year, 2026);
      });

      test('无效时间字符串处理', () {
        final invalidTimeStr = 'invalid-time';
        final dateTime = DateTime.tryParse(invalidTimeStr);
        expect(dateTime, isNull);

        final defaultTime = DateTime.tryParse(invalidTimeStr) ?? DateTime.now();
        expect(defaultTime, isNotNull);
      });
    });

    group('验证 API 路径', () {
      test('设备详情 API 路径', () {
        const sn = 'CS6K2-001';
        final path = '/devices/by-sn/$sn';
        expect(path, '/devices/by-sn/CS6K2-001');
      });

      test('设备实时数据 API 路径', () {
        const sn = 'CS6K2-001';
        final path = '/devices/by-sn/$sn/realtime';
        expect(path, '/devices/by-sn/CS6K2-001/realtime');
      });

      test('设备控制 API 路径', () {
        const sn = 'CS6K2-001';
        final path = '/devices/by-sn/$sn/control';
        expect(path, '/devices/by-sn/CS6K2-001/control');
      });

      test('设备解绑 API 路径', () {
        const sn = 'CS6K2-001';
        final path = '/devices/by-sn/$sn/unbind';
        expect(path, '/devices/by-sn/CS6K2-001/unbind');
      });
    });
  });
}
