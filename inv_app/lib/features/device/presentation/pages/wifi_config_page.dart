import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:inv_app/core/services/provision_service.dart';
import 'package:inv_app/core/services/ble_provisioning_service.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/wifi_scan_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/widgets/wifi_switch_dialog.dart';
import 'package:inv_app/core/widgets/wifi_enable_dialog.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/device/presentation/services/soft_ap_provision_runner.dart';
import 'package:inv_app/features/device/presentation/widgets/wifi_provision_widgets.dart';
import 'package:inv_app/l10n/app_localizations.dart';

part 'wifi_config_sections.dart';

class WifiConfigPage extends StatefulWidget {
  const WifiConfigPage({super.key});

  @override
  State<WifiConfigPage> createState() => _WifiConfigPageState();
}

class _WifiConfigPageState extends State<WifiConfigPage> {
  final _provisionService = ProvisionService();
  final _bleProvisioningService = BleProvisioningService();
  final _connectionModeService = getIt<ConnectionModeService>();
  late final SoftApProvisionRunner _softApProvisionRunner;

  WifiProvisionMode _provisionMode = WifiProvisionMode.ble;

  bool _wifiScanning = false;
  List<ScannedWifiNetwork> _csInvNetworks = [];
  ScannedWifiNetwork? _selectedDeviceAp;

  bool _scanningNearbyWifi = false;
  List<ScanResult> _nearbyWifiList = [];
  List<ScannedWifiNetwork> _phoneScannedWifi = []; // 手机端扫描的WiFi列表（连接热点前扫描）

  bool _provisioning = false;
  String _provisionStatus = '';
  bool _provisionOk = false;
  int _provisionStep = 0;
  int _wifiOperationId = 0;
  Future<void> _wifiRouteQueue = Future<void>.value();

  final _workingSsidController = TextEditingController();
  final _workingPasswordController = TextEditingController();
  final _pinController = TextEditingController();
  bool _showPassword = false;

  final _scSsidController = TextEditingController();
  final _scPasswordController = TextEditingController();
  BleProvisioningStatus _bleStatus = BleProvisioningStatus.idle;
  StreamSubscription<BleProvisioningStatus>? _bleStatusSub;
  StreamSubscription<List<BleDeviceInfo>>? _bleDevicesSub;
  StreamSubscription<String>? _bleResultSub;
  List<BleDeviceInfo> _bleDevices = [];
  BleDeviceInfo? _selectedBleDevice;
  bool _bleScanning = false;
  bool _bleConnecting = false;
  bool _provisionSuccess = false; // 配网成功状态
  String? _bleErrorMessage; // 配网失败错误消息
  String? _originalSsid;

  @override
  void initState() {
    super.initState();
    _softApProvisionRunner = SoftApProvisionRunner(
      configure: _provisionService.configure,
      checkStatus: _provisionService.checkStatus,
      ensureWifiRoute: () => _setForcedWifiRoute(true),
    );
    _loadCurrentWifiSsid();
    _initBleProvisioning();
    // 自动开始BLE扫描（类似热点配网的自动扫描）
    _startBleScan();
  }

