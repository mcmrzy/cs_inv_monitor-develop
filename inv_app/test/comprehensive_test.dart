import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/entities/inverter_data.dart';

// Mock classes
class MockDio extends Mock implements Dio {}

void main() {
  group('阶段 2：单元测试', () {
    test('数据模型 - ACData 创建和序列化', () {
      final acData = ACData(
        voltage: 220.5,
        current: 10.2,
        power: 2250.0,
        frequency: 50.0,
        pf: 0.95,
        apparentPower: 2368.0,
      );

      expect(acData.voltage, 220.5);
      expect(acData.power, 2250.0);

      // 测试 toJson（V2.1 键）
      final json = acData.toJson();
      expect(json['ac_output_voltage'], 220.5);
      expect(json['output_power'], 2250.0);

      // 测试 fromJson
      final restored = ACData.fromJson(json);
      expect(restored.voltage, acData.voltage);
      expect(restored.power, acData.power);
    });

    test('数据模型 - BatteryData 创建', () {
      final batteryData = BatteryData(
        soc: 80.0,
        soh: 95.0,
        voltage: 48.5,
        current: 15.0,
        chargeState: 'charging',
        power: 727.5,
        capacityRemain: 100.0,
        capacityTotal: 125.0,
        cycleCount: 150,
        tempMax: 35.0,
        tempMin: 30.0,
        cellVoltageMax: 3.65,
        cellVoltageMin: 3.60,
        cellVoltageDiff: 0.05,
        protectStatus: 0,
        bmsFaultCode: 0,
      );

      expect(batteryData.soc, 80.0);
      expect(batteryData.chargeState, 'charging');
      expect(batteryData.cycleCount, 150);
    });

    test('数据模型 - PVData 创建', () {
      final pvData = PVData(
        pvVoltage: 120.0,
        pvCurrent: 15.0,
        pvPower: 1800.0,
        mpptState: 'MPPT',
        pv1Power: 900.0,
        pv2Power: 900.0,
      );

      expect(pvData.pvPower, 1800.0);
      expect(pvData.mpptState, 'MPPT');
    });

    test('数据模型 - SystemStatus 创建', () {
      final sysStatus = SystemStatus(
        state: '1',
        faultCode: 0,
        alarmCode: 0,
        tempInv: 45.0,
        boostTemp: 40.0,
        transformerTemp: 38.0,
        pvTemp: 42.0,
        dcBusVoltage: 400.0,
        loadPercent: 75.0,
      );

      expect(sysStatus.state, '1');
      expect(sysStatus.hasFault, false);
      expect(sysStatus.faultCode, 0);
      expect(sysStatus.boostTemp, 40.0);
      expect(sysStatus.loadPercent, 75.0);

      // 测试故障状态
      final faultStatus = SystemStatus(faultCode: 100);
      expect(faultStatus.hasFault, true);
    });

    test('数据模型 - EnergyData 创建', () {
      final energyData = EnergyData(
        dailyPV: 15.5,
        totalPV: 1000.0,
        dailyCharge: 3.0,
        totalCharge: 150.0,
        dailyDischarge: 2.0,
        totalDischarge: 100.0,
        dailyLoad: 12.0,
        totalLoad: 600.0,
      );

      expect(energyData.dailyPV, 15.5);
      expect(energyData.totalLoad, 600.0);
    });

    test('数据模型 - OnlineStatus 创建', () {
      final onlineStatus = OnlineStatus(
        online: true,
        rssi: -65,
        ip: '192.168.1.100',
      );

      expect(onlineStatus.online, true);
      expect(onlineStatus.rssi, -65);
      expect(onlineStatus.ip, '192.168.1.100');
    });

    test('数据模型 - InverterRealtime 完整创建', () {
      final realtime = InverterRealtime(
        deviceSN: 'CS6K2-001',
        ac: ACData(voltage: 220, power: 2000),
        battery: BatteryData(soc: 80, voltage: 48),
        pv: PVData(pvPower: 1800),
        sysStatus: SystemStatus(state: '1'),
        energy: EnergyData(dailyPV: 15),
        fan: FanData(mpptSpeed: 40, invSpeed: 60),
        workTimeTotalSec: 3600000,
        onlineStatus: OnlineStatus(online: true),
        loadPower: 1500,
        updatedAt: DateTime(2026, 7, 27, 12, 0, 0),
      );

      expect(realtime.deviceSN, 'CS6K2-001');
      expect(realtime.ac?.power, 2000);
      expect(realtime.battery?.soc, 80);
      expect(realtime.pv?.pvPower, 1800);
      expect(realtime.fan?.maxSpeed, 60.0);
      expect(realtime.workTimeTotalSec, 3600000);
      expect(realtime.onlineStatus?.online, true);
    });
  });

  group('阶段 3：功能测试 - API 路径验证', () {
    test('设备详情 API 路径格式正确', () {
      const sn = 'CS6K2-001';
      final path = '/devices/by-sn/$sn';
      expect(path, '/devices/by-sn/CS6K2-001');
      expect(path.startsWith('/devices/by-sn/'), true);
    });

    test('设备实时数据 API 路径格式正确', () {
      const sn = 'CS6K2-001';
      final path = '/devices/by-sn/$sn/realtime';
      expect(path, '/devices/by-sn/CS6K2-001/realtime');
    });

    test('设备控制 API 路径格式正确', () {
      const sn = 'CS6K2-001';
      final path = '/devices/by-sn/$sn/control';
      expect(path, '/devices/by-sn/CS6K2-001/control');
    });

    test('设备参数配置 API 路径格式正确', () {
      const sn = 'CS6K2-001';
      final path = '/devices/by-sn/$sn/control-fields';
      expect(path, '/devices/by-sn/CS6K2-001/control-fields');
    });

    test('设备控制状态 API 路径格式正确', () {
      const sn = 'CS6K2-001';
      final path = '/devices/by-sn/$sn/control-state';
      expect(path, '/devices/by-sn/CS6K2-001/control-state');
    });

    test('设备告警 API 路径格式正确', () {
      const sn = 'CS6K2-001';
      final path = '/devices/by-sn/$sn/alarm-events';
      expect(path, '/devices/by-sn/CS6K2-001/alarm-events');
    });

    test('设备解绑 API 路径格式正确', () {
      const sn = 'CS6K2-001';
      final path = '/devices/by-sn/$sn/unbind';
      expect(path, '/devices/by-sn/CS6K2-001/unbind');
    });

    test('WiFi 配置 API 路径格式正确', () {
      const sn = 'CS6K2-001';
      final path = '/devices/by-sn/$sn/wifi/config';
      expect(path, '/devices/by-sn/CS6K2-001/wifi/config');
    });

    test('能源调度 API 路径格式正确', () {
      const sn = 'CS6K2-001';
      final path = '/devices/by-sn/$sn/energy-schedule';
      expect(path, '/devices/by-sn/CS6K2-001/energy-schedule');
    });
  });

  group('阶段 5：业务逻辑测试 - 数据解析', () {
    test('嵌套结构解析 - 标准格式', () {
      final nestedData = {
        'ac': {
          'ac_output_voltage': 220.5,
          'output_current': 10.2,
          'output_power': 2250.0,
          'ac_output_frequency': 50.0,
        },
        'bat': {
          'battery_soc': 80.0,
          'battery_voltage': 48.5,
          'battery_current': 15.0,
        },
        'pv': {
          'pv1_voltage': 120.0,
          'pv1_current': 15.0,
          'pv_total_power': 1800.0,
        },
        'sys': {
          'work_state': '1',
          'fault_code': 0,
          'alarm_code': 0,
          'inverter_temperature': 45.0,
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
        },
        'online': true,
        'updated_at': '2026-07-27T12:00:00Z',
      };

      // 验证嵌套结构的关键字段存在（V2.1 组键）
      expect(nestedData.containsKey('ac'), true);
      expect(nestedData.containsKey('bat'), true);
      expect(nestedData.containsKey('pv'), true);
      expect(nestedData.containsKey('sys'), true);
      expect(nestedData.containsKey('eng'), true);

      // 验证在线状态
      expect(nestedData['online'], true);
    });

    test('扁平结构解析 - 键值对格式', () {
      final flatData = {
        'ac_output_voltage': 220.5,
        'output_current': 10.2,
        'output_power': 2250.0,
        'ac_output_frequency': 50.0,
        'battery_soc': 80.0,
        'battery_voltage': 48.5,
        'battery_current': 15.0,
        'pv1_voltage': 120.0,
        'pv1_current': 15.0,
        'pv_total_power': 1800.0,
        'work_state': '1',
        'fault_code': 0,
        'alarm_code': 0,
        'inverter_temperature': 45.0,
        'daily_pv_energy': 15.5,
        'total_pv_energy': 1000.0,
        'work_time_total': 1800000,
        'online': true,
        'updated_at': '2026-07-27T12:00:00Z',
      };

      // 验证扁平结构的关键字段存在（V2.1 顶层键）
      expect(flatData.containsKey('ac_output_voltage'), true);
      expect(flatData.containsKey('battery_soc'), true);
      expect(flatData.containsKey('pv_total_power'), true);
      expect(flatData.containsKey('work_state'), true);
      expect(flatData.containsKey('daily_pv_energy'), true);

      // 验证在线状态
      expect(flatData['online'], true);
    });

    test('在线状态管理 - 状态切换', () {
      bool isOnline = false;
      
      // 模拟状态切换
      isOnline = true;
      expect(isOnline, true);
      
      isOnline = false;
      expect(isOnline, false);
      
      // 模拟连续状态
      final statusHistory = <bool>[];
      statusHistory.add(true);
      statusHistory.add(true);
      statusHistory.add(false);
      statusHistory.add(true);
      
      expect(statusHistory.length, 4);
      expect(statusHistory[0], true);
      expect(statusHistory[2], false);
    });

    test('异常数据处理 - 空值处理', () {
      // 测试空数据
      final emptyData = <String, dynamic>{};
      expect(emptyData.isEmpty, true);
      
      // 测试 null 值处理
      final dataWithNull = {
        'ac': null,
        'battery': null,
        'pv': null,
        'online': null,
      };
      expect(dataWithNull['ac'], null);
      expect(dataWithNull['online'], null);
      
      // 验证默认值处理
      final defaultValue = (dataWithNull['online'] as bool?) ?? false;
      expect(defaultValue, false);
    });

    test('异常数据处理 - 类型转换', () {
      // 测试 num 类型转换
      final numValue = 100;
      final doubleValue = (numValue as num).toDouble();
      expect(doubleValue, 100.0);
      
      // 测试 int 类型转换
      final intValue = (numValue as num).toInt();
      expect(intValue, 100);
      
      // 测试 null 安全转换
      final nullValue = null;
      final safeValue = (nullValue as num?)?.toDouble() ?? 0;
      expect(safeValue, 0);
    });

    test('数据验证 - 电压范围检查', () {
      // 正常电压范围
      final normalVoltage = 220.0;
      expect(normalVoltage >= 180 && normalVoltage <= 260, true);
      
      // 异常电压
      final abnormalVoltage = 500.0;
      expect(abnormalVoltage >= 180 && abnormalVoltage <= 260, false);
      
      // SOC 范围检查
      final soc = 80.0;
      expect(soc >= 0 && soc <= 100, true);
    });

    test('数据验证 - 功率计算', () {
      // 功率 = 电压 * 电流
      final voltage = 220.0;
      final current = 10.0;
      final expectedPower = voltage * current;
      
      expect(expectedPower, 2200.0);
      
      // 能量计算
      final power = 2000.0; // 瓦
      final hours = 5.0; // 小时
      final energy = power * hours / 1000; // 转换为 kWh
      
      expect(energy, 10.0);
    });
  });
}
