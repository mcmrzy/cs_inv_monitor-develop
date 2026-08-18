import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/local_discovery_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/wifi_enable_dialog.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 本地升级页（固定双 Tab：BLE 升级 / AP 升级，扫描式）
///
/// 与配网流程一致：两个 Tab 均直接实时扫描周边设备，
/// 只显示扫描到的设备，不再依赖已绑定设备列表与型号白名单：
/// - 左 BLE：按 CSIV-CT 服务 UUID 扫描广播 → 点击连接读 SN → 进入升级执行页；
/// - 右 AP：扫描 CS_INV_/CS-INV- 热点 → 点击连接热点 → 进入升级执行页。
///
/// [deviceSN]/[deviceModel] 仅为路由参数兼容保留（/local-upgrade?sn=&model=），
/// 页面主体逻辑为扫描式，不使用这两个参数。
class LocalUpgradePage extends StatefulWidget {
  /// 设备序列号（路由兼容保留，扫描式流程不使用）
  final String deviceSN;

  /// 设备型号（路由兼容保留，不再做型号能力过滤）
  final String deviceModel;

  const LocalUpgradePage({
    super.key,
    required this.deviceSN,
    required this.deviceModel,
  });

  @override
  State<LocalUpgradePage> createState() => _LocalUpgradePageState();
}

class _LocalUpgradePageState extends State<LocalUpgradePage>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 固定两个 Tab（BLE / AP），不做型号过滤
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          l10n.str('ota_local_upgrade'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: l10n.str('local_upgrade_tab_ble'),
              icon: const Icon(Icons.bluetooth_rounded, size: 20),
              height: 52.h,
            ),
            Tab(
              text: l10n.str('local_upgrade_tab_ap'),
              icon: const Icon(Icons.wifi_rounded, size: 20),
              height: 52.h,
            ),
          ],
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColor.textSecondary(context),
          indicatorColor: AppColors.primary,
        ),
      ),
      // TabBarView 子页均为 StatefulWidget 且类型不同，切 Tab 状态自动保留；
      // 子页内另启用 AutomaticKeepAliveClientMixin 双重保险。
      body: TabBarView(
        controller: _tabController,
        children: const [
          _BleUpgradeTab(),
          _ApUpgradeTab(),
        ],
      ),
    );
  }
}

/// 设备广播名中的 CS_INV_/CS-INV- 前缀（忽略大小写），去掉后即为 SN
final RegExp _snPrefixPattern = RegExp(r'^CS[-_]INV[-_]', caseSensitive: false);

/// 从广播名 / SSID 中解析设备 SN（去前缀；为空则回退原始串）
String _parseSn(String raw) {
  final sn = raw.replaceFirst(_snPrefixPattern, '').trim();
  return sn.isEmpty ? raw.trim() : sn;
}

/// 跳转本地升级执行页（[LocalOTAPage] 对应路由 /ota/:sn/local）
void _pushLocalOta(
  BuildContext context, {
  required String sn,
  required String channel,
}) {
  final uri = Uri(
    path: '/ota/$sn/local',
    queryParameters: {
      'ip': '192.168.4.1',
      'channel': channel,
    },
  );
  context.push(uri.toString());
}

/// 「开始扫描」主按钮（两个 Tab 共用样式，参考 local_mode_page）
class _ScanButton extends StatelessWidget {
  final bool scanning;
  final IconData icon;
  final VoidCallback onPressed;