  void _initBleProvisioning() {
    _bleStatusSub = _bleProvisioningService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _bleStatus = status;
          _bleScanning = status == BleProvisioningStatus.scanning;
          _bleConnecting = status == BleProvisioningStatus.connecting ||
              status == BleProvisioningStatus.discoveringServices ||
              status == BleProvisioningStatus.readingDeviceInfo ||
              status == BleProvisioningStatus.subscribingNotifications;
          // 配网失败或回到连接状态时，重置provisioning状态
          if (status == BleProvisioningStatus.bleConnected ||
              status == BleProvisioningStatus.failed ||
              status == BleProvisioningStatus.timeout ||
              status == BleProvisioningStatus.error) {
            _provisioning = false;
          }
        });

        // WiFi配网成功
        if (status == BleProvisioningStatus.wifiConnected) {
          _onBleProvisionSuccess();
        }
      }
    });

    _bleDevicesSub = _bleProvisioningService.devicesStream.listen((devices) {
      if (mounted) {
        setState(() {
          _bleDevices = devices;
        });
      }
    });

    _bleResultSub = _bleProvisioningService.resultStream.listen((result) {
      if (mounted) {
        final message = _localizeBleMessage(result);
        // 仅更新页面内状态展示，不再弹全局 SnackBar（避免与页面状态提示重复，Q3）
        setState(() {
          _bleErrorMessage = message;
        });
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

  /// 在 deactivate 中取消所有流订阅，确保不会有回调在 element 被
  /// deactivated 后触发 setState（framework.dart 断言错误的根因）。
  /// deactivate 在 Navigator pop 时先于 dispose 调用，且 mounted 在
  /// super.deactivate() 后变为 false；在此处取消订阅可封堵 deactivate
  /// 与 dispose 之间的回调窗口。
  @override
  void deactivate() {
    _bleStatusSub?.cancel();
    _bleStatusSub = null;
    _bleDevicesSub?.cancel();
    _bleDevicesSub = null;
    _bleResultSub?.cancel();
    _bleResultSub = null;
    super.deactivate();
  }

  @override
  void dispose() {
    _cancelWifiOperation();
    unawaited(_releaseForcedWifiRoute());
    _workingSsidController.dispose();
    _workingPasswordController.dispose();
    _pinController.dispose();
    _scSsidController.dispose();
    _scPasswordController.dispose();
    _bleProvisioningService.dispose();
    super.dispose();
  }

  bool _isOpenNetwork(ScannedWifiNetwork net) {
    final cap = net.capabilities?.toUpperCase() ?? '';
    return !cap.contains('WPA') && !cap.contains('WEP') && !cap.contains('EAP');
  }

  bool _isDeviceApSsid(String ssid) {
    final normalized = _normalizeSsid(ssid);
    return normalized.startsWith('CS_INV') ||
        normalized.startsWith('CS-INV');
  }

  String _normalizeSsid(String ssid) {
    return ssid.trim().replaceAll('"', '').toUpperCase();
  }

  int _beginWifiOperation() => ++_wifiOperationId;

  void _cancelWifiOperation() {
    _wifiOperationId++;
  }

  bool _isWifiOperationActive(int operationId) {
    return mounted && operationId == _wifiOperationId;
  }

  Future<void> _releaseForcedWifiRoute() async {
    try {
      await _setForcedWifiRoute(false);
    } catch (_) {}
  }

  Future<void> _setForcedWifiRoute(bool force) {
    // Android 原生路由切换无法取消。所有 true/false 串行执行，确保模式切换
    // 或页面退出排入的 false 不会被更早启动、较晚完成的 true 覆盖。
    final operation = _wifiRouteQueue
        .catchError((_) {})
        .then<void>((_) async {
          await WiFiForIoTPlugin.forceWifiUsage(force);
        });
    _wifiRouteQueue = operation;
    return operation;
  }

  Future<bool> _requestWifiPermissions() async {
    // Android 6+ 扫描WiFi列表必须有位置权限，这是系统限制
    final status = await Permission.location.request();
    return status.isGranted || status.isLimited;
  }

  Future<void> _scanCSInvWiFi() async {
    final operationId = _beginWifiOperation();
    setState(() {
      _wifiScanning = true;
      _csInvNetworks = [];
    });
    try {
      final granted = await _requestWifiPermissions();
      if (!_isWifiOperationActive(operationId)) return;
      if (!granted) {
        setState(() => _wifiScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.wifiPermissionHint),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // 请求打开位置服务（Android 11及以下必须开启定位才能扫描WiFi）
      final serviceEnabled = await Permission.location.serviceStatus.isEnabled;
      if (!_isWifiOperationActive(operationId)) return;
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.locationServiceHint),
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() => _wifiScanning = false);
        return;
      }

      // 检查手机 WiFi 是否开启：未开启则引导开启，取消则中止扫描（公共方法，Q1）
      if (!_isWifiOperationActive(operationId)) return;
      final wifiEnabled = await ensureWifiEnabled(context);
      if (!_isWifiOperationActive(operationId)) return;
      if (!wifiEnabled) {
        setState(() => _wifiScanning = false);
        return;
      }

      // 关键改进：先关闭WiFi强制使用，让系统执行一次新的WiFi扫描
      // Android 系统有4次/2分钟的扫描限制，先关闭再打开可以触发新扫描
      await _setForcedWifiRoute(false);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_isWifiOperationActive(operationId)) return;

      // 多次读取以获取最新结果
      List<ScannedWifiNetwork> allNetworks = [];
      for (int i = 0; i < 3; i++) {
        final networks = await scanWifiNetworks(triggerScan: i == 0);
        if (!_isWifiOperationActive(operationId)) return;
        allNetworks.addAll(networks);
        if (i < 2) {
          await Future.delayed(const Duration(milliseconds: 800));
          if (!_isWifiOperationActive(operationId)) return;
        }
      }

      // 去重并按信号强度排序
      final ssidSet = <String>{};
      final filtered = <ScannedWifiNetwork>[];
      for (final n in allNetworks) {
        final ssid = n.ssid ?? '';
        if (ssid.isEmpty) continue;
        if (_isDeviceApSsid(ssid)) {
          if (!ssidSet.contains(ssid)) {
            ssidSet.add(ssid);
            filtered.add(n);
          }
        }
      }
      filtered.sort((a, b) => (b.level ?? -100).compareTo(a.level ?? -100));

      // 同时扫描所有附近WiFi（用于后续配网选择）
      await _scanAllNearbyWifi(operationId);
      if (!_isWifiOperationActive(operationId)) return;

      setState(() {
        _csInvNetworks = filtered;
        _wifiScanning = false;
      });
    } catch (e) {
      if (!_isWifiOperationActive(operationId)) return;
      setState(() => _wifiScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context)!.scanFailed}: $e'),
        ),
      );
    }
  }

  /// 手机端扫描所有附近WiFi（在连接设备热点之前调用，缓存结果）
  Future<void> _scanAllNearbyWifi(int operationId) async {
    try {
      await _setForcedWifiRoute(false);
      await Future.delayed(const Duration(milliseconds: 300));
      if (!_isWifiOperationActive(operationId)) return;
      final networks = await scanWifiNetworks();
      if (!_isWifiOperationActive(operationId)) return;
      // 过滤掉设备热点本身和无名称的
      _phoneScannedWifi = networks.where((n) {
        final ssid = n.ssid ?? '';
        if (ssid.isEmpty) return false;
        final upper = ssid.toUpperCase();
        return !_isDeviceApSsid(upper);
      }).toList();
      _phoneScannedWifi
          .sort((a, b) => (b.level ?? -100).compareTo(a.level ?? -100));
    } catch (_) {}
  }

  Future<void> _connectToAp(ScannedWifiNetwork network) async {
    if (_provisionStep == 1) return;
    final operationId = _beginWifiOperation();
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _selectedDeviceAp = network;
      _provisionStatus =
          l10n.connectingSsid(network.ssid ?? '');
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
        connected = await WiFiForIoTPlugin.connect(
          ssid,
          password: null,
          security: _isOpenNetwork(network)
              ? NetworkSecurity.NONE
              : NetworkSecurity.WPA,
          joinOnce: true,
        );
        if (!_isWifiOperationActive(operationId)) return;
        if (connected) break;
        if (attempt < 2) {
          setState(
            () => _provisionStatus =
                '${l10n.connectingSsid(ssid)} (${attempt + 2}/3)',
          );
          await Future.delayed(const Duration(seconds: 1));
          if (!_isWifiOperationActive(operationId)) return;
        }
      }

      if (connected) {
        setState(
          () => _provisionStatus =
              l10n.waitingStableConnection,
        );

        // 关键：强制HTTP请求走WiFi而不是移动数据
        await _setForcedWifiRoute(true);
        if (!_isWifiOperationActive(operationId)) return;

        // 等待连接稳定，热点分配IP需要时间
        await Future.delayed(const Duration(seconds: 3));
        if (!_isWifiOperationActive(operationId)) return;

        // 验证确实连上了设备热点（增加重试检查）
        String? currentSsid;
        for (int i = 0; i < 3; i++) {
          currentSsid = await WiFiForIoTPlugin.getSSID();
          if (!_isWifiOperationActive(operationId)) return;
          if (currentSsid != null &&
              _normalizeSsid(currentSsid) == _normalizeSsid(ssid)) {
            break;
          }
          await Future.delayed(const Duration(seconds: 1));
          if (!_isWifiOperationActive(operationId)) return;
        }

        if (currentSsid == null ||
            _normalizeSsid(currentSsid) != _normalizeSsid(ssid)) {
          _showApConnectionFailure(l10n.noDeviceHotspotRetry);
          return;
        }

        setState(() {
          _provisionStatus =
              l10n.connectedScanning(ssid);
          _provisionStep = 2;
        });
        // 使用手机端已缓存的WiFi列表，不再通过设备扫描
        _usePhoneScannedWifi();
      } else {
        _showApConnectionFailure(l10n.connectionSsidFailed(ssid));
      }
    } catch (e) {
      if (!_isWifiOperationActive(operationId)) return;
      _showApConnectionFailure('${l10n.connectionFailed}: $e');
    }
  }

  void _showApConnectionFailure(String message) {
    unawaited(_releaseForcedWifiRoute());
    setState(() {
      _selectedDeviceAp = null;
      _provisionStep = 0;
      _provisionStatus = message;
    });
  }

  /// 使用手机端扫描的WiFi列表（连接热点前已缓存，无需再通过设备扫描）
  void _usePhoneScannedWifi() {
    setState(() {
      _nearbyWifiList = _phoneScannedWifi
          .map(
            (n) => ScanResult(
              ssid: n.ssid ?? '',
              rssi: n.level ?? -100,
              encrypted: !_isOpenNetwork(n),
            ),
          )
          .toList();
      _scanningNearbyWifi = false;
      _provisionStatus = _nearbyWifiList.isEmpty
          ? AppLocalizations.of(context)!.noWifiFoundInputManually
          : AppLocalizations.of(context)!
              .foundNWifi('${_nearbyWifiList.length}');
      _provisionStep = 2;
    });
  }

  /// 重新扫描附近 WiFi（手机端，在连接设备热点后临时切回普通模式扫描）
  Future<void> _rescanNearbyWifiFromPhone() async {
    final operationId = _beginWifiOperation();
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _scanningNearbyWifi = true;
    });
    try {
      // 扫描前检查位置权限（Android 6+ 扫描 WiFi 列表必须有位置权限，系统限制）
      final granted = await _requestWifiPermissions();
      if (!_isWifiOperationActive(operationId)) return;
      if (!granted) {
        setState(() => _scanningNearbyWifi = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.wifiPermissionHint),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
  
      // 请求打开位置服务（Android 11 及以下必须开启定位才能扫描 WiFi）
      final serviceEnabled = await Permission.location.serviceStatus.isEnabled;
      if (!_isWifiOperationActive(operationId)) return;
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.locationServiceHint),
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() => _scanningNearbyWifi = false);
        return;
      }
  
      // 检查手机 WiFi 是否开启：未开启则引导开启，取消则中止扫描（公共方法，Q1）
      if (!_isWifiOperationActive(operationId)) return;
      final wifiEnabled = await ensureWifiEnabled(context);
      if (!_isWifiOperationActive(operationId)) return;
      if (!wifiEnabled) {
        setState(() => _scanningNearbyWifi = false);
        return;
      }
  
      // 临时切回普通 WiFi 模式以执行扫描
      await _setForcedWifiRoute(false);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_isWifiOperationActive(operationId)) return;

      List<ScannedWifiNetwork> networks = [];
      for (int i = 0; i < 2; i++) {
        final result = await scanWifiNetworks(triggerScan: i == 0);
        if (!_isWifiOperationActive(operationId)) return;
        networks.addAll(result);
        if (i < 1) {
          await Future.delayed(const Duration(milliseconds: 600));
          if (!_isWifiOperationActive(operationId)) return;
        }
      }

      // 过滤掉设备热点
      final filtered = networks.where((n) {
        final ssid = n.ssid ?? '';
        if (ssid.isEmpty) return false;
        final upper = ssid.toUpperCase();
        return !_isDeviceApSsid(upper);
      }).toList();
      filtered.sort((a, b) => (b.level ?? -100).compareTo(a.level ?? -100));

      // 去重
      final seen = <String>{};
      final unique = <ScannedWifiNetwork>[];
      for (final n in filtered) {
        final ssid = n.ssid ?? '';
        if (!seen.contains(ssid)) {
          seen.add(ssid);
          unique.add(n);
        }
      }

      // 切回WiFi强制使用模式
      await _setForcedWifiRoute(true);
      if (!_isWifiOperationActive(operationId)) return;

      setState(() {
        _nearbyWifiList = unique
            .map(
              (n) => ScanResult(
                ssid: n.ssid ?? '',
                rssi: n.level ?? -100,
                encrypted: !_isOpenNetwork(n),
              ),
            )
            .toList();
        _scanningNearbyWifi = false;
        _provisionStatus = _nearbyWifiList.isEmpty
            ? l10n.noWifiFoundInputManually
            : l10n.foundNWifi('${_nearbyWifiList.length}');
        _provisionStep = 2;
      });
    } catch (e) {
      // 确保切回 WiFi 模式（失败也不能阻塞状态复位，避免扫描状态卡死）
      try {
        await _setForcedWifiRoute(true);
      } catch (_) {}
      if (!_isWifiOperationActive(operationId)) return;
      setState(() {
        _scanningNearbyWifi = false;
        _provisionStatus = '${l10n.scanFailed}: $e';
      });
    }
  }

  void _pickWiFi(ScanResult wifi) {
    _workingSsidController.text = wifi.ssid;
    _workingPasswordController.clear();
    _showPassword = false;
    setState(
      () => _provisionStatus =
          AppLocalizations.of(context)!.selectedWifiInputPassword(wifi.ssid),
    );
  }

  Future<void> _sendProvisionConfig() async {
    final operationId = _beginWifiOperation();
    final l10n = AppLocalizations.of(context)!;
    final ssid = _workingSsidController.text.trim();
    final password = _workingPasswordController.text;
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseInputWifiName),
        ),
      );
      return;
    }
    setState(() {
      _provisioning = true;
      _provisionStatus = l10n.sendingProvisionInfo;
      _provisionOk = false;
    });

    final outcome = await _softApProvisionRunner.run(
      ssid: ssid,
      password: password,
      isActive: () => _isWifiOperationActive(operationId),
      onConfigured: () {
        if (!_isWifiOperationActive(operationId)) return;
        setState(() {
          _provisionStatus = l10n.provisionSuccessConnecting;
          _provisionStep = 3;
        });
      },
      onWaiting: (attempt) {
        if (!_isWifiOperationActive(operationId)) return;
        setState(
          () => _provisionStatus =
              l10n.waitingDeviceConnectionN('$attempt'),
        );
      },
    );
    if (!_isWifiOperationActive(operationId) ||
        outcome.type == SoftApProvisionOutcomeType.cancelled) {
      return;
    }

    switch (outcome.type) {
      case SoftApProvisionOutcomeType.connected:
        setState(() {
          _provisioning = false;
          _provisionOk = true;
          _provisionStatus = l10n.provisionCompleteWifiIp(
            outcome.ssid ?? '',
            outcome.ip ?? '',
          );
        });
        unawaited(_onSoftApProvisionSuccess(operationId));
        break;
      case SoftApProvisionOutcomeType.timedOut:
        setState(() {
          _provisioning = false;
          _provisionOk = false;
          _provisionStatus = '❌ ${l10n.provisionTimeout}';
        });
        break;
      case SoftApProvisionOutcomeType.failed:
        setState(() {
          _provisioning = false;
          _provisionOk = false;
          _provisionStatus = '❌ ${outcome.message ?? l10n.sendFailed}';
        });
        break;
      case SoftApProvisionOutcomeType.cancelled:
        break;
    }
  }

  Future<void> _onSoftApProvisionSuccess(int operationId) async {
    await Future.delayed(const Duration(seconds: 2));

    if (!_isWifiOperationActive(operationId)) return;

    final shouldSwitch =
        await showWifiSwitchDialog(context, originalSsid: _originalSsid);
    if (!_isWifiOperationActive(operationId)) return;

    if (shouldSwitch) {
      try {
        if (_originalSsid != null) {
          await WiFiForIoTPlugin.connect(
            _originalSsid!,
            password: null,
            security: NetworkSecurity.WPA,
            joinOnce: false,
          );
        }
      } catch (_) {}

      // 即使未能读取原 SSID，也要解除强制 WiFi 路由，让系统恢复移动数据/
      // 普通网络选择；否则离开配网页后云端请求仍可能锁在设备热点。
      if (!_isWifiOperationActive(operationId)) return;
      await _releaseForcedWifiRoute();
      if (!_isWifiOperationActive(operationId)) return;

      // 配网结束回云端（系统兜底切换：不置手动锁，保留断网自动切本地的能力）
      await _connectionModeService.switchToRemote(byUser: false);
    }
  }

  Future<void> _startBleScan() async {
    debugPrint('[BLE] _startBleScan called');
    debugPrint(
      '[BLE] Current state: _bleScanning=$_bleScanning, _provisionSuccess=$_provisionSuccess, _bleStatus=$_bleStatus',
    );
    setState(() {
      _bleDevices = [];
      _selectedBleDevice = null;
      _bleConnecting = false;
      _provisioning = false;
      _provisionSuccess = false; // 重置配网成功状态
      _bleErrorMessage = null;
      _workingSsidController.clear();
      _workingPasswordController.clear();
    });

    await _bleProvisioningService.startScan();
  }

  Future<void> _connectToBleDevice(BleDeviceInfo device) async {
    setState(() {
      _selectedBleDevice = device;
      _bleConnecting = true;
    });

    final result = await _bleProvisioningService.connectToDevice(device);

    if (result.success && mounted) {
      // 连接成功，更新设备信息（包含真实SN）
      setState(() {
        _selectedBleDevice = result.deviceInfo;
        _bleConnecting = false;
      });
    } else if (mounted) {
      setState(() {
        _bleConnecting = false;
        _selectedBleDevice = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizeBleMessage(result.message)),
          backgroundColor: AppColors.errorLight,
        ),
      );
    }
  }

  Future<void> _disconnectBleDevice({WifiProvisionMode? expectedMode}) async {
    await _bleProvisioningService.disconnectFromDevice();
    if (!mounted ||
        (expectedMode != null && _provisionMode != expectedMode)) {
      return;
    }
    setState(() {
      _selectedBleDevice = null;
      _bleConnecting = false;
    });
  }

  Future<void> _sendBleProvisionConfig() async {
    final ssid = _workingSsidController.text.trim();
    // WiFi 密码允许包含合法的首尾空格，不能像 SSID 一样 trim。
    final password = _workingPasswordController.text;

    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pleaseInputWifiName),
        ),
      );
      return;
    }

    // 配网写 WiFi 凭据前先校验 PIN（附录 B）
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.pinLengthError)),
      );
      return;
    }

    setState(() {
      _provisioning = true;
    });

    final pinResult = await _bleProvisioningService.verifyPin(pin);
    // widget 可能在 verifyPin（8s 超时）期间被 pop/dispose，
    // 此时 mounted=false，继续调用 ScaffoldMessenger.of(context) 会触发
    // framework.dart 断言错误（deactivated element 访问）
    if (!mounted) return;
    if (!pinResult.success) {
      setState(() {
        _provisioning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizePinMessage(pinResult.message)),
          backgroundColor: AppColors.errorLight,
        ),
      );
      return;
    }

    final result = await _bleProvisioningService.writeWiFiCredentials(
      ssid: ssid,
      password: password,
    );

    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _provisioning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizeBleMessage(result.message)),
          backgroundColor: AppColors.errorLight,
        ),
      );
    }
  }

  void _onBleProvisionSuccess() {
    if (!mounted) return;

    setState(() {
      _provisioning = false;
      _provisionSuccess = true; // 设置配网成功状态
      _bleErrorMessage = null; // 清除错误消息
    });

    // 场景 A：配网成功后自动绑定（零操作，附录 B）
    _triggerAutoBind();
  }

  /// 场景 A：配网成功后自动绑定（零操作，附录 B：离网可用，PIN 配网阶段已验证）
  Future<void> _triggerAutoBind() async {
    final device = _selectedBleDevice;
    if (device == null) return;
    if (!mounted) return;
    if (!await getIt<StorageService>().getIsBleDirectEnabled()) return;
    final binding = getIt<BleBindingService>();
    await binding.bindAfterProvision(
      macAddress: device.macAddress,
      knownSn: device.sn,
      // 补登记同样携带 PIN（后端严格模式：无 PIN 拒绝登记）
      pin: _pinController.text.trim(),
    );
    if (!mounted) return;
    // 绑定结果由页面成功卡片（_provisionSuccess）承担，不再弹全局 SnackBar（Q3）
  }

  String _localizeBleMessage(String? code) {
    final l10n = AppLocalizations.of(context)!;
    switch (code) {
      case 'ble_waiting_credentials':
        return l10n.bleProvisionReady;
      case 'ble_connecting_wifi':
        return l10n.bleWaitingResult;
      case 'ble_wifi_connected':
        return l10n.bleSuccessExclaim;
      case 'ble_wifi_not_found':
        return l10n.bleWifiNotFound;
      case 'ble_wifi_password_failed':
        return l10n.bleWifiPasswordFailed;
      case 'ble_timeout':
        return l10n.bleTimeout;
      case 'ble_device_not_connected':
        return l10n.bleDeviceNotConnected;
      case 'ble_credentials_sent':
        return l10n.bleProvisionWaiting;
      case 'ble_connect_failed':
        return l10n.connectionFailed;
      case 'ble_write_failed':
        return l10n.sendFailed;
      case null:
        return l10n.bleError;
      default:
        return l10n.translateError(code);
    }
  }

  String _localizePinMessage(String? code) {
    final l10n = AppLocalizations.of(context)!;
    switch (code) {
      case 'pin_invalid':
        return l10n.pinInvalid;
      case 'pin_locked':
        return l10n.pinLocked;
      case 'pin_check_failed':
        return l10n.pinCheckFailed;
      default:
        return l10n.pinCheckFailed;
    }
  }

  String _getBleStatusText() {
    final l10n = AppLocalizations.of(context)!;
    switch (_bleStatus) {
      case BleProvisioningStatus.idle:
        return l10n.bleProvisionReady;
      case BleProvisioningStatus.scanning:
        return l10n.bleScanningShort;
      case BleProvisioningStatus.connecting:
        return l10n.bleConnecting;
      case BleProvisioningStatus.discoveringServices:
        return l10n.bleDiscoveringServices;
      case BleProvisioningStatus.readingDeviceInfo:
        return l10n.bleReadingInfo;
      case BleProvisioningStatus.subscribingNotifications:
        return l10n.bleSubscribing;
      case BleProvisioningStatus.writingCredentials:
        return l10n.bleWritingCredentials;
      case BleProvisioningStatus.waitingForResult:
        return l10n.bleWaitingResult;
      case BleProvisioningStatus.bleConnected:
        return l10n.bleConnectedDevice;
      case BleProvisioningStatus.wifiConnected:
        return l10n.bleSuccessExclaim;
      case BleProvisioningStatus.failed:
        return l10n.bleFailed;
      case BleProvisioningStatus.timeout:
        return l10n.bleTimeout;
      case BleProvisioningStatus.error:
        return l10n.bleError;
    }
  }

  void _resetProvision() {
    _cancelWifiOperation();
    unawaited(_releaseForcedWifiRoute());
    setState(() {
      _selectedDeviceAp = null;
      _nearbyWifiList = [];
      _provisionStep = 0;
      _provisionStatus = '';
      _provisionOk = false;
      _provisioning = false;
      _scanningNearbyWifi = false;
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
        padding: EdgeInsets.fromLTRB(
          20.w,
          20.w,
          20.w,
          // 键盘弹出时增加底部留白，确保密码输入框可滚动到键盘上方
          20.w + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          _buildModeSwitch(),
          SizedBox(height: 20.h),
          if (_provisionMode == WifiProvisionMode.softAp)
            _buildSoftApSection()
          else
            _buildBleSection(),
        ],
      ),
    );
  }

  Widget _buildModeSwitch() {
    final l10n = AppLocalizations.of(context)!;
    return WifiProvisionModeSwitch(
      selectedMode: _provisionMode,
      bleLabel: l10n.bleProvision,
      softApLabel: l10n.hotspotProvision,
      onSelected: _selectProvisionMode,
    );
  }

  void _selectProvisionMode(WifiProvisionMode mode) {
    if (mode == _provisionMode) return;
    _cancelWifiOperation();
    if (mode == WifiProvisionMode.ble) {
      unawaited(_releaseForcedWifiRoute());
      // 切换到BLE模式时重置热点配网状态
      setState(() {
        _provisionMode = WifiProvisionMode.ble;
        _selectedDeviceAp = null;
        _provisionStep = 0;
        _provisionStatus = '';
        _provisionOk = false;
        _provisioning = false;
        _wifiScanning = false;
        _scanningNearbyWifi = false;
      });
      return;
    }

    // 切换到热点模式时断开BLE连接并重置状态
    _disconnectBleDevice(expectedMode: WifiProvisionMode.softAp);
    setState(() {
      _provisionMode = WifiProvisionMode.softAp;
      _selectedDeviceAp = null;
      _provisionStep = 0;
      _provisionStatus = '';
      _provisionOk = false;
      _provisioning = false;
      _provisionSuccess = false;
    });
    if (_csInvNetworks.isEmpty && !_wifiScanning) _scanCSInvWiFi();
  }
}
