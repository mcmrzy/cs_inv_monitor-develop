import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:inv_app/core/services/provision_service.dart';
import 'package:inv_app/core/services/ble_provisioning_service.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/services/wifi_scan_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/widgets/wifi_switch_dialog.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

enum _ProvisionMode { softap, ble }

class WifiConfigPage extends StatefulWidget {
  const WifiConfigPage({super.key});

  @override
  State<WifiConfigPage> createState() => _WifiConfigPageState();
}

class _WifiConfigPageState extends State<WifiConfigPage> {
  final _provisionService = ProvisionService();
  final _bleProvisioningService = BleProvisioningService();
  final _connectionModeService = ConnectionModeService(getIt<StorageService>());

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
        setState(() {
          _bleErrorMessage = message;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
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

  /// 重新扫描附近WiFi（手机端，在连接设备热点后临时切回普通模式扫描）
  Future<void> _rescanNearbyWifiFromPhone() async {
    setState(() {
      _scanningNearbyWifi = true;
    });
    try {
      // 临时切回普通WiFi模式以执行扫描
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
    final mqtt = getIt<MQTTService>();
    bool deviceOnline = false;

    try {
      final onlineFuture = mqtt.statusStream
          .where((s) => s.online)
          .first
          .timeout(const Duration(seconds: 30));
      deviceOnline =
          await onlineFuture.then((_) => true).catchError((_) => false);
    } catch (_) {}

    if (!mounted) return;
    if (deviceOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.deviceOnlineWifi),
          backgroundColor: AppColors.successLight,
          duration: const Duration(seconds: 3),
        ),
      );
    }

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

      await _connectionModeService.switchToRemote();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.switchedToRemoteMode),
            backgroundColor: AppColors.successLight,
          ),
        );
      }
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

    setState(() {
      _provisioning = true;
    });

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
        padding: EdgeInsets.all(20.w),
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
        color: AppColors.surfaceHover,
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
                          : AppColors.textSecondary,
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      l10n.bleProvision,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: _provisionMode == _ProvisionMode.ble
                            ? Colors.white
                            : AppColors.textSecondary,
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
                          : AppColors.textSecondary,
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      AppLocalizations.of(context)!.hotspotProvision,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: _provisionMode == _ProvisionMode.softap
                            ? Colors.white
                            : AppColors.textSecondary,
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

  Widget _buildSoftApSection() {
    final deviceConnected = _provisionStep >= 2;
    final isStep0 = !deviceConnected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepIndicatorRow([
          _StepData(
            label: AppLocalizations.of(context)!.connectDeviceHotspot,
            isCompleted: _provisionStep > 1,
            isCurrent: _provisionStep == 1 ||
                (_provisionStep == 0 && !deviceConnected),
          ),
          _StepData(
            label: AppLocalizations.of(context)!.selectWifi,
            isCompleted: _provisionStep > 2 || _provisionOk,
            isCurrent: _provisionStep == 2 && !_provisionOk,
          ),
          _StepData(
            label: AppLocalizations.of(context)!.finish,
            isCompleted: _provisionOk,
            isCurrent: false,
          ),
        ]),
        SizedBox(height: 24.h),
        if (isStep0) ...[
          SizedBox(
            width: double.infinity,
            height: 46.h,
            child: ElevatedButton.icon(
              onPressed: _wifiScanning ? null : _scanCSInvWiFi,
              icon: _wifiScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.wifi_find, size: 22),
              label: Text(
                _wifiScanning
                    ? AppLocalizations.of(context)!.scanning
                    : ' ${AppLocalizations.of(context)!.scanNearInverters}',
                style: const TextStyle(fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
          if (_csInvNetworks.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Text(
              AppLocalizations.of(context)!
                  .foundNInverters('${_csInvNetworks.length}'),
              style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
            ),
            SizedBox(height: 8.h),
            ..._csInvNetworks.map((net) {
              final ssid = net.ssid ?? '';
              final rssi = net.level ?? -100;
              final sig = rssi > -50 ? '📶📶📶' : (rssi > -70 ? '📶📶' : '📶');
              return Card(
                margin: EdgeInsets.only(bottom: 8.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: ListTile(
                  leading: Container(
                    width: 44.w,
                    height: 44.w,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: const Icon(
                      Icons.solar_power,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    ssid,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '$sig $rssi dBm',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColors.textHint,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: AppColors.textHint,
                  ),
                  onTap: () => _connectToAp(net),
                ),
              );
            }),
          ],
          if (_csInvNetworks.isEmpty && !_wifiScanning)
            Padding(
              padding: EdgeInsets.only(top: 16.h),
              child: Center(
                child: Container(
                  padding: EdgeInsets.all(24.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wifi_off,
                        size: 40.sp,
                        color: AppColors.textHint,
                      ),
                      SizedBox(height: 10.h),
                      Text(
                        AppLocalizations.of(context)!.noInverterFound,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        AppLocalizations.of(context)!.ensureDevicePowered,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (_provisionStep == 1) ...[
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    _provisionStatus,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (deviceConnected) ...[
          Container(
            padding: EdgeInsets.all(12.w),
            margin: EdgeInsets.only(bottom: 16.h),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.successLight,
                  size: 20,
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!
                        .connectedTo(_selectedDeviceAp?.ssid ?? ''),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: const Color(0xFF065F46),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _resetProvision,
                  child: Text(
                    AppLocalizations.of(context)!.disconnect,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.errorLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (deviceConnected) ...[
          SizedBox(
            width: double.infinity,
            height: 44.h,
            child: OutlinedButton.icon(
              onPressed:
                  _scanningNearbyWifi ? null : _rescanNearbyWifiFromPhone,
              icon: _scanningNearbyWifi
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi, size: 20),
              label: Text(
                _scanningNearbyWifi
                    ? AppLocalizations.of(context)!.scanning
                    : AppLocalizations.of(context)!.scanNearbyWifi,
                style: const TextStyle(fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          SizedBox(height: 8.h),
          if (_nearbyWifiList.isNotEmpty) ...[
            Text(
              AppLocalizations.of(context)!.clickWifiToFill,
              style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
            ),
            SizedBox(height: 6.h),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              constraints: BoxConstraints(maxHeight: 200.h),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _nearbyWifiList.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (_, i) {
                  final w = _nearbyWifiList[i];
                  final sig =
                      w.rssi > -50 ? '📶📶📶' : (w.rssi > -70 ? '📶📶' : '📶');
                  final selected = _workingSsidController.text == w.ssid;
                  return ListTile(
                    leading: Icon(
                      w.encrypted ? Icons.lock_outline : Icons.wifi,
                      size: 20,
                      color: selected ? AppColors.primary : AppColors.textHint,
                    ),
                    title: Text(
                      w.ssid,
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    trailing: Text(
                      '$sig ${w.rssi}dBm',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: AppColors.textHint,
                      ),
                    ),
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
              labelText: AppLocalizations.of(context)!.wifiName,
              hintText: AppLocalizations.of(context)!.clickAboveOrManual,
              prefixIcon: const Icon(Icons.wifi, color: AppColors.primary),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          TextField(
            controller: _workingPasswordController,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.wifiPassword,
              hintText: AppLocalizations.of(context)!.inputWifiPassword,
              prefixIcon:
                  const Icon(Icons.lock_outline, color: AppColors.textHint),
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.textHint,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: 20.h),
          SizedBox(
            width: double.infinity,
            height: 50.h,
            child: ElevatedButton.icon(
              onPressed: _provisioning ? null : _sendProvisionConfig,
              icon: _provisioning
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.router, size: 22),
              label: Text(
                _provisioning
                    ? AppLocalizations.of(context)!.configuring
                    : AppLocalizations.of(context)!.sendingProvisionInfo,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.successLight,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
        ],
        if (_provisionStatus.isNotEmpty) ...[
          SizedBox(height: 16.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: _provisionOk
                  ? const Color(0xFFECFDF5)
                  : (_provisionStatus.contains('❌')
                      ? const Color(0xFFFEF2F2)
                      : const Color(0xFFEFF6FF)),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                Icon(
                  _provisionOk
                      ? Icons.check_circle
                      : (_provisionStatus.contains('❌')
                          ? Icons.error
                          : Icons.info),
                  size: 20.sp,
                  color: _provisionOk
                      ? AppColors.successLight
                      : (_provisionStatus.contains('❌')
                          ? AppColors.errorLight
                          : AppColors.primary),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    _provisionStatus,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        SizedBox(height: 60.h),
      ],
    );
  }

  Widget _buildBleSection() {
    final l10n = AppLocalizations.of(context)!;
    // 计算Current state
    final bool deviceSelected = _selectedBleDevice != null;
    final bool isConfiguring =
        _bleStatus == BleProvisioningStatus.writingCredentials ||
            _bleStatus == BleProvisioningStatus.waitingForResult;
    final bool isCompleted = _bleStatus == BleProvisioningStatus.wifiConnected;
    final bool isConnected = _bleStatus == BleProvisioningStatus.bleConnected;

    // 判断当前阶段
    final bool isError = _bleStatus == BleProvisioningStatus.failed ||
        _bleStatus == BleProvisioningStatus.error;
    final bool isTimeout = _bleStatus == BleProvisioningStatus.timeout; // 扫描超时
    final bool showSuccessPhase = _provisionSuccess; // 配网成功阶段
    final bool showScanPhase = !showSuccessPhase &&
        (_bleScanning ||
            (_bleDevices.isNotEmpty && !deviceSelected) ||
            (!deviceSelected && !_bleScanning && !isError && !isTimeout));
    final bool showNoDevicePhase = isTimeout &&
        !showSuccessPhase &&
        !isError &&
        !deviceSelected; // 未发现设备阶段
    final bool showConnectingPhase = !showSuccessPhase && _bleConnecting;
    final bool showConfigPhase =
        !showSuccessPhase && isConnected && !isConfiguring;
    final bool showConfiguringPhase = !showSuccessPhase && isConfiguring;
    final bool showCompletedPhase = isCompleted;
    final bool showErrorPhase = !showSuccessPhase && isError && !deviceSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 步骤指示器
        _buildStepIndicatorRow([
          _StepData(
            label: AppLocalizations.of(context)!.scanNearInverters,
            isCompleted: deviceSelected,
            isCurrent: showScanPhase,
          ),
          _StepData(
            label: AppLocalizations.of(context)!.selectWifi,
            isCompleted: isCompleted || isConnected || isConfiguring,
            isCurrent: showConfigPhase || showConfiguringPhase,
          ),
          _StepData(
            label: AppLocalizations.of(context)!.finish,
            isCompleted: isCompleted,
            isCurrent: showCompletedPhase,
          ),
        ]),
        SizedBox(height: 24.h),

        // 配网成功显示
        if (showSuccessPhase) ...[
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.successLight,
                  size: 40,
                ),
                SizedBox(height: 12.h),
                Text(
                  l10n.bleSuccessExclaim,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.successLight,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  l10n.deviceConnectingWifi,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.h),
                SizedBox(
                  width: double.infinity,
                  height: 44.h,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _provisionSuccess = false;
                        _selectedBleDevice = null;
                        _bleErrorMessage = null;
                        _workingSsidController.clear();
                        _workingPasswordController.clear();
                      });
                      _disconnectBleDevice();
                    },
                    icon: const Icon(Icons.check, size: 20),
                    label:
                        Text(l10n.done, style: const TextStyle(fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 错误状态显示
        if (showErrorPhase) ...[
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.errorLight,
                  size: 40,
                ),
                SizedBox(height: 12.h),
                Text(
                  _bleStatus == BleProvisioningStatus.timeout
                      ? l10n.bleTimeout
                      : _bleStatus == BleProvisioningStatus.failed
                          ? l10n.bleFailed
                          : l10n.bleError,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.errorLight,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  l10n.checkDeviceWorking,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.h),
                SizedBox(
                  width: double.infinity,
                  height: 44.h,
                  child: ElevatedButton.icon(
                    onPressed: _startBleScan,
                    icon: const Icon(Icons.refresh, size: 20),
                    label:
                        Text(l10n.rescan, style: const TextStyle(fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 未发现设备显示（扫描超时）
        if (showNoDevicePhase) ...[
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.bluetooth_disabled,
                  color: AppColors.textHint,
                  size: 40,
                ),
                SizedBox(height: 12.h),
                Text(
                  l10n.noDeviceFound,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  l10n.ensureProvisionMode,
                  style: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.h),
                SizedBox(
                  width: double.infinity,
                  height: 44.h,
                  child: ElevatedButton.icon(
                    onPressed: _startBleScan,
                    icon: const Icon(Icons.refresh, size: 20),
                    label:
                        Text(l10n.rescan, style: const TextStyle(fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 说明信息（仅在扫描阶段显示）
        if (showScanPhase) ...[
          Container(
            padding: EdgeInsets.all(14.w),
            margin: EdgeInsets.only(bottom: 20.h),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppColors.primary,
                  size: 20,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    l10n.bleModeDescription,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 扫描按钮（仅在扫描阶段显示）
        if (showScanPhase) ...[
          SizedBox(
            width: double.infinity,
            height: 46.h,
            child: ElevatedButton.icon(
              onPressed: () {
                debugPrint(
                  '[BLE] Scan button clicked, _bleScanning=$_bleScanning',
                );
                if (!_bleScanning) {
                  _startBleScan();
                }
              },
              icon: _bleScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.bluetooth_searching, size: 22),
              label: Text(
                _bleScanning
                    ? AppLocalizations.of(context)!.scanning
                    : AppLocalizations.of(context)!.scanNearInverters,
                style: const TextStyle(fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),

          SizedBox(height: 16.h),

          // 设备列表
          if (_bleDevices.isNotEmpty) ...[
            Text(
              AppLocalizations.of(context)!
                  .foundNInverters('${_bleDevices.length}'),
              style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
            ),
            SizedBox(height: 8.h),
            ..._bleDevices.map((device) {
              final rssi = device.rssi;
              final sig = rssi > -50 ? '📶📶📶' : (rssi > -70 ? '📶📶' : '📶');
              return Card(
                margin: EdgeInsets.only(bottom: 8.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: ListTile(
                  leading: Container(
                    width: 44.w,
                    height: 44.w,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: const Icon(
                      Icons.bluetooth,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    device.sn.isNotEmpty ? device.sn : device.deviceName,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '$sig $rssi dBm',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColors.textHint,
                    ),
                  ),
                  trailing: _bleConnecting &&
                          _selectedBleDevice?.macAddress == device.macAddress
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: AppColors.textHint,
                        ),
                  onTap:
                      _bleConnecting ? null : () => _connectToBleDevice(device),
                ),
              );
            }),
          ],

          // 无设备提示
          if (_bleDevices.isEmpty && !_bleScanning)
            Padding(
              padding: EdgeInsets.only(top: 16.h),
              child: Center(
                child: Container(
                  padding: EdgeInsets.all(24.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bluetooth_disabled,
                        size: 40.sp,
                        color: AppColors.textHint,
                      ),
                      SizedBox(height: 10.h),
                      Text(
                        AppLocalizations.of(context)!.noInverterFound,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        AppLocalizations.of(context)!.ensureDevicePowered,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ], // 结束扫描阶段

        // 连接阶段
        if (showConnectingPhase) ...[
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    _getBleStatusText(),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 已连接设备信息
        if (_selectedBleDevice != null &&
            (_bleStatus == BleProvisioningStatus.bleConnected ||
                _bleStatus == BleProvisioningStatus.wifiConnected)) ...[
          Container(
            padding: EdgeInsets.all(12.w),
            margin: EdgeInsets.only(bottom: 16.h),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.successLight,
                  size: 20,
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.connectedTo(
                          _selectedBleDevice!.sn.isNotEmpty
                              ? _selectedBleDevice!.sn
                              : _selectedBleDevice!.deviceName,
                        ),
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: const Color(0xFF065F46),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _disconnectBleDevice,
                  child: Text(
                    AppLocalizations.of(context)!.disconnect,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.errorLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 配网失败错误提示
        if (_bleErrorMessage != null && showConfigPhase) ...[
          Container(
            padding: EdgeInsets.all(12.w),
            margin: EdgeInsets.only(bottom: 16.h),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.errorLight,
                  size: 20,
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    _bleErrorMessage!,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: const Color(0xFF991B1B),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _bleErrorMessage = null),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ],

        // WiFi配置表单（仅在配置阶段显示）
        if (showConfigPhase) ...[
          SizedBox(
            width: double.infinity,
            height: 44.h,
            child: OutlinedButton.icon(
              onPressed:
                  _scanningNearbyWifi ? null : _rescanNearbyWifiFromPhone,
              icon: _scanningNearbyWifi
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi, size: 20),
              label: Text(
                _scanningNearbyWifi
                    ? AppLocalizations.of(context)!.scanning
                    : AppLocalizations.of(context)!.scanNearbyWifi,
                style: const TextStyle(fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          SizedBox(height: 8.h),
          if (_nearbyWifiList.isNotEmpty) ...[
            Text(
              AppLocalizations.of(context)!.clickWifiToFill,
              style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
            ),
            SizedBox(height: 6.h),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              constraints: BoxConstraints(maxHeight: 200.h),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _nearbyWifiList.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (_, i) {
                  final w = _nearbyWifiList[i];
                  final sig =
                      w.rssi > -50 ? '📶📶📶' : (w.rssi > -70 ? '📶📶' : '📶');
                  final selected = _workingSsidController.text == w.ssid;
                  return ListTile(
                    leading: Icon(
                      w.encrypted ? Icons.lock_outline : Icons.wifi,
                      size: 20,
                      color: selected ? AppColors.primary : AppColors.textHint,
                    ),
                    title: Text(
                      w.ssid,
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    trailing: Text(
                      '$sig ${w.rssi}dBm',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: AppColors.textHint,
                      ),
                    ),
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
              labelText: AppLocalizations.of(context)!.wifiName,
              hintText: AppLocalizations.of(context)!.clickAboveOrManual,
              prefixIcon: const Icon(Icons.wifi, color: AppColors.primary),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          TextField(
            controller: _workingPasswordController,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.wifiPassword,
              hintText: AppLocalizations.of(context)!.inputWifiPassword,
              prefixIcon:
                  const Icon(Icons.lock_outline, color: AppColors.textHint),
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.textHint,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: 20.h),
          SizedBox(
            width: double.infinity,
            height: 50.h,
            child: ElevatedButton.icon(
              onPressed: _provisioning ? null : _sendBleProvisionConfig,
              icon: _provisioning
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.bluetooth, size: 22),
              label: Text(
                _provisioning ? l10n.provisioningNow : l10n.sendWifiConfig,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.successLight,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
        ],

        // 配置中阶段
        if (showConfiguringPhase) ...[
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    _getBleStatusText(),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 完成阶段
        if (showCompletedPhase) ...[
          SizedBox(height: 16.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.successLight,
                  size: 20,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    _getBleStatusText(),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        SizedBox(height: 60.h),
      ],
    );
  }

  Widget _buildStepIndicatorRow(List<_StepData> steps) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      decoration: BoxDecoration(
        color: Colors.white,
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
            stepColor = AppColors.textHint;
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
                              ? AppColors.textPrimary
                              : AppColors.textHint,
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
                        : const Color(0xFFE5E7EB),
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
