import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/core/services/provision_service.dart';
import 'package:inv_app/core/utils/sn_utils.dart';

class AddDevicePage extends StatefulWidget {
  final int? stationId;

  const AddDevicePage({super.key, this.stationId});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> with SingleTickerProviderStateMixin {
  final _snController = TextEditingController();
  final _provisionService = ProvisionService();

  late TabController _tabController;
  bool _scanning = false;
  MobileScannerController? _cameraController;
  String _lastScanned = '';
  String _scannedPin = '';

  // Provisioning
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cameraController = MobileScannerController();
  }

  @override
  void dispose() {
    _snController.dispose();
    _workingSsidController.dispose();
    _workingPasswordController.dispose();
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
          backgroundColor: const Color(0xFFEF4444),
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
          backgroundColor: const Color(0xFFEF4444),
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
        backgroundColor: const Color(0xFFEF4444),
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

  // ==================== Provisioning ====================

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
          return;
        }
        if (mounted) setState(() => _provisionStatus = '等待设备连接... (${i + 1}/15)');
        await Future.delayed(const Duration(seconds: 2));
      }
      setState(() { _provisioning = false; _provisionStatus = '✅ 配置已发送，设备即将重启连接'; _provisionOk = true; });
    } else {
      setState(() { _provisioning = false; _provisionStatus = '❌ ${result.message}'; });
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
          labelColor: const Color(0xFF5B9BD5),
          unselectedLabelColor: const Color(0xFF9CA3AF),
          indicatorColor: const Color(0xFF5B9BD5),
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
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ 设备添加成功'),
              backgroundColor: Color(0xFF10B981),
            ));
            context.pop();
          } else if (state is DeviceError) {
            _scanning = false;
            _lastScanned = '';
            _scannedPin = '';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: const Color(0xFFEF4444),
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
                    border: Border.all(color: const Color(0xFF5B9BD5), width: 2),
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
        Container(padding: EdgeInsets.all(16.w), color: Colors.white,
          child: Column(children: [
            if (_lastScanned.isNotEmpty) ...[
              Text('SN: ${formatSNForDisplay(_lastScanned)}',
                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: const Color(0xFF1F2937))),
              if (_scannedPin.isNotEmpty)
                Padding(padding: EdgeInsets.only(top: 4.h),
                  child: Text('PIN: $_scannedPin',
                    style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: const Color(0xFF10B981)))),
            ] else
              Text('将 SN 二维码对准扫描框',
                style: TextStyle(fontSize: 14.sp, color: const Color(0xFF6B7280))),
            SizedBox(height: 8.h),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _actionChip(Icons.flash_on, '闪光灯', () => _cameraController?.toggleTorch()),
              SizedBox(width: 16.w),
              _actionChip(Icons.flip_camera_android, '翻转', () => _cameraController?.switchCamera()),
            ]),
          ])),
      ],
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(20.r)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16.sp, color: const Color(0xFF6B7280)),
          SizedBox(width: 4.w),
          Text(label, style: TextStyle(fontSize: 12.sp, color: const Color(0xFF6B7280))),
        ]),
      ),
    );
  }

  Widget _buildManualTab(DeviceState state) {
    return ListView(padding: EdgeInsets.all(20.w), children: [
      Text('手动输入设备序列号', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
      SizedBox(height: 8.h),
      Text('SN格式: 16位辰烁标准编码 (如 H1CNA0013A000011)', style: TextStyle(fontSize: 11.sp, color: const Color(0xFF9CA3AF))),
      SizedBox(height: 4.h),
      Text('也支持输入 SN:xxxxxxx PIN:xxxxx 格式', style: TextStyle(fontSize: 11.sp, color: const Color(0xFF9CA3AF))),
      SizedBox(height: 16.h),
      TextField(
        controller: _snController,
        decoration: InputDecoration(
          labelText: '设备SN', hintText: '请输入16位设备序列号',
          prefixIcon: const Icon(Icons.devices, color: Color(0xFF9CA3AF)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: Color(0xFF5B9BD5), width: 1.5)),
        ),
      ),
      SizedBox(height: 20.h),
      SizedBox(width: double.infinity, height: 48.h,
        child: ElevatedButton(
          onPressed: state is DeviceLoading ? null : _manualBind,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5B9BD5), foregroundColor: Colors.white,
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
    final deviceConnected = _provisionStep >= 2;
    final isStep0 = !deviceConnected;

    return ListView(padding: EdgeInsets.all(20.w), children: [
      Row(children: [
        _stepIndicator(1, isStep0 ? '连接设备' : '✓', _provisionStep >= 1),
        Expanded(child: Container(height: 2, color: _provisionStep >= 2 ? const Color(0xFF10B981) : const Color(0xFFE5E7EB))),
        _stepIndicator(2, _provisionStep >= 2 ? '✓' : '2', _provisionStep >= 2),
        Expanded(child: Container(height: 2, color: _provisionStep >= 3 ? const Color(0xFF10B981) : const Color(0xFFE5E7EB))),
        _stepIndicator(3, _provisionOk ? '✓' : '3', _provisionOk),
      ]),
      SizedBox(height: 8.h),
      Row(children: [
        SizedBox(width: 30.w, child: Text('连接设备热点', textAlign: TextAlign.center, style: TextStyle(fontSize: 9.sp, color: _provisionStep>=1?const Color(0xFF10B981):const Color(0xFF9CA3AF)))),
        Expanded(child: Container()),
        SizedBox(width: 30.w, child: Text('选择WiFi', textAlign: TextAlign.center, style: TextStyle(fontSize: 9.sp, color: _provisionStep>=2?const Color(0xFF10B981):const Color(0xFF9CA3AF)))),
        Expanded(child: Container()),
        SizedBox(width: 30.w, child: Text('完成', textAlign: TextAlign.center, style: TextStyle(fontSize: 9.sp, color: _provisionOk?const Color(0xFF10B981):const Color(0xFF9CA3AF)))),
      ]),
      SizedBox(height: 24.h),

      // ---- Step 1: Scan & pick device AP ----
      if (isStep0) ...[
        SizedBox(width: double.infinity, height: 46.h,
          child: ElevatedButton.icon(
            onPressed: _wifiScanning ? null : _scanCSInvWiFi,
            icon: _wifiScanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.wifi_find, size: 22),
            label: Text(_wifiScanning ? '扫描中...' : ' 扫描附近逆变器', style: const TextStyle(fontSize: 15)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5B9BD5), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r))),
          ),
        ),

        if (_csInvNetworks.isNotEmpty) ...[
          SizedBox(height: 10.h),
          Text('发现 ${_csInvNetworks.length} 个逆变器设备', style: TextStyle(fontSize: 12.sp, color: const Color(0xFF9CA3AF))),
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
                  child: const Icon(Icons.solar_power, color: Color(0xFF5B9BD5), size: 22)),
                title: Text(ssid, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                subtitle: Text('$sig $rssi dBm', style: TextStyle(fontSize: 11.sp, color: const Color(0xFF9CA3AF))),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFD1D5DB)),
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
              Icon(Icons.wifi_off, size: 40.sp, color: const Color(0xFFD1D5DB)),
              SizedBox(height: 10.h),
              Text('未发现逆变器热点', style: TextStyle(fontSize: 14.sp, color: const Color(0xFF9CA3AF))),
              SizedBox(height: 4.h),
              Text('请确保设备已上电', style: TextStyle(fontSize: 11.sp, color: const Color(0xFFD1D5DB))),
            ]),
          )),
      ],

      // ---- Step 2: Scan nearby WiFi via device ----
      if (_provisionStep == 1) ...[
        Container(padding: EdgeInsets.all(16.w), decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12.r)),
          child: Row(children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12.w),
            Expanded(child: Text(_provisionStatus, style: TextStyle(fontSize: 13.sp, color: const Color(0xFF374151)))),
          ])),
      ],

      if (deviceConnected) ...[
        Container(padding: EdgeInsets.all(12.w), margin: EdgeInsets.only(bottom: 16.h),
          decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10.r)),
          child: Row(children: [
            const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
            SizedBox(width: 8.w),
            Expanded(child: Text('已连接 ${_selectedDeviceAp?.ssid ?? ''}', style: TextStyle(fontSize: 13.sp, color: const Color(0xFF065F46)))),
            GestureDetector(onTap: _resetProvision, child: Text('断开', style: TextStyle(fontSize: 12.sp, color: const Color(0xFFEF4444)))),
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
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF5B9BD5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              side: const BorderSide(color: Color(0xFF5B9BD5))),
          ),
        ),

        SizedBox(height: 8.h),

        // WiFi list
        if (_nearbyWifiList.isNotEmpty) ...[
          Text('点击 WiFi 名称自动填入', style: TextStyle(fontSize: 11.sp, color: const Color(0xFF9CA3AF))),
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
                  leading: Icon(w.encrypted ? Icons.lock_outline : Icons.wifi, size: 20, color: selected ? const Color(0xFF5B9BD5) : const Color(0xFF9CA3AF)),
                  title: Text(w.ssid, style: TextStyle(fontSize: 13.sp, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: const Color(0xFF1F2937))),
                  trailing: Text('$sig ${w.rssi}dBm', style: TextStyle(fontSize: 10.sp, color: const Color(0xFF9CA3AF))),
                  tileColor: selected ? const Color(0xFFEFF6FF) : null,
                  dense: true,
                  onTap: () => _pickWiFi(w),
                );
              },
            ),
          ),
          SizedBox(height: 16.h),
        ],

        // Manual SSID + Password
        TextField(
          controller: _workingSsidController,
          decoration: InputDecoration(
            labelText: 'WiFi 名称', hintText: '点击上方 WiFi 或手动输入',
            prefixIcon: const Icon(Icons.wifi, color: Color(0xFF5B9BD5)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r),
              borderSide: const BorderSide(color: Color(0xFF5B9BD5), width: 1.5)),
          ),
        ),
        SizedBox(height: 12.h),
        TextField(
          controller: _workingPasswordController,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            labelText: 'WiFi 密码', hintText: '请输入 WiFi 密码',
            prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF9CA3AF)),
            suffixIcon: IconButton(
              icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF9CA3AF)),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r),
              borderSide: const BorderSide(color: Color(0xFF5B9BD5), width: 1.5)),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white,
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
              size: 20.sp, color: _provisionOk ? const Color(0xFF10B981) : (_provisionStatus.contains('❌') ? const Color(0xFFEF4444) : const Color(0xFF5B9BD5))),
            SizedBox(width: 10.w),
            Expanded(child: Text(_provisionStatus, style: TextStyle(fontSize: 13.sp, color: const Color(0xFF374151)))),
          ])),
      ],

      SizedBox(height: 60.h),
    ]);
  }

  Widget _stepIndicator(int num, String label, bool active) {
    return Container(
      width: 30.w, height: 30.w,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF10B981) : const Color(0xFFE5E7EB),
        shape: BoxShape.circle,
      ),
      child: Center(child: Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: active ? Colors.white : const Color(0xFF9CA3AF)))),
    );
  }
}
