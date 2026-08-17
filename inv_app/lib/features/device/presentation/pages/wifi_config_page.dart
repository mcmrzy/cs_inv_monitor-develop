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
import 'package:inv_app/l10n/app_localizations.dart';

part 'wifi_config_sections.dart';

enum _ProvisionMode { softap, ble }

class WifiConfigPage extends StatefulWidget {
  const WifiConfigPage({super.key});

  @override
  State<WifiConfigPage> createState() => _WifiConfigPageState();
}

class _WifiConfigPageState extends State<WifiConfigPage> {
  final _provisionService = ProvisionService();
  final _bleProvisioningService = BleProvisioningService();
  final _connectionModeService = getIt<ConnectionModeService>();

  _ProvisionMode _provisionMode = _ProvisionMode.ble;

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

  @override
  void dispose() {
    _workingSsidController.dispose();
    _workingPasswordController.dispose();
    _pinController.dispose();
    _scSsidController.dispose();
    _scPasswordController.dispose();
    _bleStatusSub?.cancel();
    _bleDevicesSub?.cancel();
    _bleResultSub?.cancel();
    _bleProvisioningService.dispose();
    super.dispose();
  }

  bool _isOpenNetwork(ScannedWifiNetwork net) {
    final cap = net.capabilities?.toUpperCase() ?? '';
    return !cap.contains('WPA') && !cap.contains('WEP') && !cap.contains('EAP');
  }

  Future<bool> _requestWifiPermissions() async {
    // Android 6+ 扫描WiFi列表必须有位置权限，这是系统限制
    final status = await Permission.location.request();
    return status.isGranted || status.isLimited;
  }

