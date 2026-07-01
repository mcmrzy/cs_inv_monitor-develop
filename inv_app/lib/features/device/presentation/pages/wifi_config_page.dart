import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:inv_app/core/services/provision_service.dart';
import 'package:inv_app/core/services/smartconfig_service.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/widgets/wifi_switch_dialog.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

enum _ProvisionMode { softap, smartconfig }

class WifiConfigPage extends StatefulWidget {
  const WifiConfigPage({super.key});

  @override
  State<WifiConfigPage> createState() => _WifiConfigPageState();
}

class _WifiConfigPageState extends State<WifiConfigPage> {
  final _provisionService = ProvisionService();
  final _smartConfigService = SmartConfigService();
  final _connectionModeService = ConnectionModeService(getIt<StorageService>());

  _ProvisionMode _provisionMode = _ProvisionMode.smartconfig;

  bool _wifiScanning = false;
  List<WifiNetwork> _csInvNetworks = [];
  WifiNetwork? _selectedDeviceAp;

  bool _scanningNearbyWifi = false;
  List<ScanResult> _nearbyWifiList = [];
  List<WifiNetwork> _phoneScannedWifi = []; // 手机端扫描的WiFi列表（连接热点前扫描）

  bool _provisioning = false;
  String _provisionStatus = '';
  bool _provisionOk = false;
  int _provisionStep = 0;

  final _workingSsidController = TextEditingController();
  final _workingPasswordController = TextEditingController();
  bool _showPassword = false;

  final _scSsidController = TextEditingController();
  final _scPasswordController = TextEditingController();
  bool _scShowPassword = false;
  SmartConfigStatus _scStatus = SmartConfigStatus.idle;
  StreamSubscription<SmartConfigStatus>? _scStatusSub;
  bool _scConfiguring = false;
  String? _originalSsid;

