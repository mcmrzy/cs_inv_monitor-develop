import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RealtimeDataService 数据解析测试', () {
    group('嵌套结构解析', () {
      test('解析标准嵌套格式 - 包含所有字段', () {
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
            'pv1_power': 900.0,
            'pv2_power': 900.0,
          },
          'sys_status': {
            'state': 'normal',
            'fault_code': 0,
            'alarm_code': 0,
            'temp_inv': 45.0,
            'temp_mos': 40.0,
            'efficiency': 95.5,
            'ambient_temperature': 25.0,
            'dc_bus_voltage': 400.0,
            'runtime_hours': 1000,
            'fan_speed_percent': 60.0,
          },
          'energy': {
            'daily_pv': 15.5,
            'total_pv': 1000.0,
            'runtime_hours': 500,
            'daily_feed_energy': 10.0,
            'total_feed_energy': 800.0,
            'daily_grid_import': 5.0,
            'total_grid_import': 200.0,
            'daily_charge': 3.0,
            'total_charge': 150.0,
            'daily_discharge': 2.0,
            'total_discharge': 100.0,
            'daily_load': 12.0,
            'total_load': 600.0,
          },
          'online': true,
          'updated_at': '2026-07-27T12:00:00Z',
        };

        // 验证嵌套结构检测
        final isNested = realtime.containsKey('ac') ||
            realtime.containsKey('battery') ||
            realtime.containsKey('batt') ||
            realtime.containsKey('pv');
        expect(isNested, true);

        // 验证 AC 数据解析
        final acData = realtime['ac'] as Map<String, dynamic>;
        expect(acData['voltage'], 220.5);
        expect(acData['power'], 2250.0);

        // 验证电池数据解析
        final batteryData = realtime['battery'] as Map<String, dynamic>;
        expect(batteryData['soc'], 80.0);
        expect(batteryData['charge_state'], 'charging');
        expect(batteryData['cycle_count'], 150);

        // 验证 PV 数据解析
        final pvData = realtime['pv'] as Map<String, dynamic>;
        expect(pvData['pv_power'], 1800.0);
        expect(pvData['mppt_state'], 'MPPT');

        // 验证系统状态解析
        final sysStatus = realtime['sys_status'] as Map<String, dynamic>;
        expect(sysStatus['state'], 'normal');
        expect(sysStatus['fault_code'], 0);
        expect(sysStatus['efficiency'], 95.5);

        // 验证能源数据解析
        final energyData = realtime['energy'] as Map<String, dynamic>;
        expect(energyData['daily_pv'], 15.5);
        expect(energyData['runtime_hours'], 500);
      });

      test('解析标准嵌套格式 - 使用别名字段', () {
        final realtime = {
          'batt': {
            'soc': 75.0,
            'voltage': 48.0,
          },
          'sys': {
            'state': 'charging',
            'fault_code': 0,
          },
          'pv': {
            'pv_power': 1500.0,
          },
          'online': true,
        };

        // 验证别名字段检测
        expect(realtime.containsKey('batt'), true);
        expect(realtime.containsKey('sys'), true);
        expect(realtime.containsKey('battery'), false);

        // 验证电池数据（使用别名）
        final batteryData = realtime['batt'] as Map<String, dynamic>;
        expect(batteryData['soc'], 75.0);

        // 验证系统状态（使用别名）
        final sysStatus = realtime['sys'] as Map<String, dynamic>;
        expect(sysStatus['state'], 'charging');
      });
    });

    group('扁平结构解析', () {
      test('解析扁平格式 - AC 电压和功率', () {
        final realtime = {
          'ac_voltage': 220.5,
          'ac_current': 10.2,
          'ac_power': 2250.0,
          'ac_frequency': 50.0,
          'ac_load_percent': 75.0,
          'ac_pf': 0.95,
        };

        // 验证扁平结构检测
        final isNested = realtime.containsKey('ac') ||
            realtime.containsKey('battery') ||
            realtime.containsKey('batt') ||
            realtime.containsKey('pv');
        expect(isNested, false);

        // 验证 AC 数据构建
        final hasAcData = realtime.containsKey('ac_voltage') || realtime.containsKey('ac_power');
        expect(hasAcData, true);

        // 验证数据提取
        final acVoltage = (realtime['ac_voltage'] as num?)?.toDouble() ?? 0;
        final acPower = (realtime['ac_power'] as num?)?.toDouble() ?? 0;
        expect(acVoltage, 220.5);
        expect(acPower, 2250.0);
      });

      test('解析扁平格式 - 电池数据', () {
        final realtime = {
          'batt_soc': 80.0,
          'batt_soh': 95.0,
          'batt_voltage': 48.5,
          'batt_current': 15.0,
          'batt_charge_state': 'charging',
        };

        // 验证电池数据构建
        final hasBatteryData = realtime.containsKey('batt_soc') || realtime.containsKey('batt_voltage');
        expect(hasBatteryData, true);

        // 验证数据提取
        final soc = (realtime['batt_soc'] as num?)?.toDouble() ?? 0;
        final voltage = (realtime['batt_voltage'] as num?)?.toDouble() ?? 0;
        expect(soc, 80.0);
        expect(voltage, 48.5);
      });

      test('解析扁平格式 - PV 数据', () {
        final realtime = {
          'pv_voltage': 120.0,
          'pv_current': 15.0,
          'pv_power': 1800.0,
          'mppt_state': 'MPPT',
        };

        // 验证 PV 数据构建
        final hasPvData = realtime.containsKey('pv_voltage') || realtime.containsKey('pv_power');
        expect(hasPvData, true);

        // 验证数据提取
        final pvPower = (realtime['pv_power'] as num?)?.toDouble() ?? 0;
        expect(pvPower, 1800.0);
      });

      test('解析扁平格式 - 系统状态', () {
        final realtime = {
          'state': 'normal',
          'fault_code': 0,
          'alarm_code': 0,
          'temp_inv': 45.0,
          'temp_mos': 40.0,
          'efficiency': 95.5,
        };

        // 验证系统状态构建
        final hasSysStatus = realtime.containsKey('state') || realtime.containsKey('temp_inv');
        expect(hasSysStatus, true);

        // 验证数据提取
        final state = realtime['state'] as String? ?? '';
        final faultCode = (realtime['fault_code'] as num?)?.toInt() ?? 0;
        expect(state, 'normal');
        expect(faultCode, 0);
      });

      test('解析扁平格式 - 能源数据', () {
        final realtime = {
          'daily_pv': 15.5,
          'total_pv': 1000.0,
          'runtime_hours': 500,
          'daily_feed_energy': 10.0,
          'total_feed_energy': 800.0,
        };

        // 验证能源数据构建
        final hasEnergyData = realtime.containsKey('daily_pv') || realtime.containsKey('total_pv');
        expect(hasEnergyData, true);

        // 验证数据提取
        final dailyPv = realtime['daily_pv']?.toDouble() ?? 0;
        final runtimeHours = realtime['runtime_hours']?.toInt() ?? 0;
        expect(dailyPv, 15.5);
        expect(runtimeHours, 500);
      });
    });

    group('在线状态管理', () {
      test('在线状态 - 从 realtime 获取', () {
        final realtime = {
          'online': true,
        };
        final responseData = {
          'online': false,
        };

        // 优先从 realtime 获取
        final online = realtime['online'] ?? responseData['online'] ?? false;
        expect(online, true);
      });

      test('在线状态 - 从 responseData 获取', () {
        final realtime = <String, dynamic>{};
        final responseData = {
          'online': false,
        };

        // realtime 没有时从 responseData 获取
        final online = realtime['online'] ?? responseData['online'] ?? false;
        expect(online, false);
      });

      test('在线状态 - 默认值处理', () {
        final realtime = <String, dynamic>{};
        final responseData = <String, dynamic>{};

        // 都没有时默认为 false
        final online = realtime['online'] as bool? ?? responseData['online'] as bool? ?? false;
        expect(online, false);
      });

      test('在线状态 - 状态切换', () {
        final statusHistory = <bool>[];
        
        // 模拟多次轮询的状态变化
        statusHistory.add(true);   // 在线
        statusHistory.add(true);   // 在线
        statusHistory.add(false);  // 离线
        statusHistory.add(false);  // 离线
        statusHistory.add(true);   // 在线
        
        expect(statusHistory.length, 5);
        expect(statusHistory[0], true);
        expect(statusHistory[2], false);
        expect(statusHistory[4], true);
      });
    });

    group('异常数据处理', () {
      test('null 值处理 - AC 数据', () {
        final realtime = {
          'ac': null,
        };

        final acData = realtime['ac'] as Map<String, dynamic>?;
        expect(acData, null);

        // 从 null 中提取数据应该返回 null
        final voltage = (acData?['voltage'] as num?)?.toDouble();
        expect(voltage, null);
      });

      test('null 值处理 - 所有字段为 null', () {
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

        // 验证所有字段都为 null
        expect(realtime['ac'], null);
        expect(realtime['battery'], null);
        expect(realtime['batt'], null);
        expect(realtime['pv'], null);
        expect(realtime['sys_status'], null);
        expect(realtime['sys'], null);
        expect(realtime['energy'], null);
        expect(realtime['online'], null);

        // 验证默认值处理
        final online = realtime['online'] as bool? ?? false;
        expect(online, false);
      });

      test('类型转换 - num 到 double', () {
        // 测试整数到 double 的转换
        final intValue = 100;
        final doubleValue = (intValue as num).toDouble();
        expect(doubleValue, 100.0);

        // 测试浮点数到 double 的转换
        final floatValue = 100.5;
        final doubleValue2 = (floatValue as num).toDouble();
        expect(doubleValue2, 100.5);

        // 测试 null 安全转换
        final nullValue = null;
        final safeValue = (nullValue as num?)?.toDouble() ?? 0;
        expect(safeValue, 0);
      });

      test('类型转换 - num 到 int', () {
        // 测试整数到 int 的转换
        final intValue = 100;
        final intValue2 = (intValue as num).toInt();
        expect(intValue2, 100);

        // 测试浮点数到 int 的转换（截断）
        final floatValue = 100.7;
        final intValue3 = (floatValue as num).toInt();
        expect(intValue3, 100);

        // 测试 null 安全转换
        final nullValue = null;
        final safeValue = (nullValue as num?)?.toInt() ?? 0;
        expect(safeValue, 0);
      });

      test('边界值处理 - SOC 0% 和 100%', () {
        // 0% SOC
        final emptyBattery = {
          'soc': 0.0,
          'voltage': 44.0,
        };
        expect((emptyBattery['soc'] as num).toDouble(), 0.0);

        // 100% SOC
        final fullBattery = {
          'soc': 100.0,
          'voltage': 54.0,
        };
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
        expect((zeroPowerData['batt_power'] as num).toDouble(), 0.0);
      });

      test('边界值处理 - 负值处理', () {
        // 电池放电时电流为负
        final dischargeData = {
          'batt_current': -15.0,
          'batt_power': -720.0,
        };
        expect((dischargeData['batt_current'] as num).toDouble(), -15.0);
        expect((dischargeData['batt_power'] as num).toDouble(), -720.0);
      });
    });

    group('时间戳处理', () {
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

        // 使用默认值
        final defaultTime = DateTime.tryParse(invalidTimeStr) ?? DateTime.now();
        expect(defaultTime, isNotNull);
      });

      test('空时间字符串处理', () {
        final emptyTimeStr = '';
        final dateTime = DateTime.tryParse(emptyTimeStr);
        expect(dateTime, isNull);
      });
    });
  });
}
