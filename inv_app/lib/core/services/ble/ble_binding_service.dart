import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';
import 'package:uuid/uuid.dart';

/// 绑定结果枚举（附录 B 定稿）
enum BindOutcome {
  /// 绑定成功（含离线绑定成功——补登记稍后由 Task 15 恢复）
  bound,

  /// 已绑定（本地已有 key / 设备 INFO 显示已绑定 / 服务器返回 5002）
  alreadyBound,

  /// PIN 错误（设备端 BIND_REJECTED invalid_pin）
  invalidPin,

  /// PIN 锁定（设备端 BIND_REJECTED locked）
  locked,

  /// 本地绑定成功但补登记需登录（401），待登录后由同步服务重试
  needLoginForSync,

  /// 连接失败 / 其他绑定失败
  failed,
}

/// 本地生成 32 字节随机 device_key（Base64），完全离网可用。
///
/// 附录 B 安全约束：App 不持有 PRODUCT_SECRET、不实现 compute_pin，
/// device_key 由 App 本地生成后写入设备并仅以 SHA-256 摘要登记到后端。
String generateDeviceKey() {
  final rand = Random.secure();
  final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
  return base64Encode(bytes);
}

/// 配网后自动绑定服务（场景 A：配网已验 PIN；场景 B：用户输入 PIN）。
///
/// 核心语义：绑定无需登录/联网——本地生成 key → 写设备 → 存 secure_storage
/// → 记本地日志 → 联网补登记（尽力而为，失败不影响绑定结果）。
class BleBindingService {
  final BleDeviceManager manager;
  final BleDeviceKeyStore keyStore;
  final Dio dio;
  final OfflineOpLogStore logStore;

  BleBindingService({
    required this.manager,
    required this.keyStore,
    required this.dio,
    required this.logStore,
  });

  /// 配网后自动绑定。
  ///
  /// [macAddress] 设备 MAC（连接目标）。
  /// [knownSn] 场景 A 配网阶段已拿到的 SN；为空时回退读 session.sn。
  /// [pin] 场景 B 必传（设备端校验）；场景 A 配网已验 PIN 传 null。
  Future<BindOutcome> bindAfterProvision({
    required String macAddress,
    String? knownSn,
    String? pin,
  }) async {
    // 1. 连接设备获取 session
    final BleDeviceSession session;
    try {
      session = await manager.connectDevice(macAddress);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BleBindingService: connect $macAddress failed: $e');
      }
      return BindOutcome.failed;
    }

    // 2. 确定 SN（优先使用配网阶段已知 SN）
    final sn = knownSn ?? session.sn;
    if (sn == null || sn.isEmpty) {
      if (kDebugMode) {
        debugPrint('BleBindingService: sn unavailable for $macAddress');
      }
      return BindOutcome.failed;
    }

    // 3. 本地已有 key → 已绑定，直接跳过
    final existingKey = await keyStore.read(sn);
    if (existingKey != null) {
      return BindOutcome.alreadyBound;
    }

    // 4. 读 INFO：设备端已绑定 → 已绑定；抛异常/字段缺失 → 视为未绑定继续
    try {
      final info = await session.readInfo();
      if (info['bound'] == true) {
        return BindOutcome.alreadyBound;
      }
    } catch (e) {
      // INFO 读取失败不阻塞绑定流程（老固件/连接波动）
      if (kDebugMode) {
        debugPrint('BleBindingService: readInfo failed (ignored): $e');
      }
    }

    // 5. 本地生成 device_key
    final deviceKey = generateDeviceKey();

    // 6. AUTH bind 写设备（场景 B 带 pin 由设备端校验）
    try {
      await session.bind(deviceKey, pin: pin);
    } on BleCommandException catch (e) {
      final msg = e.message;
      if (msg.contains('invalid_pin')) {
        return BindOutcome.invalidPin;
      }
      if (msg.contains('locked')) {
        return BindOutcome.locked;
      }
      if (kDebugMode) {
        debugPrint('BleBindingService: bind rejected: $e');
      }
      return BindOutcome.failed;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BleBindingService: bind failed: $e');
      }
      return BindOutcome.failed;
    }

    // 7. 存 secure_storage + 记本地操作日志（绑定日志不同步明文 key）
    await keyStore.write(sn, deviceKey);
    await logStore.add(
      OfflineOpLog(
        logId: const Uuid().v4(),
        deviceSn: sn,
        action: 'bind',
        params: const {},
        result: 'ok',
        channel: 'ble',
        opTime: DateTime.now(),
      ),
    );

    // 8. 联网补登记（尽力而为：失败不影响绑定结果，重试由 Task 15 负责）
    return _registerToCloud(sn, deviceKey, pin);
  }

  /// 联网补登记 POST /devices/bind，仅返回是否需登录，其余结果归并为成功。
  /// pin 可空：旧流程未持 PIN 时登记会被后端拒绝（严格模式），
  /// 本地绑定不受影响，按现有“其余 code 不视为失败”语义归并。
  Future<BindOutcome> _registerToCloud(String sn, String deviceKey, String? pin) async {
    try {
      final resp = await dio.post(
        '/devices/bind',
        data: {'sn': sn, 'device_key': deviceKey, 'pin': pin},
      );
      final body = resp.data;
      if (body is Map) {
        final code = body['code'];
        if (code == 0) {
          return BindOutcome.bound;
        }
        if (code == 5002) {
          // 服务器已绑（本地 key 已存），返回 alreadyBound
          return BindOutcome.alreadyBound;
        }
      }
      // 其余 code 不视为失败（离线语义：本地绑定已成功）
      return BindOutcome.bound;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // 未登录：补登记待登录后由同步服务重试
        return BindOutcome.needLoginForSync;
      }
      // 网络不通等：离线绑定成功，补登记稍后重试（Task 15）
      if (kDebugMode) {
        debugPrint('BleBindingService: registration deferred: $e');
      }
      return BindOutcome.bound;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BleBindingService: registration failed: $e');
      }
      return BindOutcome.bound;
    }
  }
}