  @override
  void initState() {
    super.initState();
    _loadCurrentWifiSsid();
    _scStatusSub = _smartConfigService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _scStatus = status;
          if (status == SmartConfigStatus.configuring || status == SmartConfigStatus.scanning) {
            _scConfiguring = true;
          } else {
            _scConfiguring = false;
          }
        });
        if (status == SmartConfigStatus.success) {
          _onSmartConfigSuccess();
        }
      }
    });
  }

  Future<void> _loadCurrentWifiSsid() async {
    try {
      final ssid = await WiFiForIoTPlugin.getSSID();
      if (ssid != null && ssid.isNotEmpty && mounted) {
        _originalSsid = ssid;
        _scSsidController.text = ssid;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _workingSsidController.dispose();
    _workingPasswordController.dispose();
    _scSsidController.dispose();
    _scPasswordController.dispose();
    _scStatusSub?.cancel();
    _smartConfigService.dispose();
    super.dispose();
  }

  bool _isOpenNetwork(WifiNetwork net) {
    final cap = net.capabilities?.toUpperCase() ?? '';
    return !cap.contains('WPA') && !cap.contains('WEP') && !cap.contains('EAP');
  }

  Future<bool> _requestWifiPermissions() async {
    // Android 6+ 扫描WiFi列表必须有位置权限，这是系统限制
    final status = await Permission.location.request();
    return status.isGranted || status.isLimited;
  }

  Future<void> _scanCSInvWiFi() async {
    setState(() { _wifiScanning = true; _csInvNetworks = []; });
    try {
      final granted = await _requestWifiPermissions();
      if (!granted) {
        setState(() => _wifiScanning = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.wifiPermissionHint),
            duration: const Duration(seconds: 4),
          ));
        }
        return;
      }

      // 请求打开位置服务（Android 11及以下必须开启定位才能扫描WiFi）
      final serviceEnabled = await Permission.location.serviceStatus.isEnabled;
      if (!serviceEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.locationServiceHint),
          duration: const Duration(seconds: 4),
        ));
        setState(() => _wifiScanning = false);
        return;
      }

      // 关键改进：先关闭WiFi强制使用，让系统执行一次新的WiFi扫描
      // Android 系统有4次/2分钟的扫描限制，先关闭再打开可以触发新扫描
      await WiFiForIoTPlugin.forceWifiUsage(false);
      await Future.delayed(const Duration(milliseconds: 500));

      // 多次读取以获取最新结果
      List<WifiNetwork> allNetworks = [];
      for (int i = 0; i < 3; i++) {
        final networks = await WiFiForIoTPlugin.loadWifiList();
        allNetworks.addAll(networks);
        if (i < 2) await Future.delayed(const Duration(milliseconds: 800));
      }

      // 去重并按信号强度排序
      final ssidSet = <String>{};
      final filtered = <WifiNetwork>[];
      for (final n in allNetworks) {
        final ssid = n.ssid ?? '';
        if (ssid.isEmpty) continue;
        if (ssid.toUpperCase().startsWith('CS_INV') || ssid.toUpperCase().startsWith('CS-INV')) {
          if (!ssidSet.contains(ssid)) {
            ssidSet.add(ssid);
            filtered.add(n);
          }
        }
      }
      filtered.sort((a, b) => (b.level ?? -100).compareTo(a.level ?? -100));

      // 同时扫描所有附近WiFi（用于后续配网选择）
      await _scanAllNearbyWifi();

      setState(() { _csInvNetworks = filtered; _wifiScanning = false; });
    } catch (e) {
      setState(() => _wifiScanning = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)!.scanFailed}: $e')));
    }
  }

  /// 手机端扫描所有附近WiFi（在连接设备热点之前调用，缓存结果）
  Future<void> _scanAllNearbyWifi() async {
    try {
      await WiFiForIoTPlugin.forceWifiUsage(false);
      await Future.delayed(const Duration(milliseconds: 300));
      final networks = await WiFiForIoTPlugin.loadWifiList();
      // 过滤掉设备热点本身和无名称的
      _phoneScannedWifi = networks.where((n) {
        final ssid = n.ssid ?? '';
        if (ssid.isEmpty) return false;
        final upper = ssid.toUpperCase();
        return !upper.startsWith('CS_INV') && !upper.startsWith('CS-INV');
      }).toList();
      _phoneScannedWifi.sort((a, b) => (b.level ?? -100).compareTo(a.level ?? -100));
    } catch (_) {}
  }

  Future<void> _connectToAp(WifiNetwork network) async {
    setState(() {
      _selectedDeviceAp = network;
      _provisionStatus = AppLocalizations.of(context)!.connectingSsid(network.ssid ?? '');
      _provisionStep = 1;
      _nearbyWifiList = [];
      _workingSsidController.clear();
      _workingPasswordController.clear();
    });

    try {
      final ssid = network.ssid ?? '';

      // 改进：连接AP时增加重试机制（Android 10+ WiFi连接有时不稳定）
      bool connected = false;
      for (int attempt = 0; attempt < 3; attempt++) {
        connected = await WiFiForIoTPlugin.connect(ssid,
          password: null,
          security: _isOpenNetwork(network) ? NetworkSecurity.NONE : NetworkSecurity.WPA,
          joinOnce: true,
        );
        if (connected) break;
        if (attempt < 2) {
          setState(() => _provisionStatus = '${AppLocalizations.of(context)!.connectingSsid(ssid)} (${attempt + 2}/3)');
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (connected) {
        setState(() => _provisionStatus = AppLocalizations.of(context)!.waitingStableConnection);

        // 关键：强制HTTP请求走WiFi而不是移动数据
        await WiFiForIoTPlugin.forceWifiUsage(true);

        // 等待连接稳定，热点分配IP需要时间
        await Future.delayed(const Duration(seconds: 3));

        // 验证确实连上了设备热点（增加重试检查）
        String? currentSsid;
        for (int i = 0; i < 3; i++) {
          currentSsid = await WiFiForIoTPlugin.getSSID();
          if (currentSsid != null && currentSsid.toUpperCase().contains('CS_INV')) break;
          await Future.delayed(const Duration(seconds: 1));
        }

        if (currentSsid == null || !currentSsid.toUpperCase().contains('CS_INV')) {
          setState(() => _provisionStatus = AppLocalizations.of(context)!.noDeviceHotspotRetry);
          return;
        }

        setState(() {
          _provisionStatus = AppLocalizations.of(context)!.connectedScanning(ssid);
          _provisionStep = 2;
        });
        // 使用手机端已缓存的WiFi列表，不再通过设备扫描
        _usePhoneScannedWifi();
      } else {
        setState(() => _provisionStatus = AppLocalizations.of(context)!.connectionSsidFailed(ssid));
      }
    } catch (e) {
      setState(() => _provisionStatus = '${AppLocalizations.of(context)!.connectionFailed}: $e');
    }
  }

  /// 使用手机端扫描的WiFi列表（连接热点前已缓存，无需再通过设备扫描）
  void _usePhoneScannedWifi() {
    setState(() {
      _nearbyWifiList = _phoneScannedWifi.map((n) => ScanResult(
        ssid: n.ssid ?? '',
        rssi: n.level ?? -100,
        encrypted: !_isOpenNetwork(n),
      )).toList();
      _scanningNearbyWifi = false;
      _provisionStatus = _nearbyWifiList.isEmpty
          ? AppLocalizations.of(context)!.noWifiFoundInputManually
          : AppLocalizations.of(context)!.foundNWifi('${_nearbyWifiList.length}');
      _provisionStep = 2;
    });
  }

  /// 重新扫描附近WiFi（手机端，在连接设备热点后临时切回普通模式扫描）
  Future<void> _rescanNearbyWifiFromPhone() async {
    setState(() { _scanningNearbyWifi = true; });
    try {
      // 临时切回普通WiFi模式以执行扫描
      await WiFiForIoTPlugin.forceWifiUsage(false);
      await Future.delayed(const Duration(milliseconds: 500));

      List<WifiNetwork> networks = [];
      for (int i = 0; i < 2; i++) {
        final result = await WiFiForIoTPlugin.loadWifiList();
        networks.addAll(result);
        if (i < 1) await Future.delayed(const Duration(milliseconds: 600));
      }

      // 过滤掉设备热点
      final filtered = networks.where((n) {
        final ssid = n.ssid ?? '';
        if (ssid.isEmpty) return false;
        final upper = ssid.toUpperCase();
        return !upper.startsWith('CS_INV') && !upper.startsWith('CS-INV');
      }).toList();
      filtered.sort((a, b) => (b.level ?? -100).compareTo(a.level ?? -100));

      // 去重
      final seen = <String>{};
      final unique = <WifiNetwork>[];
      for (final n in filtered) {
        final ssid = n.ssid ?? '';
        if (!seen.contains(ssid)) {
          seen.add(ssid);
          unique.add(n);
        }
      }

      // 切回WiFi强制使用模式
      await WiFiForIoTPlugin.forceWifiUsage(true);

      setState(() {
        _nearbyWifiList = unique.map((n) => ScanResult(
          ssid: n.ssid ?? '',
          rssi: n.level ?? -100,
          encrypted: !_isOpenNetwork(n),
        )).toList();
        _scanningNearbyWifi = false;
        _provisionStatus = _nearbyWifiList.isEmpty
            ? AppLocalizations.of(context)!.noWifiFoundInputManually
            : AppLocalizations.of(context)!.foundNWifi('${_nearbyWifiList.length}');
        _provisionStep = 2;
      });
    } catch (e) {
      // 确保切回WiFi模式
      await WiFiForIoTPlugin.forceWifiUsage(true);
      setState(() {
        _scanningNearbyWifi = false;
        _provisionStatus = '${AppLocalizations.of(context)!.scanFailed}: $e';
      });
    }
  }

  void _pickWiFi(ScanResult wifi) {
    _workingSsidController.text = wifi.ssid;
    _workingPasswordController.clear();
    _showPassword = false;
    setState(() => _provisionStatus = AppLocalizations.of(context)!.selectedWifiInputPassword(wifi.ssid));
  }

  Future<void> _sendProvisionConfig() async {
    final ssid = _workingSsidController.text.trim();
    final password = _workingPasswordController.text.trim();
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.pleaseInputWifiName)));
      return;
    }
    setState(() { _provisioning = true; _provisionStatus = AppLocalizations.of(context)!.sendingProvisionInfo; _provisionOk = false; });

    // 确保请求走WiFi
    await WiFiForIoTPlugin.forceWifiUsage(true);

    var result = await _provisionService.configure(ssid, password);

    if (result.success) {
      setState(() { _provisionStatus = AppLocalizations.of(context)!.provisionSuccessConnecting; _provisionStep = 3; });
      await Future.delayed(const Duration(seconds: 2));
      for (int i = 0; i < 15; i++) {
        await WiFiForIoTPlugin.forceWifiUsage(true);
        final status = await _provisionService.checkStatus();
        if (status.success) {
          setState(() {
            _provisioning = false; _provisionOk = true;
            _provisionStatus = AppLocalizations.of(context)!.provisionCompleteWifiIp(status.ssid ?? '', status.ip ?? '');
          });
          _onSoftApProvisionSuccess();
          return;
        }
        if (mounted) setState(() => _provisionStatus = AppLocalizations.of(context)!.waitingDeviceConnectionN('${i + 1}'));
        await Future.delayed(const Duration(seconds: 2));
      }
      setState(() { _provisioning = false; _provisionStatus = AppLocalizations.of(context)!.configSentDeviceRestart; _provisionOk = true; });
      _onSoftApProvisionSuccess();
    } else {
      setState(() { _provisioning = false; _provisionStatus = '❌ ${result.message}'; });
    }
  }

  Future<void> _onSoftApProvisionSuccess() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    final mqtt = getIt<MQTTService>();
    bool deviceOnline = false;

    try {
      final onlineFuture = mqtt.statusStream
          .where((s) => s.online)
          .first
          .timeout(const Duration(seconds: 30));
      deviceOnline = await onlineFuture.then((_) => true).catchError((_) => false);
    } catch (_) {}

    if (!mounted) return;
    if (deviceOnline) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.deviceOnlineWifi),
        backgroundColor: AppColors.successLight,
        duration: const Duration(seconds: 3),
      ));
    }

    final shouldSwitch = await showWifiSwitchDialog(context, originalSsid: _originalSsid);
    if (!mounted) return;

    if (shouldSwitch && _originalSsid != null) {
      try {
        await WiFiForIoTPlugin.connect(_originalSsid!,
          password: null,
          security: NetworkSecurity.WPA,
          joinOnce: false,
        );
      } catch (_) {}

      await _connectionModeService.switchToRemote();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.switchedToRemoteMode),
          backgroundColor: AppColors.successLight,
        ));
      }
    }
  }

  Future<void> _startSmartConfig() async {
    final ssid = _scSsidController.text.trim();
    final password = _scPasswordController.text.trim();
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.pleaseInputWifiName)));
      return;
    }

    setState(() => _scConfiguring = true);
    final success = await _smartConfigService.startSmartConfig(
      ssid: ssid,
      password: password,
      timeout: const Duration(seconds: 60),
    );

    if (!success && mounted && _scStatus != SmartConfigStatus.success) {
      setState(() => _scConfiguring = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.smartConfigTimeoutHint),
        backgroundColor: AppColors.errorLight,
      ));
    }
  }

  void _stopSmartConfig() {
    _smartConfigService.stopSmartConfig();
    setState(() {
      _scConfiguring = false;
      _scStatus = SmartConfigStatus.idle;
    });
  }

  Future<void> _onSmartConfigSuccess() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context)!.configSuccess),
      backgroundColor: AppColors.successLight,
    ));

    setState(() => _scConfiguring = false);

    final mqtt = getIt<MQTTService>();
    bool deviceOnline = false;

    try {
      final onlineFuture = mqtt.statusStream
          .where((s) => s.online)
          .first
          .timeout(const Duration(seconds: 30));
      deviceOnline = await onlineFuture.then((_) => true).catchError((_) => false);
    } catch (_) {}

    if (!mounted) return;
    if (deviceOnline) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.deviceOnline),
        backgroundColor: AppColors.successLight,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.provisionSuccessWaiting),
        backgroundColor: const Color(0xFFF59E0B),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  void _resetProvision() {
    setState(() {
      _selectedDeviceAp = null;
      _nearbyWifiList = [];
      _provisionStep = 0;
      _provisionStatus = '';
      _provisionOk = false;
      _workingSsidController.clear();
      _workingPasswordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.wifiConfig),
      ),
      body: ListView(
        padding: EdgeInsets.all(20.w),
        children: [
          _buildModeSwitch(),
          SizedBox(height: 20.h),
          if (_provisionMode == _ProvisionMode.softap)
            _buildSoftApSection()
          else
            _buildSmartConfigSection(),
        ],
      ),
    );
  }

  Widget _buildModeSwitch() {
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceHover,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _provisionMode = _ProvisionMode.smartconfig),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              decoration: BoxDecoration(
                color: _provisionMode == _ProvisionMode.smartconfig ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.settings_input_antenna, size: 18.sp,
                  color: _provisionMode == _ProvisionMode.smartconfig ? Colors.white : AppColors.textSecondary),
                SizedBox(width: 6.w),
                Text(AppLocalizations.of(context)!.smartProvision,
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600,
                    color: _provisionMode == _ProvisionMode.smartconfig ? Colors.white : AppColors.textSecondary)),
              ]),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() => _provisionMode = _ProvisionMode.softap);
              if (_csInvNetworks.isEmpty && !_wifiScanning) _scanCSInvWiFi();
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              decoration: BoxDecoration(
                color: _provisionMode == _ProvisionMode.softap ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.router, size: 18.sp,
                  color: _provisionMode == _ProvisionMode.softap ? Colors.white : AppColors.textSecondary),
                SizedBox(width: 6.w),
                Text(AppLocalizations.of(context)!.hotspotProvision,
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600,
                    color: _provisionMode == _ProvisionMode.softap ? Colors.white : AppColors.textSecondary)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildSoftApSection() {
    final deviceConnected = _provisionStep >= 2;
    final isStep0 = !deviceConnected;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _stepIndicator(1, isStep0 ? '⭕' : '✓', _provisionStep >= 1),
        Expanded(child: Container(height: 2, color: _provisionStep >= 2 ? AppColors.successLight : const Color(0xFFE5E7EB))),
        _stepIndicator(2, _provisionStep >= 2 ? '✓' : '2', _provisionStep >= 2),
        Expanded(child: Container(height: 2, color: _provisionStep >= 3 ? AppColors.successLight : const Color(0xFFE5E7EB))),
        _stepIndicator(3, _provisionOk ? '✓' : '3', _provisionOk),
      ]),
      SizedBox(height: 8.h),
      Row(children: [
        SizedBox(width: 30.w, child: Text(AppLocalizations.of(context)!.connectDeviceHotspot, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.sp, color: _provisionStep>=1?AppColors.successLight:AppColors.textHint))),
        Expanded(child: Container()),
        SizedBox(width: 30.w, child: Text(AppLocalizations.of(context)!.selectWifi, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.sp, color: _provisionStep>=2?AppColors.successLight:AppColors.textHint))),
        Expanded(child: Container()),
        SizedBox(width: 30.w, child: Text(AppLocalizations.of(context)!.finish, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.sp, color: _provisionOk?AppColors.successLight:AppColors.textHint))),
      ]),
      SizedBox(height: 24.h),

      if (isStep0) ...[
        SizedBox(width: double.infinity, height: 46.h,
          child: ElevatedButton.icon(
            onPressed: _wifiScanning ? null : _scanCSInvWiFi,
            icon: _wifiScanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.wifi_find, size: 22),
            label: Text(_wifiScanning ? AppLocalizations.of(context)!.scanning : ' ${AppLocalizations.of(context)!.scanNearInverters}', style: const TextStyle(fontSize: 15)),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r))),
          ),
        ),

        if (_csInvNetworks.isNotEmpty) ...[
          SizedBox(height: 10.h),
          Text(AppLocalizations.of(context)!.foundNInverters('${_csInvNetworks.length}'), style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
          SizedBox(height: 8.h),
          ..._csInvNetworks.map((net) {
            final ssid = net.ssid ?? '';
            final rssi = net.level ?? -100;
            final sig = rssi > -50 ? '📶📶📶' : (rssi > -70 ? '📶📶' : '📶');
            return Card(
              margin: EdgeInsets.only(bottom: 8.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              child: ListTile(
                leading: Container(width: 44.w, height: 44.w, decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10.r)),
                  child: const Icon(Icons.solar_power, color: AppColors.primary, size: 22)),
                title: Text(ssid, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                subtitle: Text('$sig $rssi dBm', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
                onTap: () => _connectToAp(net),
              ),
            );
          }),
        ],

        if (_csInvNetworks.isEmpty && !_wifiScanning)
          Padding(padding: EdgeInsets.only(top: 16.h), child: Center(child: Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12.r)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.wifi_off, size: 40.sp, color: AppColors.textHint),
              SizedBox(height: 10.h),
              Text(AppLocalizations.of(context)!.noInverterFound, style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
              SizedBox(height: 4.h),
              Text(AppLocalizations.of(context)!.ensureDevicePowered, style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
            ]),
          ))),
      ],

      if (_provisionStep == 1) ...[
        Container(padding: EdgeInsets.all(16.w), decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12.r)),
          child: Row(children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12.w),
            Expanded(child: Text(_provisionStatus, style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary))),
          ])),
      ],

      if (deviceConnected) ...[
        Container(padding: EdgeInsets.all(12.w), margin: EdgeInsets.only(bottom: 16.h),
          decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10.r)),
          child: Row(children: [
            const Icon(Icons.check_circle, color: AppColors.successLight, size: 20),
            SizedBox(width: 8.w),
            Expanded(child: Text(AppLocalizations.of(context)!.connectedTo(_selectedDeviceAp?.ssid ?? ''), style: TextStyle(fontSize: 13.sp, color: const Color(0xFF065F46)))),
            GestureDetector(onTap: _resetProvision, child: Text(AppLocalizations.of(context)!.disconnect, style: TextStyle(fontSize: 12.sp, color: AppColors.errorLight))),
          ])),
      ],

      if (deviceConnected) ...[
        SizedBox(width: double.infinity, height: 44.h,
          child: OutlinedButton.icon(
            onPressed: _scanningNearbyWifi ? null : _rescanNearbyWifiFromPhone,
            icon: _scanningNearbyWifi
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi, size: 20),
            label: Text(_scanningNearbyWifi ? AppLocalizations.of(context)!.scanning : AppLocalizations.of(context)!.scanNearbyWifi, style: const TextStyle(fontSize: 14)),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              side: const BorderSide(color: AppColors.primary)),
          ),
        ),

        SizedBox(height: 8.h),

        if (_nearbyWifiList.isNotEmpty) ...[
          Text(AppLocalizations.of(context)!.clickWifiToFill, style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
          SizedBox(height: 6.h),
          Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12.r), border: Border.all(color: const Color(0xFFE5E7EB))),
            constraints: BoxConstraints(maxHeight: 200.h),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _nearbyWifiList.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
              itemBuilder: (_, i) {
                final w = _nearbyWifiList[i];
                final sig = w.rssi > -50 ? '📶📶📶' : (w.rssi > -70 ? '📶📶' : '📶');
                final selected = _workingSsidController.text == w.ssid;
                return ListTile(
                  leading: Icon(w.encrypted ? Icons.lock_outline : Icons.wifi, size: 20, color: selected ? AppColors.primary : AppColors.textHint),
                  title: Text(w.ssid, style: TextStyle(fontSize: 13.sp, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: AppColors.textPrimary)),
                  trailing: Text('$sig ${w.rssi}dBm', style: TextStyle(fontSize: 10.sp, color: AppColors.textHint)),
                  tileColor: selected ? const Color(0xFFEFF6FF) : null,
                  dense: true,
                  onTap: () => _pickWiFi(w),
                );
              },
            ),
          ),
          SizedBox(height: 16.h),
        ],

        TextField(
          controller: _workingSsidController,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.wifiName, hintText: AppLocalizations.of(context)!.clickAboveOrManual,
            prefixIcon: const Icon(Icons.wifi, color: AppColors.primary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
        SizedBox(height: 12.h),
        TextField(
          controller: _workingPasswordController,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.wifiPassword, hintText: AppLocalizations.of(context)!.inputWifiPassword,
            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textHint),
            suffixIcon: IconButton(
              icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textHint),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
        SizedBox(height: 20.h),
        SizedBox(width: double.infinity, height: 50.h,
          child: ElevatedButton.icon(
            onPressed: _provisioning ? null : _sendProvisionConfig,
            icon: _provisioning
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.router, size: 22),
            label: Text(_provisioning ? AppLocalizations.of(context)!.configuring : AppLocalizations.of(context)!.sendingProvisionInfo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.successLight, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r))),
          ),
        ),
      ],

      if (_provisionStatus.isNotEmpty) ...[
        SizedBox(height: 16.h),
        Container(width: double.infinity, padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: _provisionOk ? const Color(0xFFECFDF5) : (_provisionStatus.contains('❌') ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF)),
            borderRadius: BorderRadius.circular(12.r)),
          child: Row(children: [
            Icon(_provisionOk ? Icons.check_circle : (_provisionStatus.contains('❌') ? Icons.error : Icons.info),
              size: 20.sp, color: _provisionOk ? AppColors.successLight : (_provisionStatus.contains('❌') ? AppColors.errorLight : AppColors.primary)),
            SizedBox(width: 10.w),
            Expanded(child: Text(_provisionStatus, style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary))),
          ])),
      ],

      SizedBox(height: 60.h),
    ]);
  }

  Widget _buildSmartConfigSection() {
    final l10n = AppLocalizations.of(context)!;
    final statusText = switch (_scStatus) {
      SmartConfigStatus.idle => l10n.provisionReady,
      SmartConfigStatus.scanning => l10n.scanning,
      SmartConfigStatus.configuring => l10n.sendingProvisionInfo,
      SmartConfigStatus.success => '✅ ${l10n.configSuccess}',
      SmartConfigStatus.timeout => l10n.provisionTimeout,
      SmartConfigStatus.error => l10n.provisionFailedX,
    };

    final statusColor = switch (_scStatus) {
      SmartConfigStatus.idle => AppColors.textHint,
      SmartConfigStatus.scanning => AppColors.primary,
      SmartConfigStatus.configuring => AppColors.primary,
      SmartConfigStatus.success => AppColors.successLight,
      SmartConfigStatus.timeout => const Color(0xFFF59E0B),
      SmartConfigStatus.error => AppColors.errorLight,
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: EdgeInsets.all(14.w),
        margin: EdgeInsets.only(bottom: 20.h),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
          SizedBox(width: 10.w),
          Expanded(child: Text(
            AppLocalizations.of(context)!.smartConfigModeDesc,
            style: TextStyle(fontSize: 12.sp, color: AppColors.textPrimary),
          )),
        ]),
      ),

      TextField(
        controller: _scSsidController,
        enabled: !_scConfiguring,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context)!.wifiName,
          hintText: AppLocalizations.of(context)!.pleaseInputWifiName,
          prefixIcon: const Icon(Icons.wifi, color: AppColors.primary),
          suffixIcon: IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textHint, size: 20),
            onPressed: _scConfiguring ? null : _loadCurrentWifiSsid,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        ),
      ),
      SizedBox(height: 12.h),
      TextField(
        controller: _scPasswordController,
        enabled: !_scConfiguring,
        obscureText: !_scShowPassword,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context)!.wifiPassword,
          hintText: AppLocalizations.of(context)!.inputWifiPassword,
          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textHint),
          suffixIcon: IconButton(
            icon: Icon(_scShowPassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textHint),
            onPressed: () => setState(() => _scShowPassword = !_scShowPassword),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        ),
      ),
      SizedBox(height: 24.h),

      if (_scConfiguring)
        Column(children: [
          SizedBox(
            width: 48.w, height: 48.w,
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: 12.h),
          Text(statusText, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: statusColor)),
          SizedBox(height: 20.h),
          SizedBox(width: double.infinity, height: 46.h,
            child: OutlinedButton.icon(
              onPressed: _stopSmartConfig,
              icon: const Icon(Icons.stop, size: 20),
              label: Text(AppLocalizations.of(context)!.stopProvision, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.errorLight,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                side: const BorderSide(color: AppColors.errorLight),
              ),
            ),
          ),
        ])
      else
        SizedBox(width: double.infinity, height: 50.h,
          child: ElevatedButton.icon(
            onPressed: _scStatus == SmartConfigStatus.success ? null : _startSmartConfig,
            icon: const Icon(Icons.settings_input_antenna, size: 22),
            label: Text(_scStatus == SmartConfigStatus.success ? AppLocalizations.of(context)!.configSuccess : AppLocalizations.of(context)!.provisionStarted,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _scStatus == SmartConfigStatus.success ? AppColors.successLight : AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          ),
        ),

      if (_scStatus != SmartConfigStatus.idle && !_scConfiguring) ...[
        SizedBox(height: 16.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: _scStatus == SmartConfigStatus.success
                ? const Color(0xFFECFDF5)
                : (_scStatus == SmartConfigStatus.error || _scStatus == SmartConfigStatus.timeout)
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Row(children: [
            Icon(
              _scStatus == SmartConfigStatus.success
                  ? Icons.check_circle
                  : (_scStatus == SmartConfigStatus.error || _scStatus == SmartConfigStatus.timeout)
                      ? Icons.error
                      : Icons.info,
              size: 20.sp,
              color: statusColor,
            ),
            SizedBox(width: 10.w),
            Expanded(child: Text(statusText, style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary))),
          ]),
        ),
      ],

      SizedBox(height: 60.h),
    ]);
  }

  Widget _stepIndicator(int num, String label, bool active) {
    return Container(
      width: 30.w, height: 30.w,
      decoration: BoxDecoration(
        color: active ? AppColors.successLight : const Color(0xFFE5E7EB),
        shape: BoxShape.circle,
      ),
      child: Center(child: Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: active ? Colors.white : AppColors.textHint))),
    );
  }
}
