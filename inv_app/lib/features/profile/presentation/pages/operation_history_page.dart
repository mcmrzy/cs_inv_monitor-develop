import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dio/dio.dart';

import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/pagination_bar.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 用户操作历史页（需求 15）
///
/// 数据源：后端聚合端点 GET /op-logs（当前用户维度），
/// 统一聚合 user_operation_logs + device_cmd_logs + device_upgrades，
/// 按时间倒序分页返回统一结构（类型/操作/设备/结果/时间）。
class OperationHistoryPage extends StatefulWidget {
  const OperationHistoryPage({super.key});

  @override
  State<OperationHistoryPage> createState() => _OperationHistoryPageState();
}

class _OperationHistoryPageState extends State<OperationHistoryPage> {
  List<OpLogItem> _items = const [];
  int _page = 1;
  int _total = 0;
  final int _pageSize = 20;
  bool _loading = true;
  String? _error;

  int get _totalPages => (_total / _pageSize).ceil();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = getIt<Dio>();
      final response = await dio.get(
        '/op-logs',
        queryParameters: {'page': _page, 'page_size': _pageSize},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        final payload = (data['data'] as Map<String, dynamic>?) ?? {};
        final items = (payload['items'] as List? ?? const [])
            .map((e) => OpLogItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (!mounted) return;
        setState(() {
          _items = items;
          _total = (payload['total'] as num?)?.toInt() ?? 0;
          _loading = false;
        });
      } else {
        throw Exception(data is Map ? data['message'] : 'bad response');
      }
    } catch (e) {
      debugPrint('[OperationHistoryPage] load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _onPageChanged(int page) {
    _page = page;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.operationHistory)),
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.str('op_log_load_failed'),
              style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
            ),
            SizedBox(height: 12.h),
            OutlinedButton(
              onPressed: _load,
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          l10n.opLogEmpty,
          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _OpLogTile(log: _items[index]),
            ),
          ),
          PaginationBar(
            currentPage: _page,
            totalPages: _totalPages,
            onPageChanged: _onPageChanged,
          ),
        ],
      ),
    );
  }
}

/// 聚合端点返回的单项结构（后端 user_op_log_handler.go 统一五字段）
class OpLogItem {
  final String source; // operation / command / ota
  final String title;
  final String deviceSn;
  final String result; // success / failed / pending ...
  final DateTime opTime;

  const OpLogItem({
    required this.source,
    required this.title,
    required this.deviceSn,
    required this.result,
    required this.opTime,
  });

  factory OpLogItem.fromJson(Map<String, dynamic> json) {
    return OpLogItem(
      source: json['source'] as String? ?? 'unknown',
      title: json['title'] as String? ?? '',
      deviceSn: json['device_sn'] as String? ?? '',
      result: json['result'] as String? ?? 'pending',
      opTime: DateTime.tryParse(json['op_time'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class _OpLogTile extends StatelessWidget {
  final OpLogItem log;

  const _OpLogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: Icon(
        _sourceIcon(log.source),
        size: 22.sp,
        color: _sourceColor(log.source),
      ),
      title: Text(
        log.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14.sp,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${_sourceLabel(l10n, log.source)}'
        '${log.deviceSn.isEmpty ? '' : ' · ${log.deviceSn}'}'
        ' · ${_formatTime(log.opTime)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
      ),
      trailing: _ResultChip(result: log.result),
    );
  }

  IconData _sourceIcon(String source) {
    return switch (source) {
      'ota' => Icons.system_update,
      'command' => Icons.terminal_rounded,
      'operation' => Icons.touch_app,
      _ => Icons.history,
    };
  }

  Color _sourceColor(String source) {
    return switch (source) {
      'ota' => AppColors.purple,
      'command' => AppColors.blue,
      'operation' => AppColors.teal,
      _ => AppColors.textSecondary,
    };
  }

  String _sourceLabel(AppLocalizations l10n, String source) {
    return switch (source) {
      'ota' => l10n.opLogTypeOta,
      'command' => l10n.opLogTypeCommand,
      'operation' => l10n.opLogTypeOperation,
      _ => l10n.opLogTypeUnknown,
    };
  }
}

class _ResultChip extends StatelessWidget {
  final String result;

  const _ResultChip({required this.result});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (result) {
      'success' => (AppColors.successLight, 'OK'),
      'failed' => (AppColors.errorLight, 'FAIL'),
      'pending' => (AppColors.warning, 'PENDING'),
      'downloading' || 'upgrading' => (AppColors.primary, result.toUpperCase()),
      _ => (AppColors.textHint, result.toUpperCase()),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.sp,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// 本地时间格式化：yyyy-MM-dd HH:mm
String _formatTime(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}
