import 'package:sqflite/sqflite.dart';

/// 本地缓存数据库：电站与设备快照（离线模式底座）
///
/// 在线时由上层 Bloc 写入快照，离网时 LocalModePage 读取渲染。
/// 两张表：stations / devices，字段对齐云端返回结构。
class LocalCacheDatabase {
  static LocalCacheDatabase? _instance;
  static Database? _db;

  LocalCacheDatabase._();

  factory LocalCacheDatabase() {
    _instance ??= LocalCacheDatabase._();
    return _instance!;
  }

  /// 获取数据库实例（懒初始化单例）
  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/csergy_local_cache.db';
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS stations (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL DEFAULT '',
            address TEXT DEFAULT '',
            capacity REAL DEFAULT 0,
            status INTEGER DEFAULT 0,
            image_url TEXT DEFAULT '',
            device_count INTEGER DEFAULT 0,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS devices (
            sn TEXT PRIMARY KEY,
            name TEXT NOT NULL DEFAULT '',
            model TEXT DEFAULT '',
            firmware_arm TEXT DEFAULT '',
            firmware_esp TEXT DEFAULT '',
            station_id TEXT DEFAULT '',
            status INTEGER DEFAULT 0,
            last_seen_at TEXT DEFAULT '',
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  // ============ 电站快照 ============

  /// 批量 upsert 电站快照
  Future<void> upsertStations(List<Map<String, dynamic>> stations) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();
    for (final s in stations) {
      batch.insert(
        'stations',
        {
          'id': s['id']?.toString() ?? '',
          'name': s['name']?.toString() ?? '',
          'address': s['address']?.toString() ?? '',
          'capacity': (s['capacity'] is num) ? (s['capacity'] as num).toDouble() : 0.0,
          'status': s['status'] ?? 0,
          'image_url': s['image_url']?.toString() ?? '',
          'device_count': s['device_count'] ?? 0,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 读取所有缓存电站
  Future<List<Map<String, dynamic>>> loadStations() async {
    final db = await database;
    return db.query('stations', orderBy: 'name ASC');
  }

  /// 清空电站缓存
  Future<void> clearStations() async {
    final db = await database;
    await db.delete('stations');
  }

  /// 删除单个电站快照及其下属设备快照
  /// （云端删除电站时联动调用，避免离网模式展示已删除的电站）
  Future<void> deleteStation(String stationId) async {
    final db = await database;
    await db.delete('stations', where: 'id = ?', whereArgs: [stationId]);
    await db.delete(
      'devices',
      where: 'station_id = ?',
      whereArgs: [stationId],
    );
  }

  // ============ 设备快照 ============

  /// 批量 upsert 设备快照
  Future<void> upsertDevices(List<Map<String, dynamic>> devices) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();
    for (final d in devices) {
      batch.insert(
        'devices',
        {
          'sn': d['sn']?.toString() ?? d['device_sn']?.toString() ?? '',
          'name': d['name']?.toString() ?? d['device_name']?.toString() ?? '',
          'model': d['model']?.toString() ?? d['device_model']?.toString() ?? '',
          'firmware_arm': d['firmware_arm']?.toString() ?? '',
          'firmware_esp': d['firmware_esp']?.toString() ?? '',
          'station_id': d['station_id']?.toString() ?? '',
          'status': d['status'] ?? 0,
          'last_seen_at': d['last_seen_at']?.toString() ?? '',
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 读取所有缓存设备
  Future<List<Map<String, dynamic>>> loadDevices() async {
    final db = await database;
    return db.query('devices', orderBy: 'name ASC');
  }

  /// 按电站 ID 读取缓存设备
  Future<List<Map<String, dynamic>>> loadDevicesByStation(String stationId) async {
    final db = await database;
    return db.query('devices', where: 'station_id = ?', whereArgs: [stationId]);
  }

  /// 清空设备缓存
  Future<void> clearDevices() async {
    final db = await database;
    await db.delete('devices');
  }

  /// 删除单个设备快照（解绑/删除设备时联动调用，
  /// 避免离网模式展示已解绑的设备）
  Future<void> deleteDevice(String sn) async {
    final db = await database;
    await db.delete('devices', where: 'sn = ?', whereArgs: [sn]);
  }

  /// 清空全部缓存
  Future<void> clearAll() async {
    await clearStations();
    await clearDevices();
  }

  /// 缓存统计：返回 {stations: N, devices: N}
  Future<Map<String, int>> getStats() async {
    final db = await database;
    final stationCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM stations'),
    ) ?? 0;
    final deviceCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM devices'),
    ) ?? 0;
    return {'stations': stationCount, 'devices': deviceCount};
  }
}
