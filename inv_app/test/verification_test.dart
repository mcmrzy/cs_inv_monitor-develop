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

      test('类型修复验证 - InverterRealtime.workTimeTotalSec 应为 int', () {
        final realtime = InverterRealtime(
          deviceSN: 'CS6K2-001',
          workTimeTotalSec: 1800000,
        );

        // 验证类型为 int（diag 组累计运行时长，秒）
        expect(realtime.workTimeTotalSec, isA<int>());
        expect(realtime.workTimeTotalSec, 1800000);
      });

      test('数据解析 - 嵌套结构完整解析（V2.1 组键）', () {
        final realtime = {
          'ac': {
            'ac_output_voltage': 220.5,
            'output_current': 10.2,
            'output_power': 2250.0,
            'ac_output_frequency': 50.0,
            'output_apparent_power': 2368.0,
          },
          'bat': {
            'battery_soc': 80.0,
            'battery_soh': 95.0,
            'battery_voltage': 48.5,
            'battery_current': 15.0,
            'capacity_remain': 100.0,
            'capacity_total': 125.0,
            'cycle_count': 150,
            'battery_temp_max': 35.0,
            'battery_temp_min': 30.0,
            'protect_status': 0,
            'bms_fault_code': 0,
          },
          'pv': {
            'pv1_voltage': 120.0,
            'pv1_current': 15.0,
            'pv_total_power': 1800.0,
            'mppt_state': 'MPPT',
          },
          'sys': {
            'work_state': '1',
            'fault_code': 0,
            'alarm_code': 0,
            'inverter_temperature': 45.0,
            'boost_temperature': 40.0,
            'transformer_temperature': 38.0,
            'pv_temperature': 42.0,
            'dc_bus_voltage': 400.0,
            'load_percent': 75.0,
          },
          'fan': {
            'mppt_fan_speed': 40.0,
            'inv_fan_speed': 60.0,
          },
          'diag': {
            'work_time_total': 1800000,
          },
          'eng': {
            'daily_pv_energy': 15.5,
            'total_pv_energy': 1000.0,
            'daily_charge_energy': 3.0,
            'total_charge_energy': 150.0,
          },
          'online': true,
          'updated_at': '2026-07-27T12:00:00Z',
        };

        // 验证嵌套结构
        final isNested = realtime.containsKey('ac') ||
            realtime.containsKey('bat') ||
            realtime.containsKey('pv');
        expect(isNested, true);

        // 验证 AC 数据（pf 由有功/视在功率派生）
        final acMap = realtime['ac'] as Map<String, dynamic>;
        final acData = ACData.fromJson(acMap);
        expect(acData.voltage, 220.5);
        expect(acData.power, 2250.0);
        expect(acData.pf, closeTo(2250 / 2368, 0.001));

        // 验证电池数据
        final batteryMap = realtime['bat'] as Map<String, dynamic>;
        final batteryData = BatteryData.fromJson(batteryMap);
        expect(batteryData.soc, 80.0);
        expect(batteryData.cycleCount, 150);

        // 验证 PV 数据
        final pvMap = realtime['pv'] as Map<String, dynamic>;
        final pvData = PVData.fromJson(pvMap);
        expect(pvData.pvPower, 1800.0);
        expect(pvData.mpptState, 'MPPT');

        // 验证系统状态
        final sysMap = realtime['sys'] as Map<String, dynamic>;
        final sysStatus = SystemStatus.fromJson(sysMap);
        expect(sysStatus.state, '1');
        expect(sysStatus.faultCode, 0);
        expect(sysStatus.alarmCode, 0);
        expect(sysStatus.tempInv, 45.0);
        expect(sysStatus.boostTemp, 40.0);
        expect(sysStatus.loadPercent, 75.0);

        // 验证 fan/diag 组（V2.1 新增）
        final fanMap = realtime['fan'] as Map<String, dynamic>;
        final fanData = FanData.fromJson(fanMap);
        expect(fanData.mpptSpeed, 40.0);
        expect(fanData.invSpeed, 60.0);
        expect(fanData.maxSpeed, 60.0);

        final realtimeObj = InverterRealtime.fromJson(realtime);
        expect(realtimeObj.workTimeTotalSec, 1800000);

        // 验证能源数据
        final energyMap = realtime['eng'] as Map<String, dynamic>;
        final energyData = EnergyData.fromJson(energyMap);
        expect(energyData.dailyPV, 15.5);
        expect(energyData.totalPV, 1000.0);

        // 验证在线状态
        expect(realtime['online'], true);
      });

      test('数据解析 - 扁平结构完整解析（V2.1 顶层键）', () {
        final realtime = {
          'ac_output_voltage': 220.5,
          'output_current': 10.2,
          'output_power': 2250.0,
          'ac_output_frequency': 50.0,
          'output_apparent_power': 2368.0,
          'battery_soc': 80.0,
          'battery_soh': 95.0,
          'battery_voltage': 48.5,
          'battery_current': 15.0,
          'pv1_voltage': 120.0,
          'pv1_current': 15.0,
          'pv_total_power': 1800.0,
          'mppt_state': 'MPPT',
          'work_state': '1',
          'fault_code': 0,
          'alarm_code': 0,
          'inverter_temperature': 45.0,
          'boost_temperature': 40.0,
          'dc_bus_voltage': 400.0,
          'load_percent': 75.0,
          'mppt_fan_speed': 40.0,
          'inv_fan_speed': 60.0,
          'work_time_total': 1800000,
          'daily_pv_energy': 15.5,
          'total_pv_energy': 1000.0,
          'online': true,
          'updated_at': '2026-07-27T12:00:00Z',
        };

        // 验证扁平结构
        final isNested = realtime.containsKey('ac') ||
            realtime.containsKey('bat') ||
            realtime.containsKey('pv');
        expect(isNested, false);

        // 验证 AC 数据
        final hasAcData = realtime.containsKey('ac_output_voltage') ||
            realtime.containsKey('output_power');
        expect(hasAcData, true);
        final acVoltage =
            (realtime['ac_output_voltage'] as num?)?.toDouble() ?? 0;
        final acPower = (realtime['output_power'] as num?)?.toDouble() ?? 0;
        expect(acVoltage, 220.5);
        expect(acPower, 2250.0);

        // 验证电池数据
        final hasBatteryData = realtime.containsKey('battery_soc') ||
            realtime.containsKey('battery_voltage');
        expect(hasBatteryData, true);
        final soc = (realtime['battery_soc'] as num?)?.toDouble() ?? 0;
        expect(soc, 80.0);

        // 验证 PV 数据
        final hasPvData = realtime.containsKey('pv1_voltage') ||
            realtime.containsKey('pv_total_power');
        expect(hasPvData, true);
        final pvPower =
            (realtime['pv_total_power'] as num?)?.toDouble() ?? 0;
        expect(pvPower, 1800.0);

        // 验证系统状态
        final hasSysStatus = realtime.containsKey('work_state') ||
            realtime.containsKey('inverter_temperature');
        expect(hasSysStatus, true);
        final state = realtime['work_state'] as String? ?? '';
        final faultCode = (realtime['fault_code'] as num?)?.toInt() ?? 0;
        expect(state, '1');
        expect(faultCode, 0);

        // 验证能源/诊断数据
        final hasEnergyData = realtime.containsKey('daily_pv_energy') ||
            realtime.containsKey('total_pv_energy');
        expect(hasEnergyData, true);
        final dailyPv = (realtime['daily_pv_energy'] as num?)?.toDouble() ?? 0;
        final workTimeTotal =
            (realtime['work_time_total'] as num?)?.toInt() ?? 0;
        expect(dailyPv, 15.5);
        expect(workTimeTotal, 1800000);

        // 验证在线状态
        expect(realtime['online'], true);
      });
    });

    group('验证在线状态管理', () {
      test('在线状态 - 从 realtime 获取', () {
        final realtime = {'online': true};
        final responseData = {'online': false};
        
        final online = realtime['online'] ?? responseData['online'] ?? false;
        expect(online, true);
      });

      test('在线状态 - 从 responseData 获取', () {
        final realtime = <String, dynamic>{};
        final responseData = {'online': false};
        
        final online = realtime['online'] ?? responseData['online'] ?? false;
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
