// 设备云端调试页
//
// 结构：说明文案 + 网络中断横幅 + 会话状态卡（状态徽标/倒计时/开始/停止）
//       + 曲线区（窗口/选线 Chip + 上下两张同步折线图：电压 V / 电流 A）
//
// 数据：DeviceDebugApi（getIt 注入 Dio 实例，参考 device_control_page 的直连风格）
// 轮询：会话与采样各每 10 秒；采样带 after=next_cursor 增量拉取，本地点上限 400
// 生命周期：WidgetsBindingObserver —— resumed 恢复轮询并按游标补点；
//           inactive/paused 仅暂停轮询（不停止设备端调试，会话由服务端超时管理）

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/utils/api_response.dart';
import 'package:inv_app/features/device/data/device_debug_api.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:uuid/uuid.dart';

class DeviceDebugPage extends StatefulWidget {
  final String sn;

  /// 可注入的 API（测试 mock）；缺省经 getIt 注入的 Dio 实例构造
  final DeviceDebugApi? api;

  const DeviceDebugPage({super.key, required this.sn, this.api});

  @override
  State<DeviceDebugPage> createState() => _DeviceDebugPageState();
}

class _DeviceDebugPageState extends State<DeviceDebugPage>
    with WidgetsBindingObserver {
  late final DeviceDebugApi _api = widget.api ?? DeviceDebugApi(getIt<Dio>());

  static const _pollInterval = Duration(seconds: 10);
  static const _maxLocalSamples = 400;

  /// 调试曲线指标分组：每组一条电压 + 一条电流
  /// （MPPT 电流即 Buck 电流，见 debug_desc_metrics 文案）
  static const _metricGroups = [
    (label: 'MPPT/PV1', voltageKey: 'pv1_voltage', currentKey: 'buck1_current',
        voltageColor: Color(0xFFF59E0B), currentColor: Color(0xFFB45309)),
    (label: 'MPPT/PV2', voltageKey: 'pv2_voltage', currentKey: 'buck2_current',
        voltageColor: Color(0xFF8B5CF6), currentColor: Color(0xFF6D28D9)),
    (label: 'battery', voltageKey: 'battery_voltage', currentKey: 'battery_current',
        voltageColor: Color(0xFF14B8A6), currentColor: Color(0xFF047857)),
    (label: 'inverter', voltageKey: 'dc_bus_voltage', currentKey: 'inv_current',
        voltageColor: Color(0xFF3B82F6), currentColor: Color(0xFF1D4ED8)),
    (label: 'load', voltageKey: 'ac_voltage', currentKey: 'ac_current',
        voltageColor: Color(0xFFEC4899), currentColor: Color(0xFFBE185D)),
  ];

  /// 开始时长选项（秒）与 l10n key
  static const _durationOptions = [
    (1800, 'debug_duration_30m'),
    (3600, 'debug_duration_1h'),
    (7200, 'debug_duration_2h'),
    (14400, 'debug_duration_4h'),
  ];

  /// 采样时间窗选项（分钟）与 l10n key
  static const _windowOptions = [
    (15, 'debug_window_15m'),
    (30, 'debug_window_30m'),
    (60, 'debug_window_60m'),
  ];

  // 会话状态
  DeviceDebugSession? _session;
  bool _deviceOnline = false;
  bool _supported = true;
  bool _initialLoading = true;

  /// 轮询失败 → 顶部中断横幅（保留已见曲线，不打断页面）
  bool _networkError = false;

  /// 开始/停止请求中（按钮禁用）
  bool _starting = false;
  bool _stopping = false;

  /// 开始/停止失败的内联提示（成功与否直接由会话状态徽标反映）
  String? _actionError;

  /// 开始调试时长（秒），默认 1 小时
  int _durationSeconds = 3600;

  /// 采样时间窗（分钟）
  int _windowMinutes = 15;

  /// 增量拉取游标（不透明字符串，空 = 从头拉）
  String _nextCursor = '';
  List<DeviceDebugSample> _samples = [];

  /// 曲线选线：选中的指标分组下标，默认电池(2) + 负载(4)
  final Set<int> _selectedGroups = {2, 4};

  Timer? _pollTimer;
  bool _pollInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回前台：刷新会话 + 按游标补齐离场期间的采样点，并恢复轮询
      _refreshSessionAndSamples();
      _startPolling();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // 仅暂停 App 侧轮询；设备调试会话仍在服务端继续，不做停止操作
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  数据拉取
  // ─────────────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollTick());
  }

  Future<void> _pollTick() async {
    if (_pollInFlight) return; // 上一次请求未返回时不叠加
    _pollInFlight = true;
    try {
      await _refreshSessionAndSamples();
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _refreshSessionAndSamples() async {
    await _refreshSession();
    await _fetchSamples(incremental: true);
  }

  Future<void> _refreshAll() async {
    await _refreshSession();
    await _fetchSamples(incremental: false);
  }

  Future<void> _refreshSession() async {
    try {
      final info = await _api.getDebugSession(widget.sn);
      if (!mounted) return;
      setState(() {
        _session = info.session;
        _deviceOnline = info.deviceOnline;
        _supported = info.supported;
        _networkError = false;
        _initialLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _networkError = true;
        _initialLoading = false;
      });
    }
  }

  /// 拉取采样。incremental=true 时带 after 游标增量补点；
  /// false 为全量重拉（时间窗切换/新会话），跟随游标翻页直到耗尽。
  Future<void> _fetchSamples({required bool incremental}) async {
    try {
      if (incremental) {
        final sessionId = _session?.id;
        if (sessionId == null || sessionId.isEmpty) return;
        final page = await _api.getDebugSamples(
          widget.sn,
          sessionId: sessionId,
          windowMinutes: _windowMinutes,
          after: _nextCursor.isNotEmpty ? _nextCursor : null,
        );
        if (!mounted) return;
        setState(() {
          if (page.items.isNotEmpty) {
            _samples = _mergeSamples(_samples, page.items);
          }
          _nextCursor = page.nextCursor;
          if (page.session != null) _session = page.session;
          _networkError = false;
        });
        return;
      }

      final sessionId = _session?.id;
      final collected = <DeviceDebugSample>[];
      String cursor = '';
      var pages = 0;
      DeviceDebugSamplesPage page;
      do {
        page = await _api.getDebugSamples(
          widget.sn,
          sessionId: (sessionId != null && sessionId.isNotEmpty)
              ? sessionId
              : null,
          windowMinutes: _windowMinutes,
          after: cursor,
        );
        collected.addAll(page.items);
        cursor = page.nextCursor;
        pages++;
      } while (cursor.isNotEmpty && page.items.isNotEmpty && pages < 10);
      if (!mounted) return;
      setState(() {
        _samples = _mergeSamples(const [], collected);
        _nextCursor = cursor;
        if (page.session != null) _session = page.session;
        _networkError = false;
      });
    } catch (_) {
      // 网络失败：保留已见曲线，仅提示中断，不打断页面
      if (!mounted) return;
      setState(() => _networkError = true);
    }
  }

  /// 合并 + 按 time 升序 + 裁剪到本地点上限（裁旧）
  List<DeviceDebugSample> _mergeSamples(
    List<DeviceDebugSample> existing,
    List<DeviceDebugSample> incoming,
  ) {
    final merged = [...existing, ...incoming]
      ..sort((a, b) => a.time.compareTo(b.time));
    if (merged.length <= _maxLocalSamples) return merged;
    return merged.sublist(merged.length - _maxLocalSamples);
  }

  void _onWindowChanged(int minutes) {
    if (minutes == _windowMinutes) return;
    setState(() => _windowMinutes = minutes);
    // 时间窗切换：全量重拉
    _fetchSamples(incremental: false);
  }

  // ─────────────────────────────────────────────────────────────────────
  //  开始 / 停止
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _startDebug() async {
    if (_starting || _stopping) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _starting = true;
      _actionError = null;
    });
    try {
      final result = await _api.startDebugSession(
        widget.sn,
        durationSeconds: _durationSeconds,
        requestId: const Uuid().v4(),
      );
      if (!mounted) return;
      setState(() {
        _starting = false;
        _session = result.session;
        if (result.conflict) _actionError = l10n.str('debug_conflict');
      });
      // 新会话：全量重拉采样
      await _fetchSamples(incremental: false);
    } on ApiBusinessException catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _actionError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _actionError = l10n.str('debug_start_failed');
      });
    }
  }

  Future<void> _stopDebug() async {
    final session = _session;
    if (session == null || _starting || _stopping) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _stopping = true;
      _actionError = null;
    });
    try {
      final stopped = await _api.stopDebugSession(widget.sn, session.id);
      if (!mounted) return;
      setState(() {
        _stopping = false;
        if (stopped != null) _session = stopped;
      });
      await _fetchSamples(incremental: false);
    } on ApiBusinessException catch (e) {
      if (!mounted) return;
      setState(() {
        _stopping = false;
        _actionError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stopping = false;
        _actionError = l10n.str('debug_stop_failed');
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surfaceHover(context),
      appBar: AppBar(
        title: Text(
          l10n.str('device_debug'),
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.sp),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
      ),
      body: _initialLoading
          // 静态占位（不用转圈动画，避免测试 pumpAndSettle 不收敛）
          ? Center(
              child: Text(
                l10n.str('loading'),
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColor.textHint(context),
                ),
              ),
            )
          : SafeArea(
              child: ListView(
                padding: EdgeInsets.all(16.w),
                children: [
                  _buildDescription(l10n),
                  if (_networkError) ...[
                    SizedBox(height: 12.h),
                    _buildNetworkBanner(l10n),
                  ],
                  SizedBox(height: 12.h),
                  _buildSessionCard(l10n),
                  SizedBox(height: 12.h),
                  _buildChartsSection(l10n),
                  SizedBox(height: 16.h),
                ],
              ),
            ),
    );
  }

  /// 顶部说明：云端调试 vs 本地直连、MPPT 电流为 Buck 电流等测点说明
  Widget _buildDescription(AppLocalizations l10n) {
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.all(12.w),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_outlined,
                size: 16.sp,
                color: AppColors.info,
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  l10n.str('debug_desc_cloud'),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColor.textSecondary(context),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.show_chart,
                size: 16.sp,
                color: AppColors.info,
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  l10n.str('debug_desc_metrics'),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColor.textSecondary(context),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkBanner(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 18.sp, color: AppColors.warning),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              l10n.str('debug_network_interrupted'),
              style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  会话状态卡
  // ─────────────────────────────────────────────────────────────────────

  (Color, String) _statusPresentation(AppLocalizations l10n) {
    final session = _session;
    if (session == null) {
      return (AppColors.offline, l10n.str('debug_status_not_started'));
    }
    switch (session.status) {
      case 'starting':
        return (AppColors.warning, l10n.str('debug_status_starting'));
      case 'active':
        return (AppColors.success, l10n.str('debug_status_active'));
      case 'stopping':
        return (AppColors.warning, l10n.str('debug_status_stopping'));
      case 'stopped':
        return (AppColors.offline, l10n.str('debug_status_stopped'));
      case 'expired':
        return (AppColors.offline, l10n.str('debug_status_expired'));
      case 'interrupted':
        return (AppColors.orange, l10n.str('debug_status_interrupted'));
      case 'failed':
        return (AppColors.error, l10n.str('debug_status_failed'));
      default:
        return (AppColors.offline, session.status);
    }
  }

  DateTime? get _latestSampleTime {
    final lastAt = _session?.lastSampleAt;
    if (lastAt != null) return lastAt.toLocal();
    if (_samples.isNotEmpty) return _samples.last.time.toLocal();
    return null;
  }

  String _formatCountdown(Duration d) {
    if (d.isNegative) return '00:00:00';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(d.inHours)}:${p(d.inMinutes % 60)}:${p(d.inSeconds % 60)}';
  }

  Widget _buildSessionCard(AppLocalizations l10n) {
    final session = _session;
    final live = session != null && !session.isTerminal;
    final canStart =
        !_starting && !_stopping && _deviceOnline && _supported;

    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态徽标行
          Row(
            children: [
              _buildStatusBadge(l10n),
              const Spacer(),
              if (!_deviceOnline)
                Icon(
                  Icons.cloud_off_rounded,
                  size: 18.sp,
                  color: AppColors.offline,
                ),
            ],
          ),

          // 设备离线提示
          if (!_deviceOnline) ...[
            SizedBox(height: 10.h),
            Text(
              l10n.str('debug_device_offline'),
              style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
            ),
          ],

          // 剩余时长倒计时
          if (live && session.expiresAt != null) ...[
            SizedBox(height: 12.h),
            _infoRow(
              l10n.str('debug_remaining'),
              _formatCountdown(session.expiresAt!.difference(DateTime.now())),
            ),
          ],

          // 最新样本时间
          if (_latestSampleTime != null) ...[
            SizedBox(height: 8.h),
            _infoRow(
              l10n.str('debug_latest_sample'),
              DateFormat('HH:mm:ss').format(_latestSampleTime!),
            ),
          ],

          // 失败原因
          if (session != null &&
              (session.failureReason?.isNotEmpty ?? false)) ...[
            SizedBox(height: 8.h),
            _infoRow(l10n.str('debug_failure_reason'), session.failureReason!),
          ],

          // 不支持提示
          if (!_supported) ...[
            SizedBox(height: 12.h),
            Text(
              l10n.str('debug_not_supported'),
              style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
            ),
          ],

          // 开始/停止失败提示
          if (_actionError != null) ...[
            SizedBox(height: 12.h),
            Text(
              _actionError!,
              style: TextStyle(fontSize: 12.sp, color: AppColors.error),
            ),
          ],

          SizedBox(height: 12.h),

          if (live)
            // 停止按钮（请求中禁用）
            FilledButton.icon(
              onPressed: _stopping || _starting ? null : _stopDebug,
              icon: _stopping
                  ? SizedBox(
                      width: 16.w,
                      height: 16.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.stop_rounded),
              label: Text(l10n.str('debug_stop')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.error.withValues(alpha: 0.3),
                minimumSize: Size(double.infinity, 44.h),
              ),
            )
          else ...[
            // 时长选择
            Text(
              l10n.str('debug_duration_label'),
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColor.textSecondary(context),
              ),
            ),
            SizedBox(height: 8.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 8.w,
              children: [
                for (final (seconds, key) in _durationOptions)
                  ChoiceChip(
                    label: Text(
                      l10n.str(key),
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: _durationSeconds == seconds
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    selected: _durationSeconds == seconds,
                    selectedColor: AppColors.primary.withValues(alpha: 0.12),
                    checkmarkColor: AppColors.primary,
                    side: BorderSide(
                      color: _durationSeconds == seconds
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColor.divider(context),
                    ),
                    onSelected: _starting
                        ? null
                        : (_) => setState(() => _durationSeconds = seconds),
                  ),
              ],
            ),
            SizedBox(height: 12.h),
            // 开始按钮（请求中/离线/不支持时禁用）
            FilledButton.icon(
              onPressed: canStart ? _startDebug : null,
              icon: _starting
                  ? SizedBox(
                      width: 16.w,
                      height: 16.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(l10n.str('debug_start')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.3),
                minimumSize: Size(double.infinity, 44.h),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(AppLocalizations l10n) {
    final (color, text) = _statusPresentation(l10n);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8.w,
            height: 8.w,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 6.w),
          Text(
            text,
            style: TextStyle(
              fontSize: 13.sp,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            color: AppColor.textSecondary(context),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.sp,
            color: AppColor.textPrimary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  曲线区
  // ─────────────────────────────────────────────────────────────────────

  /// 某一测点 key 在本地样本上的曲线；null 值以 nullSpot 断线
  List<FlSpot> _spotsForKey(String key) {
    final spots = <FlSpot>[];
    for (final sample in _samples) {
      final value = sample.metrics.valueFor(key);
      final x = sample.time.toLocal().millisecondsSinceEpoch.toDouble();
      if (value == null) {
        // 断线：插入 nullSpot（跳过开头/连续断点，裁掉尾部断点）
        if (spots.isEmpty || spots.last.x.isNaN) continue;
        spots.add(FlSpot.nullSpot);
      } else {
        spots.add(FlSpot(x, value));
      }
    }
    if (spots.isNotEmpty && spots.last.x.isNaN) {
      spots.removeLast();
    }
    return spots;
  }

  List<({String label, List<FlSpot> spots, Color color})> _buildSeries({
    required bool voltage,
  }) {
    final result = <({String label, List<FlSpot> spots, Color color})>[];
    final indices = _selectedGroups.toList()..sort();
    for (final i in indices) {
      if (i < 0 || i >= _metricGroups.length) continue;
      final g = _metricGroups[i];
      result.add(
        (
          label: g.label,
          spots: _spotsForKey(voltage ? g.voltageKey : g.currentKey),
          color: voltage ? g.voltageColor : g.currentColor,
        ),
      );
    }
    return result;
  }

  /// 全局 x 范围（两张图共享）；单点/同值时左右各扩 30 秒
  (double, double) _xRange(List<List<FlSpot>> allSeries) {
    double? minX;
    double? maxX;
    for (final spots in allSeries) {
      for (final s in spots) {
        if (s.x.isNaN) continue;
        if (minX == null || s.x < minX) minX = s.x;
        if (maxX == null || s.x > maxX) maxX = s.x;
      }
    }
    if (minX == null || maxX == null) {
      final now = DateTime.now().millisecondsSinceEpoch.toDouble();
      return (now - 15 * 60000, now);
    }
    if (minX == maxX) {
      minX -= 30000;
      maxX += 30000;
    }
    return (minX, maxX);
  }

  /// y 范围；单值 ±1 扩区间，上下各加 10% padding；电压下限压到 0
  (double, double) _yRange(
    List<List<FlSpot>> allSeries, {
    required bool clampZero,
  }) {
    double? minY;
    double? maxY;
    for (final spots in allSeries) {
      for (final s in spots) {
        if (s.y.isNaN) continue;
        if (minY == null || s.y < minY) minY = s.y;
        if (maxY == null || s.y > maxY) maxY = s.y;
      }
    }
    if (minY == null || maxY == null) return (0, 1);
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    final padding = (maxY - minY) * 0.1;
    minY -= padding;
    maxY += padding;
    if (clampZero && minY < 0) minY = 0;
    return (minY, maxY);
  }

  Widget _buildChartsSection(AppLocalizations l10n) {
    // 窗口与选线 Chip
    final chips = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8.w,
          runSpacing: 8.w,
          children: [
            for (final (minutes, key) in _windowOptions)
              FilterChip(
                label: Text(
                  l10n.str(key),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: _windowMinutes == minutes
                        ? AppColors.primary
                        : AppColor.textSecondary(context),
                    fontWeight: _windowMinutes == minutes
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                selected: _windowMinutes == minutes,
                selectedColor: AppColors.primary.withValues(alpha: 0.12),
                checkmarkColor: AppColors.primary,
                side: BorderSide(
                  color: _windowMinutes == minutes
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : AppColor.divider(context),
                ),
                onSelected: (_) => _onWindowChanged(minutes),
              ),
          ],
        ),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.w,
          children: [
            for (var i = 0; i < _metricGroups.length; i++)
              _buildGroupChip(l10n, i),
          ],
        ),
      ],
    );

    if (_samples.isEmpty) {
      return Column(
        children: [
          chips,
          SizedBox(height: 12.h),
          Container(
            width: double.infinity,
            decoration: AppColor.card(context),
            padding: EdgeInsets.symmetric(vertical: 40.h),
            alignment: Alignment.center,
            child: Text(
              l10n.str('debug_no_samples'),
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColor.textHint(context),
              ),
            ),
          ),
        ],
      );
    }

    final voltageSeries = _buildSeries(voltage: true);
    final currentSeries = _buildSeries(voltage: false);
    final allSpots = [
      ...voltageSeries.map((s) => s.spots),
      ...currentSeries.map((s) => s.spots),
    ];
    final (minX, maxX) = _xRange(allSpots);
    final (vMin, vMax) =
        _yRange(voltageSeries.map((s) => s.spots).toList(), clampZero: true);
    final (cMin, cMax) =
        _yRange(currentSeries.map((s) => s.spots).toList(), clampZero: false);

    return Column(
      children: [
        chips,
        SizedBox(height: 12.h),
        _buildChartCard(
          title: l10n.str('debug_voltage_chart'),
          series: voltageSeries,
          minX: minX,
          maxX: maxX,
          minY: vMin,
          maxY: vMax,
          showTimeAxis: false, // 时间轴只在下图展示，两图共享同一 x 范围
        ),
        SizedBox(height: 12.h),
        _buildChartCard(
          title: l10n.str('debug_current_chart'),
          series: currentSeries,
          minX: minX,
          maxX: maxX,
          minY: cMin,
          maxY: cMax,
          showTimeAxis: true,
        ),
      ],
    );
  }

  Widget _buildGroupChip(AppLocalizations l10n, int index) {
    final group = _metricGroups[index];
    final label = switch (group.label) {
      'battery' => l10n.str('debug_group_battery'),
      'inverter' => l10n.str('debug_group_inverter'),
      'load' => l10n.str('debug_group_load'),
      _ => group.label, // MPPT/PV1、MPPT/PV2 为技术术语不翻译
    };
    final selected = _selectedGroups.contains(index);
    final color = group.voltageColor;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.sp,
          color: selected ? color : AppColor.textSecondary(context),
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: selected,
      selectedColor: color.withValues(alpha: 0.15),
      checkmarkColor: color,
      side: BorderSide(
        color:
            selected ? color.withValues(alpha: 0.4) : AppColor.divider(context),
      ),
      onSelected: (sel) {
        setState(() {
          if (sel) {
            _selectedGroups.add(index);
          } else {
            _selectedGroups.remove(index);
          }
        });
      },
    );
  }

  Widget _buildChartCard({
    required String title,
    required List<({String label, List<FlSpot> spots, Color color})> series,
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
    required bool showTimeAxis,
  }) {
    final xInterval = (maxX - minX) / 4;
    final yInterval = (maxY - minY) / 5;
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: AppColor.textPrimary(context),
            ),
          ),
          SizedBox(height: 8.h),
          SizedBox(
            height: 180.h,
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: yInterval > 0 ? yInterval : null,
                  verticalInterval: xInterval > 0 ? xInterval : null,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppColor.divider(context).withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: AppColor.divider(context).withValues(alpha: 0.3),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: showTimeAxis,
                      reservedSize: showTimeAxis ? 28 : 0,
                      interval: xInterval > 0 ? xInterval : null,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          DateFormat('HH:mm:ss').format(
                            DateTime.fromMillisecondsSinceEpoch(value.toInt()),
                          ),
                          style: TextStyle(
                            fontSize: 9.sp,
                            color: AppColor.textHint(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval: yInterval > 0 ? yInterval : null,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 9.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(color: AppColor.divider(context)),
                    left: BorderSide(color: AppColor.divider(context)),
                  ),
                ),
                lineBarsData: [
                  for (final s in series)
                    LineChartBarData(
                      spots: s.spots,
                      // 调试数据逐点直连，不做平滑，避免误读瞬时抖动
                      isCurved: false,
                      color: s.color,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) =>
                        Theme.of(context).brightness == Brightness.dark
                            ? AppColor.surfaceContainer(context)
                            : AppColor.textPrimary(context),
                    tooltipBorderRadius: BorderRadius.circular(8),
                    getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                      final label =
                          spot.barIndex >= 0 && spot.barIndex < series.length
                              ? series[spot.barIndex].label
                              : '';
                      return LineTooltipItem(
                        '$label: ${spot.y.toStringAsFixed(2)}',
                        TextStyle(
                          color: Colors.white,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
