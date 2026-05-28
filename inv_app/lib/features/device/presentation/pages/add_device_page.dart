import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/core/services/provision_service.dart';
import 'package:inv_app/core/services/smartconfig_service.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/widgets/wifi_switch_dialog.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/utils/sn_utils.dart';

enum _ProvisionMode { softap, smartconfig }

class AddDevicePage extends StatefulWidget {
  final int? stationId;

  const AddDevicePage({super.key, this.stationId});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> with SingleTickerProviderStateMixin {
  final _snController = TextEditingController();
  final _provisionService = ProvisionService();
  final _smartConfigService = SmartConfigService();
  final _connectionModeService = ConnectionModeService(getIt<StorageService>());

  late TabController _tabController;
  bool _scanning = false;
  MobileScannerController? _cameraController;
  String _lastScanned = '';
  String _scannedPin = '';

  int _sessionBoundCount = 0;
  bool _bindSuccess = false;
  List<_ScanHistoryEntry> _scanHistory = [];
  bool _autoFlash = true;

  _ProvisionMode _provisionMode = _ProvisionMode.softap;

  bool _wifiScanning = false;
  List<WifiNetwork> _csInvNetworks = [];
  WifiNetwork? _selectedDeviceAp;

  bool _scanningNearbyWifi = false;
  List<ScanResult> _nearbyWifiList = [];

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
    _tabController = TabController(length: 3, vsync: this);
    _cameraController = MobileScannerController(
      torchEnabled: _autoFlash,
    );
    _loadScanHistory();
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
    _snController.dispose();
    _workingSsidController.dispose();
    _workingPasswordController.dispose();
    _scSsidController.dispose();
    _scPasswordController.dispose();
    _scStatusSub?.cancel();
    _smartConfigService.dispose();
    _tabController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanning) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;
    final raw = barcode.rawValue!.trim();
    if (raw.isEmpty || raw == _lastScanned) return;

    _scanning = true;

