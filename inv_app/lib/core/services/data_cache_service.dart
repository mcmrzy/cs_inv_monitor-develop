import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 通用数据缓存服务，用于在无网络时展示缓存数据。
/// 数据以 JSON 字符串形式存储在 SharedPreferences 中，每个 key 对应一组数据。
class DataCacheService {
  final SharedPreferences _prefs;
  static const String _prefix = 'data_cache_';
  static const String _tsPrefix = 'data_cache_ts_';

  /// 缓存有效期（默认 24 小时）
  static const Duration defaultTtl = Duration(hours: 24);

  DataCacheService(this._prefs);

  /// 写入缓存数据
  Future<void> save(String key, dynamic data) async {
    final jsonStr = jsonEncode(data);
    await _prefs.setString('$_prefix$key', jsonStr);
    await _prefs.setInt('$_tsPrefix$key', DateTime.now().millisecondsSinceEpoch);
  }

  /// 读取缓存数据，超过 [ttl] 返回 null
  dynamic load(String key, {Duration ttl = defaultTtl}) {
    final jsonStr = _prefs.getString('$_prefix$key');
    if (jsonStr == null || jsonStr.isEmpty) return null;

    final ts = _prefs.getInt('$_tsPrefix$key') ?? 0;
    if (ts > 0) {
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > ttl.inMilliseconds) return null;
    }

    try {
      return jsonDecode(jsonStr);
    } catch (_) {
      return null;
    }
  }

  /// 读取缓存数据（忽略过期）
  dynamic loadOrNull(String key) {
    final jsonStr = _prefs.getString('$_prefix$key');
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      return jsonDecode(jsonStr);
    } catch (_) {
      return null;
    }
  }

  /// 获取缓存的时间戳（毫秒），0 表示无缓存
  int getTimestamp(String key) {
    return _prefs.getInt('$_tsPrefix$key') ?? 0;
  }

  /// 删除指定缓存
  Future<void> remove(String key) async {
    await _prefs.remove('$_prefix$key');
    await _prefs.remove('$_tsPrefix$key');
  }

  /// 清除所有数据缓存
  Future<void> clearAll() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
    final tsKeys = _prefs.getKeys().where((k) => k.startsWith(_tsPrefix)).toList();
    for (final key in tsKeys) {
      await _prefs.remove(key);
    }
  }

  // ── 常用缓存 key ──

  static const String stationSummary = 'station_summary';
  static const String alarmList = 'alarm_list';
  static const String deviceList = 'device_list';

  static String stationDetail(int stationId) => 'station_detail_$stationId';
  static String deviceDetail(String sn) => 'device_detail_$sn';
  static String stationDevices(int stationId) => 'station_devices_$stationId';
}