  Future<void> _scanCSInvWiFi() async {
    setState(() {
      _wifiScanning = true;
      _csInvNetworks = [];
    });
    try {
      final granted = await _requestWifiPermissions();
      if (!granted) {
        setState(() => _wifiScanning = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.wifiPermissionHint),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // 请求打开位置服务（Android 11及以下必须开启定位才能扫描WiFi）
      final serviceEnabled = await Permission.location.serviceStatus.isEnabled;
      if (!serviceEnabled && mounted) {
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
      if (!mounted) return;
      final wifiEnabled = await ensureWifiEnabled(context);
      if (!wifiEnabled) {
        setState(() => _wifiScanning = false);
        return;
      }

      // 关键改进：先关闭WiFi强制使用，让系统执行一次新的WiFi扫描
      // Android 系统有4次/2分钟的扫描限制，先关闭再打开可以触发新扫描
      await WiFiForIoTPlugin.forceWifiUsage(false);
      await Future.delayed(const Duration(milliseconds: 500));

      // 多次读取以获取最新结果
      List<ScannedWifiNetwork> allNetworks = [];
      for (int i = 0; i < 3; i++) {
        final networks = await scanWifiNetworks(triggerScan: i == 0);
        allNetworks.addAll(networks);
        if (i < 2) await Future.delayed(const Duration(milliseconds: 800));
      }

      // 去重并按信号强度排序
      final ssidSet = <String>{};
      final filtered = <ScannedWifiNetwork>[];
      for (final n in allNetworks) {
        final ssid = n.ssid ?? '';
        if (ssid.isEmpty) continue;
        if (ssid.toUpperCase().startsWith('CS_INV') ||
            ssid.toUpperCase().startsWith('CS-INV')) {
          if (!ssidSet.contains(ssid)) {
            ssidSet.add(ssid);
            filtered.add(n);
          }
        }
      }
      filtered.sort((a, b) => (b.level ?? -100).compareTo(a.level ?? -100));

      // 同时扫描所有附近WiFi（用于后续配网选择）
      await _scanAllNearbyWifi();

      setState(() {
        _csInvNetworks = filtered;
        _wifiScanning = false;
      });
    } catch (e) {
      setState(() => _wifiScanning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.scanFailed}: $e'),
          ),
        );
      }
    }
  }

  /// 手机端扫描所有附近WiFi（在连接设备热点之前调用，缓存结果）
  Future<void> _scanAllNearbyWifi() async {
    try {
      await WiFiForIoTPlugin.forceWifiUsage(false);
      await Future.delayed(const Duration(milliseconds: 300));
      final networks = await scanWifiNetworks();
      // 过滤掉设备热点本身和无名称的
      _phoneScannedWifi = networks.where((n) {
        final ssid = n.ssid ?? '';
        if (ssid.isEmpty) return false;
        final upper = ssid.toUpperCase();
        return !upper.startsWith('CS_INV') && !upper.startsWith('CS-INV');
      }).toList();
      _phoneScannedWifi
          .sort((a, b) => (b.level ?? -100).compareTo(a.level ?? -100));
    } catch (_) {}
  }

  Future<void> _connectToAp(ScannedWifiNetwork network) async {
    setState(() {
      _selectedDeviceAp = network;
      _provisionStatus =
          AppLocalizations.of(context)!.connectingSsid(network.ssid ?? '');
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
        if (connected) break;
        if (attempt < 2) {
          setState(
            () => _provisionStatus =
                '${AppLocalizations.of(context)!.connectingSsid(ssid)} (${attempt + 2}/3)',
          );
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (connected) {
        setState(
          () => _provisionStatus =
              AppLocalizations.of(context)!.waitingStableConnection,
        );

        // 关键：强制HTTP请求走WiFi而不是移动数据
        await WiFiForIoTPlugin.forceWifiUsage(true);

        // 等待连接稳定，热点分配IP需要时间
        await Future.delayed(const Duration(seconds: 3));

        // 验证确实连上了设备热点（增加重试检查）
        String? currentSsid;
        for (int i = 0; i < 3; i++) {
          currentSsid = await WiFiForIoTPlugin.getSSID();
          if (currentSsid != null &&
              currentSsid.toUpperCase().contains('CS_INV')) {
            break;
          }
          await Future.delayed(const Duration(seconds: 1));
        }

        if (currentSsid == null ||
            !currentSsid.toUpperCase().contains('CS_INV')) {
          setState(
            () => _provisionStatus =
                AppLocalizations.of(context)!.noDeviceHotspotRetry,
          );
          return;
        }

        setState(() {
          _provisionStatus =
              AppLocalizations.of(context)!.connectedScanning(ssid);
          _provisionStep = 2;
        });
        // 使用手机端已缓存的WiFi列表，不再通过设备扫描
        _usePhoneScannedWifi();
      } else {
        setState(
          () => _provisionStatus =
              AppLocalizations.of(context)!.connectionSsidFailed(ssid),
        );
      }
    } catch (e) {
      setState(
        () => _provisionStatus =
            '${AppLocalizations.of(context)!.connectionFailed}: $e',
      );
    }
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
    setState(() {
      _scanningNearbyWifi = true;
    });
    try {
      // 扫描前检查位置权限（Android 6+ 扫描 WiFi 列表必须有位置权限，系统限制）
      final granted = await _requestWifiPermissions();
      if (!granted) {
        setState(() => _scanningNearbyWifi = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.wifiPermissionHint),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }
  
      // 请求打开位置服务（Android 11 及以下必须开启定位才能扫描 WiFi）
      final serviceEnabled = await Permission.location.serviceStatus.isEnabled;
      if (!serviceEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.locationServiceHint),
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() => _scanningNearbyWifi = false);
        return;
      }
  
      // 检查手机 WiFi 是否开启：未开启则引导开启，取消则中止扫描（公共方法，Q1）
      if (!mounted) return;
      final wifiEnabled = await ensureWifiEnabled(context);
      if (!wifiEnabled) {
        setState(() => _scanningNearbyWifi = false);
        return;
      }
  
      // 临时切回普通 WiFi 模式以执行扫描
      await WiFiForIoTPlugin.forceWifiUsage(false);
      await Future.delayed(const Duration(milliseconds: 500));

      List<ScannedWifiNetwork> networks = [];
      for (int i = 0; i < 2; i++) {
        final result = await scanWifiNetworks(triggerScan: i == 0);
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
      final unique = <ScannedWifiNetwork>[];
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
            ? AppLocalizations.of(context)!.noWifiFoundInputManually
            : AppLocalizations.of(context)!
                .foundNWifi('${_nearbyWifiList.length}');
        _provisionStep = 2;
      });
    } catch (e) {
      // 确保切回 WiFi 模式（失败也不能阻塞状态复位，避免扫描状态卡死）
      try {
        await WiFiForIoTPlugin.forceWifiUsage(true);
      } catch (_) {}
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
    setState(
      () => _provisionStatus =
          AppLocalizations.of(context)!.selectedWifiInputPassword(wifi.ssid),
    );
  }

  Future<void> _sendProvisionConfig() async {
    final ssid = _workingSsidController.text.trim();
    final password = _workingPasswordController.text.trim();
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pleaseInputWifiName),
        ),
      );
      return;
    }
    setState(() {
      _provisioning = true;
      _provisionStatus = AppLocalizations.of(context)!.sendingProvisionInfo;
      _provisionOk = false;
    });

    // 确保请求走WiFi
    await WiFiForIoTPlugin.forceWifiUsage(true);

    var result = await _provisionService.configure(ssid, password);

    if (result.success) {
      setState(() {
        _provisionStatus =
            AppLocalizations.of(context)!.provisionSuccessConnecting;
        _provisionStep = 3;
      });
      await Future.delayed(const Duration(seconds: 2));
      for (int i = 0; i < 15; i++) {
        await WiFiForIoTPlugin.forceWifiUsage(true);
        final status = await _provisionService.checkStatus();
        if (status.success) {
          setState(() {
            _provisioning = false;
            _provisionOk = true;
            _provisionStatus = AppLocalizations.of(context)!
                .provisionCompleteWifiIp(status.ssid ?? '', status.ip ?? '');
          });
          _onSoftApProvisionSuccess();
          return;
        }
        if (mounted) {
          setState(
            () => _provisionStatus = AppLocalizations.of(context)!
                .waitingDeviceConnectionN('${i + 1}'),
          );
        }
        await Future.delayed(const Duration(seconds: 2));
      }
      setState(() {
        _provisioning = false;
        _provisionStatus =
            AppLocalizations.of(context)!.configSentDeviceRestart;
        _provisionOk = true;
      });
      _onSoftApProvisionSuccess();
    } else {
      setState(() {
        _provisioning = false;
        _provisionStatus = '❌ ${result.message}';
      });
    }
  }

  Future<void> _onSoftApProvisionSuccess() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final shouldSwitch =
        await showWifiSwitchDialog(context, originalSsid: _originalSsid);
    if (!mounted) return;

    if (shouldSwitch && _originalSsid != null) {
      try {
        await WiFiForIoTPlugin.connect(
          _originalSsid!,
          password: null,
          security: NetworkSecurity.WPA,
          joinOnce: false,
        );
      } catch (_) {}

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

  Future<void> _disconnectBleDevice() async {
    await _bleProvisioningService.disconnectFromDevice();
    setState(() {
      _selectedBleDevice = null;
      _bleConnecting = false;
    });
  }

  Future<void> _sendBleProvisionConfig() async {
    final ssid = _workingSsidController.text.trim();
    final password = _workingPasswordController.text.trim();

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
    if (pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.pinRequired)),
      );
      return;
    }

    setState(() {
      _provisioning = true;
    });

    final pinResult = await _bleProvisioningService.verifyPin(pin);
    if (!pinResult.success && mounted) {
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

    if (!result.success && mounted) {
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
          if (_provisionMode == _ProvisionMode.softap)
            _buildSoftApSection()
          else
            _buildBleSection(),
        ],
      ),
    );
  }

  Widget _buildModeSwitch() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceHover(context),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                // 切换到BLE模式时重置热点配网状态
                setState(() {
                  _provisionMode = _ProvisionMode.ble;
                  _selectedDeviceAp = null;
                  _provisionStep = 0;
                  _provisionStatus = '';
                  _provisionOk = false;
                });
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 10.h),
                decoration: BoxDecoration(
                  color: _provisionMode == _ProvisionMode.ble
                      ? AppColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bluetooth,
                      size: 18.sp,
                      color: _provisionMode == _ProvisionMode.ble
                          ? Colors.white
                          : AppColor.textSecondary(context),
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      l10n.bleProvision,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: _provisionMode == _ProvisionMode.ble
                            ? Colors.white
                            : AppColor.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                // 切换到热点模式时断开BLE连接并重置状态
                _disconnectBleDevice();
                setState(() {
                  _provisionMode = _ProvisionMode.softap;
                  _selectedDeviceAp = null;
                  _provisionStep = 0;
                  _provisionStatus = '';
                  _provisionOk = false;
                  _provisionSuccess = false;
                });
                if (_csInvNetworks.isEmpty && !_wifiScanning) _scanCSInvWiFi();
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 10.h),
                decoration: BoxDecoration(
                  color: _provisionMode == _ProvisionMode.softap
                      ? AppColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.router,
                      size: 18.sp,
                      color: _provisionMode == _ProvisionMode.softap
                          ? Colors.white
                          : AppColor.textSecondary(context),
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      AppLocalizations.of(context)!.hotspotProvision,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: _provisionMode == _ProvisionMode.softap
                            ? Colors.white
                            : AppColor.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicatorRow(List<_StepData> steps) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;

          Color stepColor;
          if (step.isCompleted) {
            stepColor = AppColors.successLight;
          } else if (step.isCurrent) {
            stepColor = AppColors.primary;
          } else {
            stepColor = AppColor.textHint(context);
          }

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 28.w,
                        height: 28.w,
                        decoration: BoxDecoration(
                          color: stepColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: stepColor, width: 2),
                        ),
                        child: step.isCompleted
                            ? Icon(Icons.check, size: 14.sp, color: stepColor)
                            : Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w600,
                                    color: stepColor,
                                  ),
                                ),
                              ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        step.label,
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: step.isCurrent || step.isCompleted
                              ? AppColor.textPrimary(context)
                              : AppColor.textHint(context),
                          fontWeight: step.isCurrent
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (index < steps.length - 1)
                  Container(
                    width: 16.w,
                    height: 2,
                    color: step.isCompleted
                        ? AppColors.successLight
                        : AppColor.border(context),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StepData {
  final String label;
  final bool isCompleted;
  final bool isCurrent;
  const _StepData({
    required this.label,
    required this.isCompleted,
    required this.isCurrent,
  });
}