    final qr = parseQRCode(raw);
    if (qr == null) {
      _lastScanned = raw;
      _scannedPin = '';
      _scanning = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('无法识别的二维码:\n$raw'),
          backgroundColor: AppColors.errorLight,
          duration: const Duration(seconds: 3),
        ));
      }
      return;
    }

    final sn = qr.sn.toUpperCase();
    final pin = qr.pin ?? '';

    if (!validateSNFormat(sn)) {
      _lastScanned = sn;
      _scannedPin = '';
      _scanning = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('SN格式不正确:\n${formatSNForDisplay(sn)}'),
          backgroundColor: AppColors.errorLight,
          duration: const Duration(seconds: 3),
        ));
      }
      return;
    }

    if (!validateCheckDigitOnly(sn)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('⚠ 校验码不匹配: ${formatSNForDisplay(sn)}\n请确认 SN 是否正确'),
          backgroundColor: const Color(0xFFF59E0B),
          duration: const Duration(seconds: 4),
        ));
      }
    }

    _lastScanned = sn;
    _scannedPin = pin;
    _bindDevice(sn);
  }

  Future<void> _bindDevice(String sn) async {
    if (!mounted) return;
    context.read<DeviceBloc>().add(DeviceBindRequested(sn: sn, stationId: widget.stationId));
  }

  void _manualBind() {
    final raw = _snController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入设备SN')));
      return;
    }

    final qr = parseQRCode(raw);
    final sn = qr != null ? qr.sn.toUpperCase() : raw.toUpperCase();

    if (!validateSNFormat(sn)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('SN格式不正确:\n${formatSNForDisplay(sn)}'),
        backgroundColor: AppColors.errorLight,
        duration: const Duration(seconds: 3),
      ));
      return;
    }

    if (!validateCheckDigitOnly(sn)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('⚠ 校验码不匹配: ${formatSNForDisplay(sn)}\n请确认 SN 是否正确'),
        backgroundColor: const Color(0xFFF59E0B),
        duration: const Duration(seconds: 4),
      ));
    }

    _bindDevice(sn);
  }

  bool _isOpenNetwork(WifiNetwork net) {
    final cap = net.capabilities?.toUpperCase() ?? '';
    return !cap.contains('WPA') && !cap.contains('WEP') && !cap.contains('EAP');
  }

  Future<void> _scanCSInvWiFi() async {
    setState(() { _wifiScanning = true; _csInvNetworks = []; });
    try {
      await WiFiForIoTPlugin.forceWifiUsage(true);
      final networks = await WiFiForIoTPlugin.loadWifiList();
      final filtered = networks.where((n) {
        final ssid = n.ssid ?? '';
        return ssid.toUpperCase().startsWith('CS_INV') || ssid.toUpperCase().startsWith('CS-INV');
      }).toList();
      filtered.sort((a, b) => (b.level ?? -100).compareTo(a.level ?? -100));
      setState(() { _csInvNetworks = filtered; _wifiScanning = false; });
    } catch (e) {
      setState(() => _wifiScanning = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('扫描失败: $e')));
    }
  }

  Future<void> _connectToAp(WifiNetwork network) async {
    setState(() {
      _selectedDeviceAp = network;
      _provisionStatus = '正在连接 ${network.ssid}...';
      _provisionStep = 1;
      _nearbyWifiList = [];
      _workingSsidController.clear();
      _workingPasswordController.clear();
    });

    try {
      final ssid = network.ssid ?? '';
      final connected = await WiFiForIoTPlugin.connect(ssid,
        password: null,
        security: _isOpenNetwork(network) ? NetworkSecurity.NONE : NetworkSecurity.WPA,
        joinOnce: true,
      );

      if (connected) {
        await Future.delayed(const Duration(seconds: 1));
        setState(() {
          _provisionStatus = '已连接到 $ssid';
          _provisionStep = 2;
        });
        _scanDeviceWiFi();
      } else {
        setState(() => _provisionStatus = '连接 $ssid 失败，请重试');
      }
    } catch (e) {
      setState(() => _provisionStatus = '连接失败: $e');
    }
  }

  Future<void> _scanDeviceWiFi() async {
    setState(() { _scanningNearbyWifi = true; _provisionStatus = '正在通过设备扫描 WiFi...'; });
    try {
      final list = await _provisionService.scanWiFi();
      setState(() {
        _nearbyWifiList = list;
        _scanningNearbyWifi = false;
        _provisionStatus = list.isEmpty ? '设备未扫描到 WiFi，请手动输入' : '发现 ${list.length} 个 WiFi';
        _provisionStep = 2;
      });
    } catch (_) {
      setState(() {
        _scanningNearbyWifi = false;
        _provisionStatus = 'WiFi 扫描失败，请手动输入';
      });
    }
  }

  void _pickWiFi(ScanResult wifi) {
    _workingSsidController.text = wifi.ssid;
    _workingPasswordController.clear();
    _showPassword = false;
    setState(() => _provisionStatus = '已选择 ${wifi.ssid}，请输入密码');
  }

  Future<void> _sendProvisionConfig() async {
    final ssid = _workingSsidController.text.trim();
    final password = _workingPasswordController.text.trim();
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入WiFi名称')));
      return;
    }
    setState(() { _provisioning = true; _provisionStatus = '正在发送配网信息...'; _provisionOk = false; });

    var result = await _provisionService.configure(ssid, password);
    if (!result.success) result = await _provisionService.configureCompat(ssid, password);

    if (result.success) {
      setState(() { _provisionStatus = '✅ 配网成功！设备正在连接 WiFi...'; _provisionStep = 3; });
      await Future.delayed(const Duration(seconds: 2));
      for (int i = 0; i < 15; i++) {
        final status = await _provisionService.checkStatus();
        if (status.success) {
          setState(() {
            _provisioning = false; _provisionOk = true;
            _provisionStatus = '✅ 配网完成！WiFi: ${status.ssid}  IP: ${status.ip}';
          });
          _onSoftApProvisionSuccess();
          return;
        }
        if (mounted) setState(() => _provisionStatus = '等待设备连接... (${i + 1}/15)');
        await Future.delayed(const Duration(seconds: 2));
      }
      setState(() { _provisioning = false; _provisionStatus = '✅ 配置已发送，设备即将重启连接'; _provisionOk = true; });
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ 设备已连接到WiFi并上线'),
        backgroundColor: AppColors.successLight,
        duration: Duration(seconds: 3),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ 已切换回原WiFi，进入远程模式'),
          backgroundColor: AppColors.successLight,
        ));
      }
    }
  }

  Future<void> _startSmartConfig() async {
    final ssid = _scSsidController.text.trim();
    final password = _scPasswordController.text.trim();
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入WiFi名称')));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('SmartConfig 配网超时或失败，请重试'),
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('✅ SmartConfig 配网成功！'),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ 设备已上线'),
        backgroundColor: AppColors.successLight,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('配网成功，等待设备上线中...'),
        backgroundColor: Color(0xFFF59E0B),
        duration: Duration(seconds: 3),
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
        title: const Text('添加设备'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: '扫码', icon: Icon(Icons.qr_code_scanner, size: 20)),
            Tab(text: '手动输入', icon: Icon(Icons.edit, size: 20)),
            Tab(text: '配网', icon: Icon(Icons.wifi, size: 20)),
          ],
        ),
      ),
      body: BlocConsumer<DeviceBloc, DeviceState>(
        listener: (context, state) {
          if (state is DeviceBindSuccess) {
            if (widget.stationId != null) {
              context.read<StationBloc>().add(StationDetailRequested(stationId: widget.stationId!));
            }
            setState(() {
              _sessionBoundCount++;
              _bindSuccess = true;
              _scanning = false;
            });
            _addToScanHistory(_lastScanned, true);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('✅ 设备添加成功 (本次已绑定 $_sessionBoundCount 台)'),
              backgroundColor: AppColors.successLight,
            ));
          } else if (state is DeviceError) {
            _scanning = false;
            _lastScanned = '';
            _scannedPin = '';
            _addToScanHistory(_lastScanned, false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.errorLight,
            ));
          }
        },
        builder: (context, state) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildScanTab(state),
              _buildManualTab(state),
              _buildProvisionTab(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScanTab(DeviceState state) {
    return Column(
      children: [
        if (_sessionBoundCount > 0)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            color: const Color(0xFFECFDF5),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.successLight, size: 18),
                SizedBox(width: 6.w),
                Text('本次已绑定 $_sessionBoundCount 台设备',
                  style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: const Color(0xFF065F46))),
              ],
            ),
          ),
        Expanded(
          flex: 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _cameraController, onDetect: _onDetect),
              Center(
                child: Container(
                  width: 220.w, height: 220.w,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 2),
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                ),
              ),
              if (_scanning || state is DeviceLoading)
                Container(color: Colors.black54,
                  child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('正在添加设备...', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ]))),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.all(16.w),
          color: Colors.white,
          child: Column(
            children: [
              if (_bindSuccess) ...[
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _continueScanning,
                      icon: const Icon(Icons.qr_code_scanner, size: 20),
                      label: const Text('继续扫码', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text('完成', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.successLight,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                    ),
                  ),
                ]),
                SizedBox(height: 12.h),
              ] else ...[
                if (_lastScanned.isNotEmpty) ...[
                  Text('SN: ${formatSNForDisplay(_lastScanned)}',
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  if (_scannedPin.isNotEmpty)
                    Padding(padding: EdgeInsets.only(top: 4.h),
                      child: Text('PIN: $_scannedPin',
                        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.successLight))),
                ] else
                  Text('将 SN 二维码对准扫描框',
                    style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
              ],
              SizedBox(height: 8.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _actionChip(Icons.flash_on, '闪光灯', () => _cameraController?.toggleTorch()),
                  SizedBox(width: 12.w),
                  _actionChip(Icons.flip_camera_android, '翻转', () => _cameraController?.switchCamera()),
                  SizedBox(width: 12.w),
                  GestureDetector(
                    onTap: () => setState(() => _autoFlash = !_autoFlash),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: _autoFlash ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surfaceHover,
                        borderRadius: BorderRadius.circular(20.r),
                        border: _autoFlash ? Border.all(color: AppColors.primary.withValues(alpha: 0.3)) : null,
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.auto_fix_high, size: 16.sp, color: _autoFlash ? AppColors.primary : AppColors.textSecondary),
                        SizedBox(width: 4.w),
                        Text('自动闪光', style: TextStyle(fontSize: 12.sp, color: _autoFlash ? AppColors.primary : AppColors.textSecondary)),
                      ]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_scanHistory.isNotEmpty)
          Container(
            constraints: BoxConstraints(maxHeight: 160.h),
            color: const Color(0xFFF9FAFB),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
                  child: Text('扫码记录', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    itemCount: _scanHistory.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final entry = _scanHistory[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 2.h),
                        leading: Icon(
                          entry.success ? Icons.check_circle : Icons.error,
                          size: 18,
                          color: entry.success ? AppColors.successLight : AppColors.errorLight,
                        ),
                        title: Text(formatSNForDisplay(entry.sn),
                          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                        trailing: Text(entry.success ? '绑定成功' : '绑定失败',
                          style: TextStyle(fontSize: 11.sp, color: entry.success ? AppColors.successLight : AppColors.errorLight)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(20.r)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16.sp, color: AppColors.textSecondary),
          SizedBox(width: 4.w),
          Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _buildManualTab(DeviceState state) {
    return ListView(padding: EdgeInsets.all(20.w), children: [
      Text('手动输入设备序列号', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
      SizedBox(height: 8.h),
      Text('SN格式: 16位辰烁标准编码 (如 H1CNA0013A000011)', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
      SizedBox(height: 4.h),
      Text('也支持输入 SN:xxxxxxx PIN:xxxxx 格式', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
      SizedBox(height: 16.h),
      TextField(
        controller: _snController,
        decoration: InputDecoration(
          labelText: '设备SN', hintText: '请输入16位设备序列号',
          prefixIcon: const Icon(Icons.devices, color: AppColors.textHint),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        ),
      ),
      SizedBox(height: 20.h),
      SizedBox(width: double.infinity, height: 48.h,
        child: ElevatedButton(
          onPressed: state is DeviceLoading ? null : _manualBind,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
          child: state is DeviceLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('绑定设备', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }

  Widget _buildProvisionTab() {
    return ListView(
      padding: EdgeInsets.all(20.w),
      children: [
        _buildModeSwitch(),
        SizedBox(height: 20.h),
        if (_provisionMode == _ProvisionMode.softap)
          _buildSoftApSection()
        else
          _buildSmartConfigSection(),
      ],
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
            onTap: () => setState(() => _provisionMode = _ProvisionMode.softap),
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
                Text('SoftAP',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600,
                    color: _provisionMode == _ProvisionMode.softap ? Colors.white : AppColors.textSecondary)),
              ]),
            ),
          ),
        ),
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
                Text('SmartConfig',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600,
                    color: _provisionMode == _ProvisionMode.smartconfig ? Colors.white : AppColors.textSecondary)),
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
        _stepIndicator(1, isStep0 ? '连接设备' : '✓', _provisionStep >= 1),
        Expanded(child: Container(height: 2, color: _provisionStep >= 2 ? AppColors.successLight : const Color(0xFFE5E7EB))),
        _stepIndicator(2, _provisionStep >= 2 ? '✓' : '2', _provisionStep >= 2),
        Expanded(child: Container(height: 2, color: _provisionStep >= 3 ? AppColors.successLight : const Color(0xFFE5E7EB))),
        _stepIndicator(3, _provisionOk ? '✓' : '3', _provisionOk),
      ]),
      SizedBox(height: 8.h),
      Row(children: [
        SizedBox(width: 30.w, child: Text('连接设备热点', textAlign: TextAlign.center, style: TextStyle(fontSize: 9.sp, color: _provisionStep>=1?AppColors.successLight:AppColors.textHint))),
        Expanded(child: Container()),
        SizedBox(width: 30.w, child: Text('选择WiFi', textAlign: TextAlign.center, style: TextStyle(fontSize: 9.sp, color: _provisionStep>=2?AppColors.successLight:AppColors.textHint))),
        Expanded(child: Container()),
        SizedBox(width: 30.w, child: Text('完成', textAlign: TextAlign.center, style: TextStyle(fontSize: 9.sp, color: _provisionOk?AppColors.successLight:AppColors.textHint))),
      ]),
      SizedBox(height: 24.h),

      if (isStep0) ...[
        SizedBox(width: double.infinity, height: 46.h,
          child: ElevatedButton.icon(
            onPressed: _wifiScanning ? null : _scanCSInvWiFi,
            icon: _wifiScanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.wifi_find, size: 22),
            label: Text(_wifiScanning ? '扫描中...' : ' 扫描附近逆变器', style: const TextStyle(fontSize: 15)),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r))),
          ),
        ),

        if (_csInvNetworks.isNotEmpty) ...[
          SizedBox(height: 10.h),
          Text('发现 ${_csInvNetworks.length} 个逆变器设备', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
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
          Padding(padding: EdgeInsets.only(top: 16.h), child: Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12.r)),
            child: Column(children: [
              Icon(Icons.wifi_off, size: 40.sp, color: AppColors.textHint),
              SizedBox(height: 10.h),
              Text('未发现逆变器热点', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
              SizedBox(height: 4.h),
              Text('请确保设备已上电', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
            ]),
          )),
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
            Expanded(child: Text('已连接 ${_selectedDeviceAp?.ssid ?? ''}', style: TextStyle(fontSize: 13.sp, color: const Color(0xFF065F46)))),
            GestureDetector(onTap: _resetProvision, child: Text('断开', style: TextStyle(fontSize: 12.sp, color: AppColors.errorLight))),
          ])),
      ],

      if (deviceConnected) ...[
        SizedBox(width: double.infinity, height: 44.h,
          child: OutlinedButton.icon(
            onPressed: _scanningNearbyWifi ? null : _scanDeviceWiFi,
            icon: _scanningNearbyWifi
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering, size: 20),
            label: Text(_scanningNearbyWifi ? '扫描中...' : '📡 扫描附近可用 WiFi', style: const TextStyle(fontSize: 14)),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              side: const BorderSide(color: AppColors.primary)),
          ),
        ),

        SizedBox(height: 8.h),

        if (_nearbyWifiList.isNotEmpty) ...[
          Text('点击 WiFi 名称自动填入', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
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
            labelText: 'WiFi 名称', hintText: '点击上方 WiFi 或手动输入',
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
            labelText: 'WiFi 密码', hintText: '请输入 WiFi 密码',
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
            label: Text(_provisioning ? '配网中...' : '⚡ 发送配网信息', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
    final statusText = switch (_scStatus) {
      SmartConfigStatus.idle => '就绪',
      SmartConfigStatus.scanning => '扫描中...',
      SmartConfigStatus.configuring => '正在发送配网信息...',
      SmartConfigStatus.success => '✅ 配网成功',
      SmartConfigStatus.timeout => '⏱ 配网超时',
      SmartConfigStatus.error => '❌ 配网失败',
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
            'SmartConfig 模式：手机和设备需在同一 WiFi 环境下，通过广播发送 WiFi 信息给设备',
            style: TextStyle(fontSize: 12.sp, color: AppColors.textPrimary),
          )),
        ]),
      ),

      TextField(
        controller: _scSsidController,
        enabled: !_scConfiguring,
        decoration: InputDecoration(
          labelText: 'WiFi 名称',
          hintText: '请输入要配网的 WiFi 名称',
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
          labelText: 'WiFi 密码',
          hintText: '请输入 WiFi 密码',
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
              label: const Text('停止配网', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
            label: Text(_scStatus == SmartConfigStatus.success ? '配网成功' : '开始配网',
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

  void _continueScanning() {
    setState(() {
      _lastScanned = '';
      _scannedPin = '';
      _scanning = false;
      _bindSuccess = false;
    });
  }

  static const String _scanHistoryKey = 'scan_history';

  Future<void> _loadScanHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_scanHistoryKey);
      if (jsonStr != null) {
        final list = jsonDecode(jsonStr) as List;
        setState(() {
          _scanHistory = list.map((e) => _ScanHistoryEntry.fromJson(e as Map<String, dynamic>)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveScanHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = _scanHistory.length > 10 ? _scanHistory.sublist(_scanHistory.length - 10) : _scanHistory;
      final jsonStr = jsonEncode(trimmed.map((e) => e.toJson()).toList());
      await prefs.setString(_scanHistoryKey, jsonStr);
    } catch (_) {}
  }

  void _addToScanHistory(String sn, bool success) {
    if (sn.isEmpty) return;
    setState(() {
      _scanHistory.add(_ScanHistoryEntry(sn: sn, success: success, time: DateTime.now()));
      if (_scanHistory.length > 10) {
        _scanHistory = _scanHistory.sublist(_scanHistory.length - 10);
      }
    });
    _saveScanHistory();
  }
}

class _ScanHistoryEntry {
  final String sn;
  final bool success;
  final DateTime time;

  _ScanHistoryEntry({required this.sn, required this.success, required this.time});

  Map<String, dynamic> toJson() => {
    'sn': sn,
    'success': success,
    'time': time.toIso8601String(),
  };

  factory _ScanHistoryEntry.fromJson(Map<String, dynamic> json) => _ScanHistoryEntry(
    sn: json['sn'] as String,
    success: json['success'] as bool,
    time: DateTime.parse(json['time'] as String),
  );
}
