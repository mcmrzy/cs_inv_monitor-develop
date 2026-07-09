import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/core/services/local_discovery_service.dart';
import 'package:inv_app/core/services/mdns_discovery_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
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
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _connectedSSID;
  String? _errorMessage;
  StreamSubscription<ConnectionMode>? _modeSubscription;

  @override
  void initState() {
    super.initState();
    _modeService = ConnectionModeService(getIt<StorageService>());
    _initMode();
  }

  Future<void> _initMode() async {
    await _modeService.init();
    _modeSubscription = _modeService.modeStream.listen((mode) {
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  @override
  void dispose() {
    _modeSubscription?.cancel();
    _modeService.dispose();
    super.dispose();
  }

  Future<void> _scanDevices() async {
    if (_isScanning) return;
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
          context.push('/device/${device.ssid}');
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.apCommTestFailed),
              backgroundColor: AppColors.warning,
            ),
          );
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
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: Text(
            AppLocalizations.of(context)!.localConnection,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
        ),
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
      margin: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          Icon(
            isLocal ? Icons.wifi : Icons.cloud_outlined,
            size: 22.sp,
            color: isLocal ? AppColors.successLight : AppColors.primary,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLocal ? AppLocalizations.of(context)!.localMode : AppLocalizations.of(context)!.remoteMode,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  isLocal ? AppLocalizations.of(context)!.localModeDirectAp : AppLocalizations.of(context)!.remoteModeCloud,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isLocal,
            activeTrackColor: AppColors.successLight,
            activeThumbColor: AppColors.successLight,
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
          Icon(Icons.warning_amber_rounded, size: 18.sp, color: const Color(0xFFF97316)),
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
                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
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
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18.sp, color: AppColors.error),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(fontSize: 12.sp, color: const Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    if (_apDevices.isEmpty && _mdnsDevices.isEmpty && !_isScanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56.sp, color: AppColors.textHint),
            SizedBox(height: 12.h),
            Text(
              AppLocalizations.of(context)!.noDeviceFound,
              style: TextStyle(fontSize: 15.sp, color: AppColors.textHint),
            ),
            SizedBox(height: 4.h),
            Text(
              AppLocalizations.of(context)!.ensureDeviceApMode,
              style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 20.h),
      children: [
        if (_apDevices.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: Text(
              AppLocalizations.of(context)!.deviceApCount('${_apDevices.length}'),
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ..._apDevices.map((d) => _buildAPDeviceCard(d)),
        ],
        if (_mdnsDevices.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.only(top: 12.h, bottom: 8.h),
            child: Text(
              AppLocalizations.of(context)!.lanDeviceCount('${_mdnsDevices.length}'),
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ..._mdnsDevices.map((d) => _buildMDNSDeviceCard(d)),
        ],
      ],
    );
  }

  Widget _buildAPDeviceCard(DiscoveredDevice device) {
    final isConnected = _connectedSSID == device.ssid;
    final isConnectingToThis = _isConnecting && _connectedSSID == null;

    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: isConnected
              ? null
              : () => _connectToDevice(device),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    isConnected
                        ? Icons.wifi
                        : Icons.wifi_tethering,
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
                          color: AppColors.textPrimary,
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
                              color: AppColors.textHint,
                            ),
                          ),
                          if (device.isEncrypted) ...[
                            SizedBox(width: 8.w),
                            Icon(Icons.lock_outline, size: 12.sp, color: AppColors.textHint),
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
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
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
                  Icon(Icons.chevron_right_rounded, size: 18.sp, color: AppColors.textHint),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () {
            if (device.host.isNotEmpty) {
              _commService.connect(device.host);
              _modeService.switchToLocal();
              setState(() {});
              context.push('/device/${device.sn ?? device.name}');
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
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(Icons.lan, size: 20.sp, color: AppColors.successLight),
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
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        '${device.host}${device.port > 0 ? ':${device.port}' : ''}${device.sn != null ? ' · SN: ${device.sn}' : ''}',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18.sp, color: AppColors.textHint),
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
                ? (level >= 3 ? AppColors.successLight : const Color(0xFFF59E0B))
                : const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(1.r),
          ),
        );
      }),
    );
  }
}
