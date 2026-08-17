import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/data/local_cache_database.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/core/services/local_discovery_service.dart';
import 'package:inv_app/core/services/mdns_discovery_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/wifi_enable_dialog.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class LocalModePage extends StatefulWidget {
  const LocalModePage({super.key});

  @override
  State<LocalModePage> createState() => _LocalModePageState();
}

class _LocalModePageState extends State<LocalModePage> {
  late final ConnectionModeService _modeService;
  final LocalDiscoveryService _discoveryService = LocalDiscoveryService();
  final MDNSDiscoveryService _mdnsService = MDNSDiscoveryService();
  final LocalCommunicationService _commService = LocalCommunicationService();

  List<DiscoveredDevice> _apDevices = [];
  List<MDNSDevice> _mdnsDevices = [];
  List<Map<String, dynamic>> _cachedDevices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _connectedSSID;
  String? _errorMessage;
  StreamSubscription<ConnectionMode>? _modeSubscription;

  @override
  void initState() {
    super.initState();
    // 共享全局单例（需求 6：与 StationBloc/DeviceBloc 数据源分支保持一致）
    _modeService = getIt<ConnectionModeService>();
    _initMode();
    _loadCachedDevices();
  }

  Future<void> _initMode() async {
    await _modeService.init();
    _modeSubscription = _modeService.modeStream.listen((mode) {
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  /// 从本地缓存加载设备快照，用于离网时展示
  Future<void> _loadCachedDevices() async {
    try {
      final devices = await LocalCacheDatabase().loadDevices();
      if (mounted) setState(() => _cachedDevices = devices);
    } catch (_) {
      // 缓存读取失败不影响主流程
    }
  }

  @override
  void dispose() {
    _modeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _scanDevices() async {
    if (_isScanning) return;
    // 扫描前确保手机 WiFi 已开启（未开启弹窗引导，取消则中止扫描，Q1）
    if (!await ensureWifiEnabled(context)) return;
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _discoveryService.scanCSInvAPs(),
        _mdnsService.discoverInvServices(),
        _commService.scanLocalDevices(),
      ]);

      if (!mounted) return;

      final apResults = results[0] as List<DiscoveredDevice>;
      final mdnsResults = results[1] as List<MDNSDevice>;
      final udpResults = results[2] as List<DiscoveredDevice>;

      final mergedAPs = <String, DiscoveredDevice>{};
      for (final d in apResults) {
        mergedAPs[d.ssid] = d;
      }
      for (final d in udpResults) {
        if (!mergedAPs.containsKey(d.ssid)) {
          mergedAPs[d.ssid] = d;
        }
      }

      setState(() {
        _apDevices = mergedAPs.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
        _mdnsDevices = mdnsResults;
        _isScanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _errorMessage = '${AppLocalizations.of(context)!.scanFailed}: $e';
      });
    }
  }

  Future<void> _connectToDevice(DiscoveredDevice device) async {
    if (_isConnecting) return;
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final success = await _discoveryService.connectToAP(
        device.ssid,
        password: device.isEncrypted ? '' : null,
      );

      if (!mounted) return;

      if (success) {
        await _modeService.switchToLocal();
        _commService.connect('192.168.4.1');
        _commService.setConnectedSSID(device.ssid);

        setState(() {
          _connectedSSID = device.ssid;
          _isConnecting = false;
        });

        final testOk = await _commService.testConnection();
        if (testOk && mounted) {
          // 连接成功：进入离网主界面（复用 ShellRoute 骨架，不复制页面）
          context.go('/home');
        } else if (mounted) {
          AppToast.show(context, AppLocalizations.of(context)!.apCommTestFailed, type: ToastType.error);
        }
      } else {
        setState(() {
          _isConnecting = false;
          _errorMessage = AppLocalizations.of(context)!.connectionFailed;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _errorMessage = '${AppLocalizations.of(context)!.connectionFailed}: $e';
      });
    }
  }

  Future<void> _disconnect() async {
    await _discoveryService.disconnectFromAP();
    await _modeService.switchToRemote();
    _commService.disconnect();
    setState(() {
      _connectedSSID = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.surfaceHover(context),
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.localConnection,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
      ),
      body: Column(
        children: [
          _buildModeSwitch(),
          if (_modeService.isLocal) _buildWiFiWarning(),
          _buildScanButton(),
          if (_errorMessage != null) _buildErrorMessage(),
          Expanded(child: _buildDeviceList()),
        ],
      ),
    );
  }

  Widget _buildModeSwitch() {
    final isLocal = _modeService.isLocal;
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 16.h),
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 28.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // 居中的图标
          Container(
            width: 56.w,
            height: 56.w,
            decoration: BoxDecoration(
              color: isLocal
                  ? AppColors.successLight.withValues(alpha: 0.15)
                  : AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Icon(
              isLocal ? Icons.wifi : Icons.cloud_outlined,
              size: 28.sp,
              color: isLocal ? AppColors.successLight : AppColors.primary,
            ),
          ),
          SizedBox(height: 12.h),
          // 居中的主标题
          Text(
            isLocal
                ? AppLocalizations.of(context)!.localMode
                : AppLocalizations.of(context)!.remoteMode,
            style: TextStyle(
              fontSize: 17.sp,
              fontWeight: FontWeight.bold,
              color: AppColor.textPrimary(context),
            ),
          ),
          SizedBox(height: 4.h),
          // 居中的副标题
          Text(
            isLocal
                ? AppLocalizations.of(context)!.localModeDirectAp
                : AppLocalizations.of(context)!.remoteModeCloud,
            style: TextStyle(
              fontSize: 13.sp,
              color: AppColor.textHint(context),
            ),
          ),
          SizedBox(height: 20.h),
          // Switch 放在下方
          Switch(
            value: isLocal,
            activeTrackColor: isLocal ? AppColors.successLight : AppColors.primary,
            activeThumbColor: Colors.white,
            onChanged: (value) async {
              if (value) {
                await _modeService.switchToLocal();
              } else {
                await _disconnect();
              }
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWiFiWarning() {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: const Color(0xFFFDBA74), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18.sp,
            color: const Color(0xFFF97316),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.apDisconnectWarning,
              style: TextStyle(fontSize: 12.sp, color: const Color(0xFF9A3412)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
      child: SizedBox(
        width: double.infinity,
        height: 46.h,
        child: ElevatedButton(
          onPressed: _isScanning ? null : _scanDevices,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
            elevation: 0,
          ),
          child: _isScanning
              ? SizedBox(
                  width: 20.w,
                  height: 20.w,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_find_rounded, size: 20.sp),
                    SizedBox(width: 8.w),
                    Text(
                      AppLocalizations.of(context)!.scanDevices,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppColors.badgeAlarmBg,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18.sp,
            color: AppColors.error,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(fontSize: 12.sp, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    final hasScanned = _apDevices.isNotEmpty || _mdnsDevices.isNotEmpty;
    final hasCached = _cachedDevices.isNotEmpty;

    if (!hasScanned && !hasCached && !_isScanning) {
      // 小烁提醒动作插画：本地模式未发现设备空态（美术路由 C3/reminder）
      return XiaoshuoStatePanel(
        asset: CsergyAssets.xiaoshuoReminder,
        title: AppLocalizations.of(context)!.noDeviceFound,
        message: AppLocalizations.of(context)!.ensureDeviceApMode,
        size: 176,
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 20.h),
      children: [
        if (_apDevices.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: Text(
              AppLocalizations.of(context)!
                  .deviceApCount('${_apDevices.length}'),
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColor.textSecondary(context),
              ),
            ),
          ),
          ..._apDevices.map((d) => _buildAPDeviceCard(d)),
        ],
        if (_mdnsDevices.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.only(top: 12.h, bottom: 8.h),
            child: Text(
              AppLocalizations.of(context)!
                  .lanDeviceCount('${_mdnsDevices.length}'),
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColor.textSecondary(context),
              ),
            ),
          ),
          ..._mdnsDevices.map((d) => _buildMDNSDeviceCard(d)),
        ],
        // 缓存设备区：来自 sqflite 快照，标记在线/离线
        if (hasCached) ...[
          _buildCachedSection(),
        ],
      ],
    );
  }

  /// 缓存设备区标题 + 设备列表
  Widget _buildCachedSection() {
    final l10n = AppLocalizations.of(context)!;
    // 收集已扫描到的 SN，用于判断缓存设备是否在线
    final onlineSNs = <String>{};
    for (final d in _apDevices) {
      onlineSNs.add(d.ssid.replaceAll(RegExp(r'^CS[-_]INV[-_]', caseSensitive: false), ''));
    }
    for (final d in _mdnsDevices) {
      if (d.sn != null) onlineSNs.add(d.sn!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 16.h, bottom: 4.h),
          child: Text(
            l10n.str('local_cached_devices'),
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: AppColor.textSecondary(context),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 8.h),
          child: Text(
            l10n.str('local_cached_devices_hint'),
            style: TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
          ),
        ),
        // 快照时效提示：updated_at 参与时效判断，
        // 避免用户把陈旧快照当当前设备状态
        _buildSnapshotFreshness(),
        ..._cachedDevices.map((d) => _buildCachedDeviceCard(d, onlineSNs)),
      ],
    );
  }

  /// 快照时效提示：展示最新快照时间，超过 24 小时以警示色提醒
  Widget _buildSnapshotFreshness() {
    if (_cachedDevices.isEmpty) return const SizedBox.shrink();
    DateTime? latest;
    for (final d in _cachedDevices) {
      final raw = d['updated_at']?.toString() ?? '';
      final parsed = raw.isEmpty ? null : DateTime.tryParse(raw);
      if (parsed != null && (latest == null || parsed.isAfter(latest))) {
        latest = parsed;
      }
    }
    if (latest == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final stale = DateTime.now().difference(latest.toLocal()) >
        const Duration(hours: 24);
    final timeStr = DateFormat('MM-dd HH:mm').format(latest.toLocal());
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        children: [
          Icon(
            stale ? Icons.history_rounded : Icons.schedule_rounded,
            size: 13.sp,
            color: stale ? AppColors.warning : AppColor.textHint(context),
          ),
          SizedBox(width: 4.w),
          Expanded(
            child: Text(
              l10n.str('local_snapshot_time', {'time': timeStr}),
              style: TextStyle(
                fontSize: 11.sp,
                color: stale ? AppColors.warning : AppColor.textHint(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 缓存设备卡片：根据是否在扫描结果中显示在线/离线标记
  Widget _buildCachedDeviceCard(
    Map<String, dynamic> device,
    Set<String> onlineSNs,
  ) {
    final sn = device['sn']?.toString() ?? '';
    final name = device['name']?.toString() ?? sn;
    final model = device['model']?.toString() ?? '';
    final isOnline = onlineSNs.contains(sn);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: isOnline ? () => context.push('/device/$sn') : null,
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: isOnline
                        ? AppColors.badgeNormalBg
                        : AppColor.surfaceHover(context),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    isOnline ? Icons.solar_power : Icons.solar_power_outlined,
                    size: 20.sp,
                    color: isOnline ? AppColors.successLight : AppColor.textHint(context),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: isOnline ? AppColor.textPrimary(context) : AppColor.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        '$sn${model.isNotEmpty ? ' · $model' : ''}',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? AppColors.badgeNormalBg
                        : AppColor.surfaceHover(context),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(
                    isOnline
                        ? l10n.str('local_device_online')
                        : l10n.str('local_device_offline'),
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: isOnline ? AppColors.successLight : AppColor.textHint(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAPDeviceCard(DiscoveredDevice device) {
    final isConnected = _connectedSSID == device.ssid;
    final isConnectingToThis = _isConnecting && _connectedSSID == null;

    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: isConnected ? null : () => _connectToDevice(device),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? AppColors.badgeNormalBg
                        : AppColor.primarySoft(context),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    isConnected ? Icons.wifi : Icons.wifi_tethering,
                    size: 20.sp,
                    color: isConnected
                        ? AppColors.successLight
                        : AppColors.primary,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.ssid,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColor.textPrimary(context),
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Row(
                        children: [
                          _buildSignalIndicator(device.signalLevel),
                          SizedBox(width: 6.w),
                          Text(
                            '${device.rssi} dBm',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: AppColor.textHint(context),
                            ),
                          ),
                          if (device.isEncrypted) ...[
                            SizedBox(width: 8.w),
                            Icon(
                              Icons.lock_outline,
                              size: 12.sp,
                              color: AppColor.textHint(context),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (isConnectingToThis)
                  SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: const CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else if (isConnected)
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: AppColors.badgeNormalBg,
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.apConnected,
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.successLight,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18.sp,
                    color: AppColor.textHint(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMDNSDeviceCard(MDNSDevice device) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () async {
            if (device.host.isNotEmpty) {
              _commService.connect(device.host);
              _modeService.switchToLocal();
              setState(() {});
              // 与 AP 路径对齐：连接后探测设备通信，失败不进入离网主界面
              final testOk = await _commService.testConnection();
              if (testOk && mounted) {
                // 进入离网主界面（复用 ShellRoute 骨架，不复制页面）
                context.go('/home');
              } else if (mounted) {
                AppToast.show(
                  context,
                  AppLocalizations.of(context)!.apCommTestFailed,
                  type: ToastType.error,
                );
              }
            }
          },
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: AppColors.badgeNormalBg,
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    Icons.lan,
                    size: 20.sp,
                    color: AppColors.successLight,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColor.textPrimary(context),
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        '${device.host}${device.port > 0 ? ':${device.port}' : ''}${device.sn != null ? ' · SN: ${device.sn}' : ''}',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18.sp,
                  color: AppColor.textHint(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignalIndicator(int level) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        final active = i < level;
        return Container(
          width: 3.w,
          height: (6 + i * 3.0).h,
          margin: EdgeInsets.only(right: 1.w),
          decoration: BoxDecoration(
            color: active
                ? (level >= 3 ? AppColors.successLight : AppColors.orange)
                : AppColor.border(context),
            borderRadius: BorderRadius.circular(1.r),
          ),
        );
      }),
    );
  }
}
