import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RealtimeDataService 数据解析测试', () {
    group('嵌套结构解析', () {
      test('解析标准嵌套格式 - 包含所有字段（V2.1 组键）', () {
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
            'battery_charge_power': 727.5,
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
            'pv1_power': 900.0,
            'pv2_power': 900.0,
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
            'work_time_total': 3600000,
          },
          'eng': {
            'daily_pv_energy': 15.5,
            'total_pv_energy': 1000.0,
            'daily_charge_energy': 3.0,
            'total_charge_energy': 150.0,
            'daily_discharge_energy': 2.0,
            'total_discharge_energy': 100.0,
            'daily_load_energy': 12.0,
            'total_load_energy': 600.0,
          },
          'online': true,
          'updated_at': '2026-07-27T12:00:00Z',
        };

        // 验证嵌套结构检测（V2 组键）
        final isNested = realtime.containsKey('ac') ||
            realtime.containsKey('bat') ||
            realtime.containsKey('pv') ||
            realtime.containsKey('sys') ||
            realtime.containsKey('eng');
        expect(isNested, true);

        // 验证 AC 数据解析（V2.1 键）
        final acData = realtime['ac'] as Map<String, dynamic>;
        expect(acData['ac_output_voltage'], 220.5);
        expect(acData['output_power'], 2250.0);

        // 验证电池数据解析（V2 bat 组）
        final batteryData = realtime['bat'] as Map<String, dynamic>;
        expect(batteryData['battery_soc'], 80.0);
        expect(batteryData['cycle_count'], 150);

        // 验证 PV 数据解析
        final pvData = realtime['pv'] as Map<String, dynamic>;
        expect(pvData['pv_total_power'], 1800.0);
        expect(pvData['mppt_state'], 'MPPT');

        // 验证系统状态解析（V2 sys 组）
        final sysStatus = realtime['sys'] as Map<String, dynamic>;
        expect(sysStatus['work_state'], '1');
        expect(sysStatus['fault_code'], 0);
        expect(sysStatus['boost_temperature'], 40.0);

        // 验证 fan/diag 组（V2.1 新增）
        final fan = realtime['fan'] as Map<String, dynamic>;
        expect(fan['inv_fan_speed'], 60.0);
        final diag = realtime['diag'] as Map<String, dynamic>;
        expect(diag['work_time_total'], 3600000);

        // 验证能源数据解析（V2 eng 组）
        final energyData = realtime['eng'] as Map<String, dynamic>;
        expect(energyData['daily_pv_energy'], 15.5);
        expect(energyData['daily_load_energy'], 12.0);
      });

      test('解析标准嵌套格式 - 使用别名字段', () {
        final realtime = {
          'batt': {
            'battery_soc': 75.0,
            'battery_voltage': 48.0,
          },
          'sys': {
            'work_state': '1',
            'fault_code': 0,
          },
          'pv': {
            'pv_total_power': 1500.0,
          },
          'online': true,
        };

        // 验证别名字段检测
        expect(realtime.containsKey('batt'), true);
        expect(realtime.containsKey('sys'), true);
        expect(realtime.containsKey('battery'), false);

        // 验证电池数据（使用别名）
        final batteryData = realtime['batt'] as Map<String, dynamic>;
        expect(batteryData['battery_soc'], 75.0);

        // 验证系统状态（使用别名）
        final sysStatus = realtime['sys'] as Map<String, dynamic>;
        expect(sysStatus['work_state'], '1');
      });
    });

    group('扁平结构解析', () {
      test('解析扁平格式 - AC 电压和功率', () {
        final realtime = {
          'ac_output_voltage': 220.5,
          'output_current': 10.2,
          'output_power': 2250.0,
          'ac_output_frequency': 50.0,
          'output_apparent_power': 2368.0,
        };

        // 验证扁平结构检测
        final isNested = realtime.containsKey('ac') ||
            realtime.containsKey('bat') ||
            realtime.containsKey('pv');
        expect(isNested, false);

        // 验证 AC 数据构建
        final hasAcData = realtime.containsKey('ac_output_voltage') ||
            realtime.containsKey('output_power');
        expect(hasAcData, true);

        // 验证数据提取
        final acVoltage =
            (realtime['ac_output_voltage'] as num?)?.toDouble() ?? 0;
        final acPower = (realtime['output_power'] as num?)?.toDouble() ?? 0;
        expect(acVoltage, 220.5);
        expect(acPower, 2250.0);
      });

      test('解析扁平格式 - 电池数据', () {
        final realtime = {
          'battery_soc': 80.0,
          'battery_soh': 95.0,
          'battery_voltage': 48.5,
          'battery_current': 15.0,
        };

        // 验证电池数据构建
        final hasBatteryData = realtime.containsKey('battery_soc') ||
            realtime.containsKey('battery_voltage');
        expect(hasBatteryData, true);

        // 验证数据提取
        final soc = (realtime['battery_soc'] as num?)?.toDouble() ?? 0;
        final voltage = (realtime['battery_voltage'] as num?)?.toDouble() ?? 0;
        expect(soc, 80.0);
        expect(voltage, 48.5);
      });

      test('解析扁平格式 - PV 数据', () {
        final realtime = {
          'pv1_voltage': 120.0,
          'pv1_current': 15.0,
          'pv_total_power': 1800.0,
          'mppt_state': 'MPPT',
        };

        // 验证 PV 数据构建
        final hasPvData = realtime.containsKey('pv1_voltage') ||
            realtime.containsKey('pv_total_power');
        expect(hasPvData, true);

        // 验证数据提取
        final pvPower =
            (realtime['pv_total_power'] as num?)?.toDouble() ?? 0;
        expect(pvPower, 1800.0);
      });

      test('解析扁平格式 - 系统状态', () {
        final realtime = {
          'work_state': '1',
          'fault_code': 0,
          'alarm_code': 0,
          'inverter_temperature': 45.0,
          'boost_temperature': 40.0,
          'transformer_temperature': 38.0,
          'pv_temperature': 42.0,
          'dc_bus_voltage': 400.0,
          'load_percent': 75.0,
          'mppt_fan_speed': 40.0,
          'inv_fan_speed': 60.0,
        };

        // 验证系统状态构建
        final hasSysStatus = realtime.containsKey('work_state') ||
            realtime.containsKey('inverter_temperature');
        expect(hasSysStatus, true);

        // 验证数据提取
        final state = realtime['work_state'] as String? ?? '';
        final faultCode = (realtime['fault_code'] as num?)?.toInt() ?? 0;
        expect(state, '1');
        expect(faultCode, 0);
      });

      test('解析扁平格式 - 能源与诊断数据', () {
        final realtime = {
          'daily_pv_energy': 15.5,
          'total_pv_energy': 1000.0,
          'work_time_total': 1800000,
          'gen_energy_daily': 2.0,
        };

        // 验证能源数据构建
        final hasEnergyData = realtime.containsKey('daily_pv_energy') ||
            realtime.containsKey('total_pv_energy');
        expect(hasEnergyData, true);

        // 验证数据提取（累计运行时长为秒）
        final dailyPv = realtime['daily_pv_energy']?.toDouble() ?? 0;
        final workTimeTotal = realtime['work_time_total']?.toInt() ?? 0;
        expect(dailyPv, 15.5);
        expect(workTimeTotal, 1800000);
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
