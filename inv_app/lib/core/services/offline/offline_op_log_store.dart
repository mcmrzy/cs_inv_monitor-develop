import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// 本地操作日志实体（设计文档 §3.5）
class OfflineOpLog {
  final String logId;
  final String deviceSn;
  final String action;
  final Map<String, dynamic> params;
  final String result;
  final String channel;
  final DateTime opTime;
  final String syncStatus; // pending/syncing/synced/failed
  final int syncAttempts;

  const OfflineOpLog({
    required this.logId,
    required this.deviceSn,
    required this.action,
    this.params = const {},
    this.result = 'ok',
    this.channel = 'ble',
    required this.opTime,
    this.syncStatus = 'pending',
    this.syncAttempts = 0,
  });

  Map<String, dynamic> toJson() => {
        'log_id': logId,
        'device_sn': deviceSn,
        'action': action,
        'params': params,
        'result': result,
        'channel': channel,
        'op_time': opTime.toUtc().toIso8601String(),
      };

  factory OfflineOpLog.fromMap(Map<String, dynamic> map) => OfflineOpLog(
        logId: map['log_id'] as String,
        deviceSn: map['device_sn'] as String,
        action: map['action'] as String,
        params: (jsonDecode(map['params'] as String? ?? '{}') as Map)
            .cast<String, dynamic>(),
        result: (map['result'] as String?) ?? 'ok',
        channel: (map['channel'] as String?) ?? 'ble',
        opTime: DateTime.parse(map['op_time'] as String),
        syncStatus: (map['sync_status'] as String?) ?? 'pending',
        syncAttempts: (map['sync_attempts'] as int?) ?? 0,
      );
}

/// 本地操作日志存储（sqflite，表 local_op_logs）
///
/// 容量上限：500 条 / 30 天（仅清理已同步日志，设计文档 §3.5）。
class OfflineOpLogStore {
  final Future<Database> Function() _openDb;
  Database? _db;

  OfflineOpLogStore({Future<Database> Function()? openDb})
      : _openDb = openDb ?? _defaultOpen;

  static Future<Database> _defaultOpen() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      '$dir/local_op_logs.db',
      version: 1,
      onCreate: onCreate,
    );
  }

  /// 建表回调（测试与默认打开共用）
  static Future<void> onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE local_op_logs (
        log_id TEXT PRIMARY KEY,
        device_sn TEXT NOT NULL,
        action TEXT NOT NULL,
        params TEXT NOT NULL DEFAULT '{}',
        result TEXT NOT NULL DEFAULT 'ok',
        channel TEXT NOT NULL DEFAULT 'ble',
        op_time TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        sync_attempts INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_op_logs_status ON local_op_logs(sync_status, op_time)',
    );
  }

  Future<Database> get _database async => _db ??= await _openDb();

  Future<void> add(OfflineOpLog log) async {
    final db = await _database;
    await db.insert('local_op_logs', {
      'log_id': log.logId,
      'device_sn': log.deviceSn,
      'action': log.action,
      'params': jsonEncode(log.params),
      'result': log.result,
      'channel': log.channel,
      'op_time': log.opTime.toUtc().toIso8601String(),
      'sync_status': log.syncStatus,
      'sync_attempts': log.syncAttempts,
    });
    await prune();
  }

  /// 待同步日志（按时间正序，[limit] 条）。
  ///
  /// 仅返回 pending 状态；failed 为终止状态（不再自动重试），
  /// attempts 已达 5 的日志同样不再返回。
  Future<List<OfflineOpLog>> pending({int limit = 50}) async {
    final db = await _database;
    final rows = await db.query(
      'local_op_logs',
      where: "sync_status = 'pending' AND sync_attempts < 5",
      orderBy: 'op_time ASC',
      limit: limit,
    );
    return rows.map(OfflineOpLog.fromMap).toList(growable: false);
  }

  /// 某设备全部操作日志（按时间倒序，最新在前，[limit] 条）。
  ///
  /// 不过滤 sync_status，页面需展示 pending/syncing/synced/failed 全状态。
  Future<List<OfflineOpLog>> listBySn(String sn, {int limit = 200}) async {
    final db = await _database;
    final rows = await db.query(
      'local_op_logs',
      where: 'device_sn = ?',
      whereArgs: [sn],
      orderBy: 'op_time DESC',
      limit: limit,
    );
    return rows.map(OfflineOpLog.fromMap).toList(growable: false);
  }

  Future<int> pendingCount() async {
    final db = await _database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM local_op_logs WHERE sync_status = 'pending' AND sync_attempts < 5",
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> countAll() async {
    final db = await _database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM local_op_logs');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> countByStatus(String status) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM local_op_logs WHERE sync_status = ?',
      [status],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> markSyncing(List<String> logIds) async {
    await _updateStatus(logIds, 'syncing');
  }

  /// 启动时把僵死的 syncing 日志恢复为 pending：
  /// markSyncing 后若进程被杀/ack 丢失，日志会停在 syncing，
  /// 而 pending() 只查 pending，不恢复则永久不可重试
  Future<void> resetSyncingToPending() async {
    final db = await _database;
    await db.rawUpdate(
      "UPDATE local_op_logs SET sync_status = 'pending' "
      "WHERE sync_status = 'syncing'",
    );
  }

  Future<void> markSynced(List<String> logIds) async {
    await _updateStatus(logIds, 'synced');
  }

  Future<void> markFailed(List<String> logIds) async {
    await _updateStatus(logIds, 'failed');
  }

  /// 失败重试计数 +1（状态回 pending，等待下一次退避重试）
  Future<void> bumpAttempts(List<String> logIds) async {
    if (logIds.isEmpty) return;
    final db = await _database;
    await db.rawUpdate(
      'UPDATE local_op_logs SET sync_attempts = sync_attempts + 1, '
      "sync_status = 'pending' WHERE log_id IN (${List.filled(logIds.length, '?').join(',')})",
      logIds,
    );
  }

  Future<void> _updateStatus(List<String> logIds, String status) async {
    if (logIds.isEmpty) return;
    final db = await _database;
    await db.rawUpdate(
      'UPDATE local_op_logs SET sync_status = ? WHERE log_id IN '
      '(${List.filled(logIds.length, '?').join(',')})',
      [status, ...logIds],
    );
  }

  /// 容量清理：删除已同步且（超过 30 天 或 超出最近 500 条）的日志
  Future<void> prune() async {
    final db = await _database;
    await db.rawDelete('''
      DELETE FROM local_op_logs
      WHERE sync_status = 'synced' AND (
        julianday(op_time) < julianday('now', '-30 days')
        OR rowid NOT IN (
          SELECT rowid FROM local_op_logs
          WHERE sync_status = 'synced'
          ORDER BY op_time DESC LIMIT 500
        )
      )
    ''');
  }

  /// 清空全部操作日志（登出时调用，隐私：不残留上一账号的离线操作记录）
  Future<void> clearAll() async {
    final db = await _database;
    await db.delete('local_op_logs');
  }
}