  const _ScanButton({
    required this.scanning,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
      child: SizedBox(
        width: double.infinity,
        height: 46.h,
        child: ElevatedButton(
          onPressed: scanning ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
            elevation: 0,
          ),
          child: scanning
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
                    Icon(icon, size: 20.sp),
                    SizedBox(width: 8.w),
                    Text(
                      l10n.scanDevices,
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
}

/// 空态面板 + 重新扫描按钮（两个 Tab 共用，文案按 Tab 传入）
class _ScanEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRescan;

  const _ScanEmptyState({
    required this.title,
    required this.message,
    required this.onRescan,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          XiaoshuoStatePanel(
            asset: CsergyAssets.xiaoshuoReminder,
            title: title,
            message: message,
            size: 176,
          ),
          SizedBox(height: 16.h),
          OutlinedButton.icon(
            onPressed: onRescan,
            icon: Icon(Icons.refresh_rounded, size: 16.sp),
            label: Text(l10n.str('rescan')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// BLE 扫描到的设备（按 MAC 去重后的展示模型）
class _ScannedBleDevice {
  final String macAddress;
  final String name;
  final int rssi;

  const _ScannedBleDevice({
    required this.macAddress,
    required this.name,
    required this.rssi,
  });

  String get displayName {
    final sn = name.replaceFirst(_snPrefixPattern, '').trim();
    // 广播名为空或仅含前缀时回退显示 MAC
    return sn.isEmpty ? macAddress : sn;
  }
}

/// BLE 升级 Tab：实时扫描 CSIV-CT 广播 → 连接读 SN → 进入升级执行页
class _BleUpgradeTab extends StatefulWidget {
  const _BleUpgradeTab();

  @override
  State<_BleUpgradeTab> createState() => _BleUpgradeTabState();
}

class _BleUpgradeTabState extends State<_BleUpgradeTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final BleAdapter _adapter = getIt<BleAdapter>();

  StreamSubscription<BleScanResult>? _scanSub;
  Timer? _scanStopTimer;
  final Map<String, _ScannedBleDevice> _devices = {};
  List<_ScannedBleDevice> _sortedDevices = const [];

  bool _scanning = false;
  String? _connectingMac;

  @override
  void dispose() {
    _scanStopTimer?.cancel();
    _scanSub?.cancel();
    // 页面销毁时兜底停止底层扫描，避免残留
    _adapter.stopScan();
    super.dispose();
  }

  /// 开始一轮 BLE 扫描（参考 BleDirectService._scanOnce：
  /// 按 CSIV-CT 服务 UUID 过滤，15s 超时）
  Future<void> _startScan() async {
    if (_scanning) return;
    final l10n = AppLocalizations.of(context)!;

    // 扫描前检查蓝牙适配器状态，未开启给出提示
    final status = await _adapter.status;
    if (!mounted) return;
    if (status != BleAdapterStatus.on) {
      AppToast.show(
        context,
        l10n.str('ble_bluetooth_off'),
        type: ToastType.error,
      );
      return;
    }

    setState(() {
      _scanning = true;
      _devices.clear();
      _sortedDevices = const [];
    });

    await _scanSub?.cancel();
    _scanSub = _adapter
        .scan(
          serviceUuids: const [BleCtProtocol.serviceUuid],
          timeout: const Duration(seconds: 15),
        )
        .listen(
          _onScanResult,
          onError: (Object e) {
            if (!mounted) return;
            AppToast.show(
              context,
              l10n.str('ble_scan_failed'),
              type: ToastType.error,
            );
            _finishScan();
          },
        );

    // 底层扫描到 15s 自动停止但流不关闭，此处定时收尾
    _scanStopTimer?.cancel();
    _scanStopTimer = Timer(const Duration(seconds: 16), _finishScan);
  }

  void _onScanResult(BleScanResult result) {
    if (!mounted) return;
    // 按 MAC 去重（保留最新广播名与信号强度），按信号强度倒序展示
    _devices[result.macAddress] = _ScannedBleDevice(
      macAddress: result.macAddress,
      name: result.name,
      rssi: result.rssi,
    );
    _sortedDevices = _devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    setState(() {});
  }

  void _finishScan() {
    _scanStopTimer?.cancel();
    _scanStopTimer = null;
    _scanSub?.cancel();
    _scanSub = null;
    if (!mounted) return;
    if (_scanning) setState(() => _scanning = false);
  }

  /// 点击设备：连接读 SN → 跳转 BLE 通道升级执行页
  Future<void> _onDeviceTap(_ScannedBleDevice device) async {
    if (_connectingMac != null) return;
    final l10n = AppLocalizations.of(context)!;
    final manager = getIt<BleDeviceManager>();

    setState(() => _connectingMac = device.macAddress);
    try {
      // 连接并读取设备 SN（autoReconnect=false：临时连接，不做后台重连）
      final session = await manager.connectDevice(
        device.macAddress,
        autoReconnect: false,
      );
      final sn = (session.sn ?? '').trim().isNotEmpty
          ? session.sn!.trim()
          : _parseSn(device.name);

      // 释放连接：升级执行页（BLE 通道）会自行重新扫描并连接设备，
      // 避免两条链路同时占用同一 GATT 连接导致冲突
      await manager.disconnectDevice(device.macAddress);

      if (!mounted) return;
      if (sn.isEmpty) {
        AppToast.show(
          context,
          l10n.str('ble_connection_failed'),
          type: ToastType.error,
        );
        return;
      }
      _pushLocalOta(context, sn: sn, channel: 'ble');
    } catch (_) {
      // 连接失败：清理会话并 Toast 提示
      await manager.disconnectDevice(device.macAddress);
      if (!mounted) return;
      AppToast.show(
        context,
        l10n.str('ble_connection_failed'),
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _connectingMac = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        _ScanButton(
          scanning: _scanning,
          icon: Icons.bluetooth_searching_rounded,
          onPressed: _startScan,
        ),
        Expanded(
          child: _scanning && _sortedDevices.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _sortedDevices.isEmpty
                  ? _ScanEmptyState(
                      title: l10n.noDeviceFound,
                      message: l10n.str('ble_found_empty'),
                      onRescan: _startScan,
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 20.h),
                      itemCount: _sortedDevices.length,
                      itemBuilder: (_, index) =>
                          _buildDeviceCard(_sortedDevices[index]),
                    ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(_ScannedBleDevice device) {
    final connecting = _connectingMac == device.macAddress;

    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: connecting ? null : () => _onDeviceTap(device),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: AppColor.primarySoft(context),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    Icons.bluetooth_rounded,
                    size: 20.sp,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.displayName,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColor.textPrimary(context),
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        '${device.macAddress} · ${device.rssi} dBm',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (connecting)
                  SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: const CircularProgressIndicator(strokeWidth: 2.5),
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
}

/// AP 升级 Tab：扫描 CS_INV_/CS-INV- 热点 → 连接 → 进入升级执行页
class _ApUpgradeTab extends StatefulWidget {
  const _ApUpgradeTab();

  @override
  State<_ApUpgradeTab> createState() => _ApUpgradeTabState();
}

class _ApUpgradeTabState extends State<_ApUpgradeTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final LocalDiscoveryService _discoveryService = LocalDiscoveryService();

  List<DiscoveredDevice> _devices = const [];
  bool _scanning = false;
  String? _connectingSsid;

  /// 开始一轮 AP 扫描（扫描前确保手机 WiFi 已开启）
  Future<void> _startScan() async {
    if (_scanning) return;
    // 扫描前确保手机 WiFi 已开启（未开启弹窗引导，取消则中止扫描，Q1）
    if (!await ensureWifiEnabled(context)) return;
    if (!mounted) return;

    setState(() {
      _scanning = true;
    });

    try {
      final results = await _discoveryService.scanCSInvAPs();
      if (!mounted) return;

      // 按 ssid 去重（保留信号最强的一条），结果已按 rssi 倒序
      final merged = <String, DiscoveredDevice>{};
      for (final d in results) {
        merged.putIfAbsent(d.ssid, () => d);
      }
      setState(() {
        _devices = merged.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
        _scanning = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _scanning = false);
    }
  }

  /// 点击热点：连接设备 AP → 成功后跳转 WiFi 通道升级执行页
  Future<void> _onDeviceTap(DiscoveredDevice device) async {
    if (_connectingSsid != null) return;
    final l10n = AppLocalizations.of(context)!;

    setState(() => _connectingSsid = device.ssid);
    try {
      final success = await _discoveryService.connectToAP(
        device.ssid,
        password: device.isEncrypted ? '' : null,
      );
      if (!mounted) return;
      if (success) {
        // 设备热点固定 IP：192.168.4.1；SN 从 SSID 去前缀解析
        _pushLocalOta(context, sn: _parseSn(device.ssid), channel: 'wifi');
      } else {
        AppToast.show(context, l10n.connectionFailed, type: ToastType.error);
      }
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, l10n.connectionFailed, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _connectingSsid = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        _ScanButton(
          scanning: _scanning,
          icon: Icons.wifi_find_rounded,
          onPressed: _startScan,
        ),
        Expanded(
          child: _scanning && _devices.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _devices.isEmpty
                  ? _ScanEmptyState(
                      title: l10n.noDeviceFound,
                      message: l10n.ensureDeviceApMode,
                      onRescan: _startScan,
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 20.h),
                      itemCount: _devices.length,
                      itemBuilder: (_, index) =>
                          _buildDeviceCard(_devices[index]),
                    ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(DiscoveredDevice device) {
    final connecting = _connectingSsid == device.ssid;

    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: connecting ? null : () => _onDeviceTap(device),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: AppColor.primarySoft(context),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    Icons.wifi_tethering,
                    size: 20.sp,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // 标题展示 SN（SSID 去掉 CS_INV_/CS-INV- 前缀）
                        _parseSn(device.ssid),
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
                if (connecting)
                  SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: const CircularProgressIndicator(strokeWidth: 2.5),
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

  /// 信号强度指示条（与 local_mode_page._buildSignalIndicator 保持一致）
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
