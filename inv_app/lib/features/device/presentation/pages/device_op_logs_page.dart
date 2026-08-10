import 'package:flutter/material.dart';

import 'package:inv_app/core/services/offline/offline_log_sync_service.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 设备本地操作日志页（BLE 直连模式，设计文档 §3.5）
///
/// 按 SN 展示本地离线操作日志（pending/syncing/synced/failed 全状态），
/// 支持下拉刷新与手动立即同步。
class DeviceOpLogsPage extends StatefulWidget {
  final String sn;
  final OfflineOpLogStore? store;
  final OfflineLogSyncService? syncService;

  const DeviceOpLogsPage({
    super.key,
    required this.sn,
    this.store,
    this.syncService,
  });

  @override
  State<DeviceOpLogsPage> createState() => _DeviceOpLogsPageState();
}

class _DeviceOpLogsPageState extends State<DeviceOpLogsPage> {
  late final OfflineOpLogStore _store;
  late final OfflineLogSyncService _syncService;
  List<OfflineOpLog>? _logs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? getIt<OfflineOpLogStore>();
    _syncService = widget.syncService ?? getIt<OfflineLogSyncService>();
    _load();
  }

  Future<void> _load() async {
    final logs = await _store.listBySn(widget.sn);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  Future<void> _syncNow() async {
    final l10n = AppLocalizations.of(context)!;
    final pending = await _store.pendingCount();
    if (!mounted) return;
    if (pending == 0) {
      // 无待同步日志
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.opLogsEmpty)),
      );
      return;
    }
    // 失败已内部处理（指数退避重试，超 5 次标记 failed）
    await _syncService.syncNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.opLogSyncedToast)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.opLogs),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: l10n.opLogSyncNow,
            onPressed: _syncNow,
          ),
        ],
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final logs = _logs ?? const <OfflineOpLog>[];
    if (logs.isEmpty) {
      return Center(child: Text(l10n.opLogsEmpty));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: logs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) => _LogTile(log: logs[index]),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final OfflineOpLog log;

  const _LogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: _actionIcon(log.action),
      title: Text(l10n.opLogAction(log.action)),
      subtitle: Text(
        '${l10n.opLogChannel(log.channel)} · '
        '${l10n.opLogSyncStatus(log.syncStatus)} · '
        '${_formatTime(log.opTime)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _StatusChip(status: log.syncStatus),
    );
  }

  Icon _actionIcon(String action) {
    final icon = switch (action) {
      'ota' => Icons.system_update,
      'control' => Icons.touch_app,
      'set_param' => Icons.tune,
      'unbind' => Icons.link_off,
      _ => Icons.link,
    };
    return Icon(icon);
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (color, label) = switch (status) {
      'synced' => (Colors.green, l10n.opLogSyncStatus('synced')),
      'syncing' => (Colors.blue, l10n.opLogSyncStatus('syncing')),
      'failed' => (Colors.red, l10n.opLogSyncStatus('failed')),
      _ => (Colors.orange, l10n.opLogSyncStatus('pending')),
    };
    return Chip(
      label: Text(
        label,
        style: TextStyle(fontSize: 11, color: color),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// 本地时间格式化：yyyy-MM-dd HH:mm:ss
String _formatTime(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
