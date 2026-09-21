import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/errors/ota_error_types.dart';
import 'package:inv_app/core/platform/platform.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/wifi_scan_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/ble_pin_bind_dialog.dart';
import 'package:inv_app/core/widgets/wifi_enable_dialog.dart';
import 'package:inv_app/features/ota/data/datasources/ble_communication_service.dart';
import 'package:inv_app/features/ota/data/datasources/local_ota_result_sync_queue.dart';
import 'package:inv_app/features/ota/data/datasources/wifi_ap_communication_service.dart';
import 'package:inv_app/features/ota/presentation/controller/local_ota_controller.dart';
import 'package:inv_app/features/ota/domain/entities/local_channel.dart';
import 'package:inv_app/features/ota/domain/repositories/local_communication_repository.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/models/local_ota_presentation.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/features/ota/presentation/models/firmware_module_presentation.dart';
import 'package:permission_handler/permission_handler.dart';

enum LocalOTAStep {
  selectFirmware,
  connectDevice,
  pushFirmware,
  triggerUpgrade,
  result,
}

enum LocalOTAResult { success, failed, verifyFailed }

class LocalOTAPage extends StatefulWidget {
  final String deviceSN;
  final String deviceIP;
  final int? firmwareId;
  final String? firmwareUrl;
  final String? firmwareFileName;
  final String? deviceModel;
  final int? fileSize;
  final String? targetChip;
  final String? firmwareVersion;
  final String? fileSha256;
  final int? securityVersion;
  final String? releaseSignature;
  final LocalCommunicationChannel channel;

  /// BLE 通道目标设备 MAC（扫描页连接时带入）。
  /// 设备被连接后停止广播，带 MAC 可在连接步骤免扫描直接复用会话。
  final String? deviceMac;

  /// 嵌入模式：作为 Tab 内容嵌入双通道页时不渲染自身 Scaffold/AppBar，
  /// 仅渲染升级流程主体（步骤指示 + 内容），由外层页面提供 AppBar。
  final bool embedded;

  const LocalOTAPage({
    super.key,
    required this.deviceSN,
    required this.deviceIP,
    this.firmwareId,
    this.firmwareUrl,
    this.firmwareFileName,
    this.deviceModel,
    this.fileSize,
    this.targetChip,
    this.firmwareVersion,
    this.fileSha256,
    this.securityVersion,
    this.releaseSignature,
    this.channel = LocalCommunicationChannel.wifiAp,
    this.deviceMac,
    this.embedded = false,
  });

  @override
  State<LocalOTAPage> createState() => _LocalOTAPageState();
}

class _LocalOTAPageState extends State<LocalOTAPage> {
  LocalOTAStep _currentStep = LocalOTAStep.selectFirmware;
  LocalOTAResult? _result;
  String? _resultMessage;
  String? _newVersion;

  String? _selectedFilePath;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;

  // 已下载固件列表（离线选择用）
  List<DownloadedFirmwareInfo> _downloadedFirmwares = [];
  bool _firmwareListLoading = true;

  /// 当前选中的已下载固件（离线升级时提供签名元数据；
  /// 为 null 表示使用路由参数传入的元数据）
  DownloadedFirmwareInfo? _selectedDownloaded;

  double _uploadProgress = 0.0;
  double _upgradeProgress = 0.0;
  String _upgradeStatus = '';

  bool _isProcessing = false;
  String? _errorMessage;

  // WiFi 热点扫描
  bool _scanningWifi = false;
  ScannedWifiNetwork? _selectedAp;
  bool _autoConnecting = false;

  late final FirmwareDownloadService _downloadService;
  late final LocalCommunicationRepository _communicationService;

  StreamSubscription<DownloadProgressEvent>? _downloadProgressSub;

  /// 本地 OTA 执行引擎（上传→触发→轮询→上报的状态机下沉层）
  LocalOTAController? _otaController;

  /// 按固件 ID 从服务端拉取的元数据（路由仅传 firmware_id 时的链路）；
  /// 与路由参数兼容：路由参数优先，缺失时用拉取结果兜底
  Map<String, dynamic>? _firmwareMeta;

  // 固件元数据有效值：路由参数优先，其次服务端拉取结果
  String? get _metaFirmwareUrl =>
      widget.firmwareUrl ?? (_firmwareMeta?['download_url'] as String?);
  String? get _metaFileName =>
      widget.firmwareFileName ?? (_firmwareMeta?['file_name'] as String?);
  String? get _metaDeviceModel =>
      widget.deviceModel ??
      (_firmwareMeta?['device_model'] as String?) ??
      (_firmwareMeta?['model'] as String?);
  int? get _metaFileSize =>
      widget.fileSize ?? (_firmwareMeta?['file_size'] as num?)?.toInt();
  String? get _metaTargetChip =>
      widget.targetChip ?? (_firmwareMeta?['target_chip'] as String?);
  String? get _metaFirmwareVersion =>
      widget.firmwareVersion ?? (_firmwareMeta?['firmware_version'] as String?);
  String? get _metaFileSha256 =>
      widget.fileSha256 ?? (_firmwareMeta?['file_sha256'] as String?);
  int? get _metaSecurityVersion =>
      widget.securityVersion ??
      (_firmwareMeta?['security_version'] as num?)?.toInt();
  List<String>? get _metaSupportedChannels {
    final value = _firmwareMeta?['supported_channels'];
    if (value is! List) return null;
    return value.map((entry) => entry.toString()).toList(growable: false);
  }
  String? get _metaReleaseSignature =>
      widget.releaseSignature ??
      (_firmwareMeta?['release_signature'] as String?);

  @override
  void initState() {
    super.initState();
    // 应用级单例：并发守卫与进度流跨页面共享，页面退出不再 dispose
    _downloadService = getIt<FirmwareDownloadService>();

    // 根据通道类型创建对应的通信服务
    switch (widget.channel) {
      case LocalCommunicationChannel.ble:
        _communicationService = BleCommunicationService(
          adapter: getIt<BleAdapter>(),
          manager: getIt<BleDeviceManager>(),
        );
        break;
      case LocalCommunicationChannel.wifiAp:
        _communicationService = WifiApCommunicationService();
        break;
    }

    _downloadProgressSub = _downloadService.progressStream.listen((event) {
      // 只关注本页固件任务的进度（进度流已按 firmwareId 分流）
      if (mounted &&
          (widget.firmwareId == null ||
              event.firmwareId == widget.firmwareId)) {
        setState(() {
          _downloadProgress = _normalizeProgress(
            event.progress,
            source: 'download',
          );
        });
      }
    });

    _initFirmware();
    _loadDownloadedFirmwares();
  }

  Future<void> _initFirmware() async {
    if (widget.firmwareId != null) {
      final isDownloaded =
          await _downloadService.isFirmwareDownloaded(widget.firmwareId!);
      if (isDownloaded) {
        final path = await _downloadService
            .getDownloadedFirmwarePath(widget.firmwareId!);
        if (path != null && mounted) {
          setState(() {
            _selectedFilePath = path;
          });
        }
      }
    }

    // 路由仅传 firmware_id 时，按 ID 拉取升级元数据
    // （替代旧版 9 个 query 参数传复杂元数据）
    if (widget.firmwareUrl == null && widget.firmwareId != null) {
      try {
        final result =
            await getIt<OtaRepository>().getFirmwareInfo(widget.firmwareId!);
        result.fold(
          (failure) {
            if (mounted) {
              setState(() {
                _errorMessage = AppLocalizations.of(context)!
                    .str('download_failed', {'error': failure.message});
              });
            }
          },
          (meta) {
            if (mounted) {
              setState(() => _firmwareMeta = meta);
            }
          },
        );
      } catch (_) {
        // 拉取失败时保留离线选择链路兜底
      }
    }
  }

  /// 加载本地已下载固件列表（无网时也可选择已预下载的固件）
  Future<void> _loadDownloadedFirmwares() async {
    final items = await _downloadService.listDownloadedFirmwares();
    if (!mounted) return;
    final channel = widget.channel == LocalCommunicationChannel.ble
        ? 'ble'
        : 'wifi_ap';
    final eligibleItems = items
        .where((item) => item.supportsLocalChannel(channel))
        .toList(growable: false);
    setState(() {
      _downloadedFirmwares = eligibleItems;
      for (final item in eligibleItems) {
        final matchesRoute =
            widget.firmwareId != null && item.firmwareId == widget.firmwareId;
        final matchesSelection = _selectedFilePath == item.filePath;
        if (matchesRoute || matchesSelection) {
          _selectedFilePath = item.filePath;
          _selectedDownloaded = item;
          break;
        }
      }
      _firmwareListLoading = false;
    });
  }

  @override
  void dispose() {
    _downloadProgressSub?.cancel();
    _otaController
      ?..removeListener(_onControllerChanged)
      ..dispose();
    // 本页发起且未完成的下载随页面退出取消（.part 分片保留供续传）；
    // 下载服务是应用级单例，不随页面 dispose
    if (_isDownloading && widget.firmwareId != null) {
      _downloadService.cancelDownload(widget.firmwareId!);
    }
    // 清理通信服务资源
    if (_communicationService case BleCommunicationService service) {
      service.dispose();
    } else {
      // WiFi 通道：退出页面时恢复正常网络
      final wifi = WifiApController.instance;
      wifi.disconnect();
      wifi.forceWifiUsage(false);
    }
    super.dispose();
  }

  void _goToStep(LocalOTAStep step) {
    setState(() {
      _currentStep = step;
      _isProcessing = false;
      _errorMessage = null;
    });
    // 进入连接设备步骤时自动开始扫描+连接
    if (step == LocalOTAStep.connectDevice) {
      switch (widget.channel) {
        case LocalCommunicationChannel.ble:
          _autoScanAndConnectBle();
          break;
        case LocalCommunicationChannel.wifiAp:
          _autoScanAndConnect();
          break;
      }
    }
  }

  /// 是否处于不可退出的升级阶段：固件上传中或刷写轮询中。
  /// 此时退出会断开设备热点/BLE 连接，中断刷写有变砖风险
  bool get _upgradeInProgress =>
      _currentStep == LocalOTAStep.triggerUpgrade ||
      (_currentStep == LocalOTAStep.pushFirmware && _isProcessing);

  /// 升级中误触返回时弹出二次确认（PopScope canPop=false 时由
  /// 系统返回手势/导航栏返回键触发）
  Future<void> _confirmExitWhileUpgrading() async {
    final l10n = AppLocalizations.of(context)!;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.str('ota_exit_confirm_title', {})),
        content: Text(l10n.str('ota_exit_confirm_message', {})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.str('ota_keep_upgrading', {})),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.str('ota_exit_anyway', {}),
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (shouldExit == true && mounted) {
      // 用户确认退出：程序式 pop 不受 PopScope canPop 限制
      Navigator.of(context).pop();
    }
  }

  bool get _isBleChannel =>
      widget.channel == LocalCommunicationChannel.ble;

  /// 自动扫描热点并连接，整个流程只触发两次 setState（开始/结束）
  Future<void> _autoScanAndConnect() async {
    // 已在处理中或已连接成功，不重复触发
    if (_scanningWifi ||
        _autoConnecting ||
        _isProcessing ||
        _selectedAp != null) {
      return;
    }

    setState(() {
      _scanningWifi = true;
      _errorMessage = null;
    });
    try {
      // 从扫描页带入时热点可能已连上：先复用，避免重复扫描/切换网络
      if (await _isDeviceHotspotConnected()) {
        if (!mounted) return;
        setState(() {
          _scanningWifi = false;
          _autoConnecting = false;
        });
        _checkConnectionAndProceed();
        return;
      }

      final status = await Permission.location.request();
      if (!mounted) return;
      if (!status.isGranted && !status.isLimited) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _scanningWifi = false;
          _errorMessage = l10n.locationPermissionRequired;
        });
        return;
      }
      final serviceEnabled = await Permission.location.serviceStatus.isEnabled;
      if (!mounted) return;
      if (!serviceEnabled) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _scanningWifi = false;
          _errorMessage = l10n.enableLocationService;
        });
        return;
      }
      // 扫描前确保手机 WiFi 已开启（未开启弹窗引导，取消则中止扫描，Q1）
      if (!await ensureWifiEnabled(context)) {
        if (mounted) setState(() => _scanningWifi = false);
        return;
      }
      await WifiApController.instance.forceWifiUsage(true);
      final networks = await scanWifiNetworks();
      if (!mounted) return;

      final sn = widget.deviceSN.toUpperCase();
      final target = networks.where((n) {
        final ssid = (n.ssid ?? '').toUpperCase();
        return ssid == 'CS_INV_$sn' || ssid == 'CS-INV-$sn';
      }).toList();

      if (target.isEmpty) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _scanningWifi = false;
          _errorMessage =
              l10n.str('device_hotspot_not_found', {'sn': widget.deviceSN});
        });
        return;
      }

      // 找到热点，继续连接（不更新 UI，保持扫描中状态）
      final network = target.first;
      _selectedAp = network;
      final ssid = network.ssid ?? '';
      final cap = network.capabilities?.toUpperCase() ?? '';
      final isOpen =
          !cap.contains('WPA') && !cap.contains('WEP') && !cap.contains('EAP');

      final connected = await WifiApController.instance.connect(
        ssid,
        password: null,
        security: isOpen ? AppWifiSecurity.none : AppWifiSecurity.wpa,
        joinOnce: true,
      );
      if (!mounted) return;

      if (!connected) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _scanningWifi = false;
          _selectedAp = null;
          _errorMessage = l10n.str('connection_failed_retry', {'ssid': ssid});
        });
        return;
      }

      await WifiApController.instance.forceWifiUsage(true);
      await Future.delayed(const Duration(seconds: 3));

      final currentSsid = await WifiApController.instance.currentSsid;
      if (!mounted) return;
      if (currentSsid == null || !_isDeviceHotspotSsid(currentSsid)) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _scanningWifi = false;
          _selectedAp = null;
          _errorMessage = l10n.connectionFailedNoHotspot;
        });
        return;
      }

      // 连接成功，一次性更新状态
      setState(() {
        _scanningWifi = false;
        _autoConnecting = false;
      });

      // 自动测试连接并进入下一步
      _checkConnectionAndProceed();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _scanningWifi = false;
        _selectedAp = null;
        _errorMessage = l10n.str('scan_failed', {'error': '$e'});
      });
    }
  }

  /// 自动扫描BLE设备并连接
  Future<void> _autoScanAndConnectBle() async {
    // 已在处理中或已连接成功，不重复触发
    if (_scanningWifi || _autoConnecting || _isProcessing) {
      return;
    }

    setState(() {
      _scanningWifi = true;
      _errorMessage = null;
    });

    try {
      // 检查蓝牙权限
      final bluetoothStatus = await Permission.bluetooth.request();
      if (!mounted) return;
      if (!bluetoothStatus.isGranted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _scanningWifi = false;
          _errorMessage = l10n.str('bluetooth_permission_required', {});
        });
        return;
      }

      // 连接设备：服务内部优先复用扫描页建立的活跃会话（按 MAC/SN），
      // 无会话时按已知 MAC 直连，最后才扫描兜底。
      // 设备连上即停止广播，此处绝不能先扫描，否则必然"扫描不到设备"。
      final connected = await _communicationService.connectToDevice(
        deviceSN: widget.deviceSN,
        deviceIP: widget.deviceIP,
        macAddress: widget.deviceMac,
      );
      if (!mounted) return;

      if (!connected) {
        final failure = _bleService?.lastConnectFailure;
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _scanningWifi = false;
          _errorMessage = _bleFailureMessage(l10n, failure);
        });
        // 未绑定/鉴权失败：本机与设备之间缺少可用密钥，
        // 固件侧 OTA 通道要求已鉴权，扫描也无济于事，就地引导重新绑定
        if (failure == BleConnectFailure.notBound ||
            failure == BleConnectFailure.authFailed) {
          await _offerBleBind();
        }
        return;
      }

      // 连接成功，一次性更新状态
      setState(() {
        _scanningWifi = false;
        _autoConnecting = false;
      });

      // 自动测试连接并进入下一步
      _checkConnectionAndProceed();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _scanningWifi = false;
        _errorMessage = l10n.str('ble_scan_failed', {'error': '$e'});
      });
    }
  }

  /// BLE 通道通信服务（失败原因与目标 MAC 只在 BLE 实现上）
  BleCommunicationService? get _bleService {
    final service = _communicationService;
    return service is BleCommunicationService ? service : null;
  }

  /// 连接失败文案：按原因区分，避免把"未绑定/鉴权失败"误报成"扫描不到设备"
  String _bleFailureMessage(
    AppLocalizations l10n,
    BleConnectFailure? failure,
  ) {
    switch (failure) {
      case BleConnectFailure.adapterOff:
        return l10n.str('ble_bluetooth_off', {});
      case BleConnectFailure.notBound:
        return l10n.str('ble_ota_not_bound', {});
      case BleConnectFailure.authFailed:
        return l10n.str('ble_ota_auth_failed', {});
      case BleConnectFailure.unsupportedFirmware:
        return l10n.str('ble_ota_unsupported_firmware', {});
      case BleConnectFailure.otaBusy:
        return l10n.str('ble_ota_connect_busy', {});
      case BleConnectFailure.notFound:
      case BleConnectFailure.unknown:
      case null:
        return l10n.str('ble_connection_failed', {'sn': widget.deviceSN});
    }
  }

  /// 未绑定/鉴权失败时就地补救：输入铭牌 PIN 绑定设备 → 重试鉴权与连接。
  ///
  /// 本机密钥与设备不匹配（设备恢复出厂/重刷固件后常见）时清掉陈旧密钥重绑；
  /// 设备已被其他账号绑定时不动本机密钥，仅提示需在设备端解绑。
  Future<void> _offerBleBind() async {
    final l10n = AppLocalizations.of(context)!;
    final mac = _bleService?.targetMacAddress ?? widget.deviceMac;
    if (mac == null || mac.trim().isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.str('ble_ota_need_bind_title', {})),
        content: Text(l10n.str('ble_ota_need_bind_message', {})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.str('ble_ota_bind_action', {})),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final pin = await showBlePinBindDialog(
      context: context,
      deviceSn: widget.deviceSN,
    );
    if (pin == null || !mounted) return;

    final binding = getIt<BleBindingService>();
    final manager = getIt<BleDeviceManager>();
    final keyStore = getIt<BleDeviceKeyStore>();

    setState(() => _errorMessage = null);
    var outcome = await binding.bindAfterProvision(
      macAddress: mac,
      knownSn: widget.deviceSN,
      pin: pin,
    );

    // 本机留有陈旧 device_key（设备侧已无绑定）：清掉后重新绑定；
    // 本机无密钥却返回 alreadyBound，说明设备端已有密钥（换手机/重装应用后常见），
    // 绑定窗口已关闭，只能提示用户先在设备端解绑
    if (outcome == BindOutcome.alreadyBound) {
      final hasLocalKey = await manager.hasDeviceKey(widget.deviceSN);
      if (hasLocalKey) {
        await keyStore.delete(widget.deviceSN);
        outcome = await binding.bindAfterProvision(
          macAddress: mac,
          knownSn: widget.deviceSN,
          pin: pin,
        );
      }
    }
    if (!mounted) return;

    switch (outcome) {
      case BindOutcome.bound:
      case BindOutcome.needLoginForSync:
        // 绑定写入成功：立即鉴权并重试连接（同一会话，无需重新扫描）
        await manager.ensureAuthenticated(mac);
        if (!mounted) return;
        AppToast.show(
          context,
          l10n.str('ble_ota_bind_done', {}),
          type: ToastType.success,
        );
        await _autoScanAndConnectBle();
      case BindOutcome.alreadyBound:
        AppToast.show(
          context,
          l10n.str('ble_ota_bound_elsewhere', {}),
          type: ToastType.error,
        );
      case BindOutcome.invalidPin:
        AppToast.show(
          context,
          l10n.str('ble_ota_bind_invalid_pin', {}),
          type: ToastType.error,
        );
      case BindOutcome.locked:
        AppToast.show(
          context,
          l10n.str('ble_ota_bind_locked', {}),
          type: ToastType.error,
        );
      case BindOutcome.failed:
        AppToast.show(
          context,
          l10n.str('ble_ota_bind_failed', {}),
          type: ToastType.error,
        );
    }
  }

  Future<void> _startDownload() async {
    if (_metaFirmwareUrl == null ||
        _metaFileName == null ||
        widget.firmwareId == null) {
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      final path = await _downloadService.downloadFirmware(
        url: _metaFirmwareUrl!,
        fileName: _metaFileName!,
        firmwareId: widget.firmwareId!,
        // 持久化离线升级元数据，下次无网时也可从已下载列表选择升级
        expectedSize: _metaFileSize,
        expectedSha256: _metaFileSha256,
        deviceModel: _metaDeviceModel,
        targetChip: _metaTargetChip,
        version: _metaFirmwareVersion,
        signature: _metaReleaseSignature,
        securityVersion: _metaSecurityVersion,
      );
      if (mounted) {
        setState(() {
          _selectedFilePath = path;
          _selectedDownloaded = null;
          _isDownloading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _isDownloading = false;
          _errorMessage = l10n.str('download_failed', {'error': '$e'});
        });
      }
    }
  }

  Future<void> _checkConnectionAndProceed() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // 根据通道类型检查连接
    bool connected = false;
    String? currentSsid;

    if (widget.channel == LocalCommunicationChannel.wifiAp) {
      // WiFi 通道：检查当前WiFi连接
      final wifi = WifiApController.instance;
      try {
        currentSsid = await wifi.currentSsid;
        final isConnected = await wifi.isConnected();
        debugPrint('Current SSID: $currentSsid, isConnected: $isConnected');
        if (!mounted) return;

        if (!_isDeviceHotspotSsid(currentSsid)) {
          setState(() {
            _isProcessing = false;
            _errorMessage =
                l10n.str('connect_wifi_first', {'wifi': currentSsid ?? ''});
          });
          return;
        }
      } catch (e) {
        debugPrint('getSSID error: $e');
      }

      // 强制使用WiFi
      try {
        await wifi.forceWifiUsage(true);
        debugPrint('forceWifiUsage(true) called');
        await Future.delayed(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('forceWifiUsage error: $e');
      }
      if (!mounted) return;
    }

    // 尝试连接（两种通道都使用统一接口）
    connected = await _communicationService.testConnection(widget.deviceIP);
    debugPrint('Connection test result: $connected');
    if (!mounted) return;

    if (connected) {
      _goToStep(LocalOTAStep.pushFirmware);
      _startPushFirmware();
    } else {
      // 连接失败：按通道给出对应引导（BLE / WiFi AP 文案不能混用）
      setState(() {
        _isProcessing = false;
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.connectionFailed),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isBleChannel
                      ? l10n.str('ble_connection_failed', {})
                      : l10n.connectedHotspotCannotAccess,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.tryFollowing,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_isBleChannel) ...[
                  Text(l10n.str('ble_bluetooth_off')),
                  Text(l10n.str('ota_mode_ble_hint')),
                ] else ...[
                  Text(l10n.disableMobileData),
                  Text(l10n.ensureWifiConnected),
                  Text(l10n.waitAndRetry),
                  const SizedBox(height: 12),
                  Text(
                    '${l10n.currentHotspot}: $currentSsid',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${l10n.deviceIpLabel}: ${widget.deviceIP}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _checkConnectionAndProceed(); // 重试
                },
                child: Text(l10n.retry),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _startPushFirmware() async {
    final l10n = AppLocalizations.of(context)!;
    if (_selectedFilePath == null) {
      setState(() {
        _isProcessing = false;
        _result = LocalOTAResult.failed;
        _resultMessage = l10n.firmwareFileNotFound;
        _currentStep = LocalOTAStep.result;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _uploadProgress = 0.0;
      _errorMessage = null;
    });

    // 升级元数据：优先取选中的已下载固件（离线升级链路），
    // 缺失时回退路由参数（双 Tab 入口不传固件参数时，
    // 仅靠路由参数会导致校验必败，故必须支持离线元数据）
    final offline = _selectedDownloaded;
    final target = ((offline?.targetChip ?? _metaTargetChip) ?? 'esp')
        .trim()
        .toLowerCase();
    final version = (offline?.version ?? _metaFirmwareVersion)?.trim() ?? '';
    final sha256 =
        (offline?.sha256 ?? _metaFileSha256)?.trim().toLowerCase() ?? '';
    final signature =
        (offline?.signature ?? _metaReleaseSignature)?.trim() ?? '';
    final securityVersion =
        offline?.securityVersion ?? _metaSecurityVersion ?? 0;
    final firmwareModel =
        (offline?.deviceModel ?? _metaDeviceModel)?.trim() ?? '';
    final fileSize = offline?.fileSize ?? _metaFileSize ?? 0;

    final supportedChannels =
        offline?.supportedChannels ?? _metaSupportedChannels;
    final selectedChannel = widget.channel == LocalCommunicationChannel.ble
        ? 'ble'
        : 'wifi_ap';
    final supportsSelectedChannel = supportedChannels == null ||
        supportedChannels.any(
          (channel) => channel.trim().toLowerCase() == selectedChannel,
        );

    if ((target != 'esp' && target != 'arm') ||
        !supportsSelectedChannel ||
        fileSize <= 0 ||
        firmwareModel.isEmpty ||
        version.isEmpty ||
        sha256.isEmpty ||
        signature.isEmpty ||
        securityVersion <= 0) {
      setState(() {
        _isProcessing = false;
        _result = LocalOTAResult.failed;
        _resultMessage = l10n.str('ota_missing_metadata');
        _currentStep = LocalOTAStep.result;
      });
      return;
    }

    final manifest = LocalOtaManifest(
      target: target,
      taskId:
          'local-${offline?.firmwareId ?? widget.firmwareId ?? 0}-${DateTime.now().millisecondsSinceEpoch}',
      version: version,
      sha256: sha256,
      signature: signature,
      securityVersion: securityVersion,
    );

    // 执行引擎下沉：上传 → 触发 → 轮询 → 上报由 LocalOTAController 承担，
    // 页面仅渲染状态并提供热点重连等 UI 回调
    final controller = LocalOTAController(
      communication: _communicationService,
      repository: getIt<OtaRepository>(),
      channel: widget.channel,
      deviceSN: widget.deviceSN,
      deviceIP: widget.deviceIP,
      isHotspotConnected: widget.channel == LocalCommunicationChannel.wifiAp
          ? _isDeviceHotspotConnected
          : null,
      reconnectHotspot: widget.channel == LocalCommunicationChannel.wifiAp
          ? _reconnectDeviceHotspot
          : null,
      onTerminateConnection: _disconnectDeviceHotspot,
      syncQueue: getIt<LocalOtaResultSyncQueue>(),
    );
    _otaController
      ?..removeListener(_onControllerChanged)
      ..dispose();
    _otaController = controller;
    controller.addListener(_onControllerChanged);
    await controller.execute(
      filePath: _selectedFilePath!,
      manifest: manifest,
      fallbackVersion: _metaFirmwareVersion ?? '',
      firmwareModel: firmwareModel,
    );
  }

  /// 执行引擎状态 → 页面 UI 状态映射（页面仅渲染，不含流程逻辑）
  void _onControllerChanged() {
    final controller = _otaController;
    if (!mounted || controller == null) return;
    final s = controller.state;
    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _uploadProgress = _normalizeProgress(
        s.uploadProgress,
        source: 'upload',
      );
      _upgradeProgress = _normalizeProgress(
        s.upgradeProgress,
        source: 'upgrade',
      );

      if (s.statusOverrideKey != null) {
        _upgradeStatus = l10n.str(s.statusOverrideKey!, s.statusOverrideParams);
      } else if (s.deviceMessage.isNotEmpty) {
        _upgradeStatus = FirmwareModulePresentation.sanitizeCustomerCopy(
          s.deviceMessage,
          l10n,
        );
      } else if (s.deviceStatus.isNotEmpty) {
        _upgradeStatus = _mapStatus(s.deviceStatus);
      }

      switch (s.phase) {
        case LocalOTAPhase.idle:
        case LocalOTAPhase.uploading:
          break;
        case LocalOTAPhase.upgrading:
          if (_currentStep != LocalOTAStep.triggerUpgrade) {
            _currentStep = LocalOTAStep.triggerUpgrade;
            _errorMessage = null;
          }
        case LocalOTAPhase.success:
          _isProcessing = false;
          _result = LocalOTAResult.success;
          _newVersion = s.newVersion;
          _currentStep = LocalOTAStep.result;
        case LocalOTAPhase.failed:
          _isProcessing = false;
          _result = LocalOTAResult.failed;
          final err = s.error;
          _resultMessage = err != null
              ? (OtaErrorMapper.carriesDetail(err)
                  ? l10n.str(
                      OtaErrorMapper.l10nKeyOf(err),
                      {'error': '$err'},
                    )
                  : l10n.str(OtaErrorMapper.l10nKeyOf(err)))
              : (s.deviceMessage.isNotEmpty
                  ? FirmwareModulePresentation.sanitizeCustomerCopy(
                      s.deviceMessage,
                      l10n,
                    )
                  : l10n.upgradeFailed);
          _currentStep = LocalOTAStep.result;
        case LocalOTAPhase.timedOut:
          _isProcessing = false;
          _result = LocalOTAResult.failed;
          _resultMessage = l10n.upgradeTimeout;
          _currentStep = LocalOTAStep.result;
      }
    });
  }

  /// 升级结束后断开连接，恢复正常网络
  void _disconnectDeviceHotspot() {
    if (widget.channel == LocalCommunicationChannel.ble) {
      // BLE通道：断开BLE连接
      _communicationService.disconnect();
    } else {
      // WiFi通道：断开WiFi热点
      final wifi = WifiApController.instance;
      wifi.disconnect();
      wifi.forceWifiUsage(false);
    }
  }

  /// 检测当前 WiFi 是否仍连接到设备热点
  Future<bool> _isDeviceHotspotConnected() async {
    try {
      final ssid = await WifiApController.instance.currentSsid;
      return _isDeviceHotspotSsid(ssid);
    } catch (_) {
      return false;
    }
  }

  /// 设备热点 SSID 统一判定（兼容 CS_INV_xxx / CS-INV-xxx 两种格式），
  /// 避免各入口用 startsWith/contains 不一致导致误判"未连接热点"
  static bool _isDeviceHotspotSsid(String? ssid) {
    if (ssid == null || ssid.isEmpty || ssid == '<unknown ssid>') {
      return false;
    }
    final upper = ssid.toUpperCase();
    return upper.contains('CS_INV') || upper.contains('CS-INV');
  }

  /// 尝试重新连接设备热点
  Future<bool> _reconnectDeviceHotspot() async {
    try {
      // 重连前确保手机 WiFi 已开启（未开启引导开启，取消则中止，Q1）；
      // 对话框期间页面可能已退出
      if (!mounted) return false;
      if (!await ensureWifiEnabled(context)) return false;
      if (!mounted) return false;
      final wifi = WifiApController.instance;
      await wifi.forceWifiUsage(true);
      final networks = await scanWifiNetworks();
      if (!mounted) return false;
      final sn = widget.deviceSN.toUpperCase();
      final target = networks.where((n) {
        final ssid = (n.ssid ?? '').toUpperCase();
        return ssid == 'CS_INV_$sn' || ssid == 'CS-INV-$sn';
      }).toList();

      if (target.isEmpty) return false;

      final network = target.first;
      final ssid = network.ssid ?? '';
      final cap = network.capabilities?.toUpperCase() ?? '';
      final isOpen =
          !cap.contains('WPA') && !cap.contains('WEP') && !cap.contains('EAP');

      final connected = await wifi.connect(
        ssid,
        password: null,
        security: isOpen ? AppWifiSecurity.none : AppWifiSecurity.wpa,
        joinOnce: true,
      );
      if (!connected) return false;

      await wifi.forceWifiUsage(true);
      await Future.delayed(const Duration(seconds: 3)); // 等待IP分配
      return true;
    } catch (_) {
      return false;
    }
  }

  String _mapStatus(String status) {
    final l10n = AppLocalizations.of(context)!;
    switch (localOtaStatusKind(status)) {
      case LocalOtaStatusKind.idle:
        return l10n.idleStatus;
      case LocalOtaStatusKind.downloading:
        return l10n.downloading;
      case LocalOtaStatusKind.uploading:
        return l10n.uploadingStatus;
      case LocalOtaStatusKind.verifying:
        return l10n.verifying;
      case LocalOtaStatusKind.done:
        return l10n.done;
      case LocalOtaStatusKind.failure:
        return l10n.failure;
      case LocalOtaStatusKind.installing:
        return l10n.installingFirmware;
      case LocalOtaStatusKind.unknown:
        return status;
    }
  }

  double _normalizeProgress(double value, {required String source}) {
    return normalizeLocalOtaProgress(
      value,
      onInvalid: (invalidValue) {
        debugPrint('[LocalOTA] Invalid $source progress: $invalidValue');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final body = Column(
      children: [
        _buildStepIndicator(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: _buildCurrentStepContent(),
          ),
        ),
      ],
    );
    // 嵌入模式：由外层页面提供 AppBar 与 Scaffold
    if (widget.embedded) {
      return body;
    }
    // 升级中拦截返回（系统手势/导航栏返回键/AppBar 返回按钮），
    // 二次确认后才允许退出，防止误退断热点导致设备变砖
    return PopScope(
      canPop: !_upgradeInProgress,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmExitWhileUpgrading();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            l10n.localFirmwareUpgrade,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.sp),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          actions: [
            // 显示当前使用的通道类型
            Padding(
              padding: EdgeInsets.only(right: 16.w),
              child: Chip(
                label: Text(
                  widget.channel == LocalCommunicationChannel.ble
                      ? 'BLE'
                      : 'WiFi',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: widget.channel == LocalCommunicationChannel.ble
                        ? Colors.blue
                        : Colors.orange,
                  ),
                ),
                backgroundColor: widget.channel == LocalCommunicationChannel.ble
                    ? Colors.blue.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                side: BorderSide.none,
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        body: body,
      ),
    );
  }

  Widget _buildStepIndicator() {
    const steps = LocalOTAStep.values;
    final currentIndex = steps.indexOf(_currentStep);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      color: AppColor.surfaceContainer(context),
      child: Row(
        children: steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          final isCompleted = currentIndex > index;
          final isCurrent = currentIndex == index;

          Color stepColor;
          if (isCompleted) {
            stepColor = AppColors.successLight;
          } else if (isCurrent) {
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
                        child: isCompleted
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
                        _stepLabel(step),
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: isCurrent || isCompleted
                              ? AppColor.textPrimary(context)
                              : AppColor.textSecondary(context),
                          fontWeight:
                              isCurrent ? FontWeight.w600 : FontWeight.w400,
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
                    color: isCompleted
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

  String _stepLabel(LocalOTAStep step) {
    final l10n = AppLocalizations.of(context)!;
    switch (step) {
      case LocalOTAStep.selectFirmware:
        return l10n.selectFirmware;
      case LocalOTAStep.connectDevice:
        return l10n.connectDevice;
      case LocalOTAStep.pushFirmware:
        return l10n.pushFirmware;
      case LocalOTAStep.triggerUpgrade:
        return l10n.upgrading;
      case LocalOTAStep.result:
        return l10n.upgradeResult;
    }
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case LocalOTAStep.selectFirmware:
        return _buildSelectFirmwareStep();
      case LocalOTAStep.connectDevice:
        return _buildConnectDeviceStep();
      case LocalOTAStep.pushFirmware:
        return _buildPushFirmwareStep();
      case LocalOTAStep.triggerUpgrade:
        return _buildTriggerUpgradeStep();
      case LocalOTAStep.result:
        return _buildResultStep();
    }
  }

  Widget _buildSelectFirmwareStep() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDeviceInfoCard(),
        SizedBox(height: 16.h),
        Container(
          padding: EdgeInsets.all(16.w),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.selectFirmware,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColor.textPrimary(context),
                ),
              ),
              SizedBox(height: 12.h),
              if (_selectedFilePath != null)
                _buildSelectedFirmwareInfo()
              else if (_isDownloading)
                _buildDownloadingProgress()
              else if (_firmwareListLoading)
                _buildFirmwareListLoading()
              else if (_downloadedFirmwares.isNotEmpty)
                _buildDownloadedFirmwareList()
              else
                Text(
                  l10n.firmwareDownloadHint,
                  style: TextStyle(
                      fontSize: 13.sp, color: AppColor.textHint(context)),
                ),
              if (_errorMessage != null) ...[
                SizedBox(height: 8.h),
                Text(
                  _errorMessage!,
                  style: TextStyle(fontSize: 12.sp, color: AppColors.error),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 24.h),
        if (_selectedFilePath == null &&
            !_isDownloading &&
            _metaFirmwareUrl != null)
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: _startDownload,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 0,
              ),
              child: Text(
                l10n.downloadFirmware,
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        if (_selectedFilePath != null)
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: () => _goToStep(LocalOTAStep.connectDevice),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 0,
              ),
              child: Text(
                l10n.next,
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDownloadingProgress() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        SizedBox(height: 8.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(8.r),
          child: LinearProgressIndicator(
            value: _downloadProgress > 0 ? _downloadProgress : null,
            minHeight: 8.h,
            backgroundColor: AppColor.border(context),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          _downloadProgress > 0
              ? '${(_downloadProgress * 100).toStringAsFixed(1)}%'
              : '${l10n.downloading}...',
          style: TextStyle(fontSize: 12.sp, color: AppColors.primary),
        ),
      ],
    );
  }

  Widget _buildSelectedFirmwareInfo() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.badgeNormalBg,
        borderRadius: BorderRadius.circular(10.r),
        border:
            Border.all(color: AppColors.successLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 20.sp,
            color: AppColors.successLight,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.firmwareReady,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.successLight,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _selectedFileName() ??
                      widget.firmwareFileName ??
                      _selectedFilePath!.split('/').last,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColor.textSecondary(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 当前选中文件在已下载列表中的文件名（离线选择场景优先展示所选条目文件名）
  String? _selectedFileName() {
    final path = _selectedFilePath;
    if (path == null) return null;
    for (final item in _downloadedFirmwares) {
      if (item.filePath == path) return item.fileName;
    }
    return null;
  }

  Widget _buildFirmwareListLoading() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        SizedBox(
          width: 14.w,
          height: 14.w,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
        SizedBox(width: 8.w),
        Text(
          l10n.loading,
          style: TextStyle(fontSize: 13.sp, color: AppColor.textHint(context)),
        ),
      ],
    );
  }

  /// 已下载固件列表（点击条目即可选中，无需联网）
  Widget _buildDownloadedFirmwareList() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.downloadedFirmwareList,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            color: AppColor.textSecondary(context),
          ),
        ),
        SizedBox(height: 8.h),
        ..._downloadedFirmwares.map(
          (item) => _buildDownloadedFirmwareTile(item),
        ),
      ],
    );
  }

  Widget _buildDownloadedFirmwareTile(DownloadedFirmwareInfo item) {
    final selected = _selectedFilePath == item.filePath;
    final l10n = AppLocalizations.of(context)!;
    final displayName = _downloadedDisplayName(item);
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.06)
            : AppColors.badgeNormalBg,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: selected ? AppColors.primary : AppColor.border(context),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: () => setState(() {
          _selectedFilePath = item.filePath;
          // 离线升级链路：升级元数据取自持久化的下载记录
          _selectedDownloaded = item;
          _errorMessage = null;
        }),
        child: Padding(
          padding: EdgeInsets.all(10.w),
          child: Row(
            children: [
              Icon(
                Icons.memory_rounded,
                size: 18.sp,
                color:
                    selected ? AppColors.primary : AppColor.textHint(context),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      _formatFirmwareSize(item.fileSize),
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColor.textHint(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 18.sp,
                  color: AppColors.primary,
                ),
              SizedBox(width: 4.w),
              // 删除已下载固件：释放本地空间，删除后需重新下载才能本地升级
              IconButton(
                onPressed: () => _confirmDeleteDownloaded(item),
                tooltip: l10n.str('downloaded_firmware_delete'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: 32.w, minHeight: 32.w),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 18.sp,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 删除某个已下载固件（二次确认；删除当前选中项时清空选择）
  Future<void> _confirmDeleteDownloaded(DownloadedFirmwareInfo item) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.str('downloaded_firmware_delete')),
        content: Text(
          l10n.str('downloaded_firmware_delete_confirm', {
            'name': _downloadedDisplayName(item),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(l10n.str('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 先清空选择再删除：删除后列表里已无该条目，
    // 否则 _loadDownloadedFirmwares 会保留指向已删文件的陈旧选中路径
    if (_selectedDownloaded?.firmwareId == item.firmwareId ||
        _selectedFilePath == item.filePath) {
      setState(() {
        _selectedFilePath = null;
        _selectedDownloaded = null;
      });
    }
    try {
      await _downloadService.deleteDownloadedFirmware(item.firmwareId);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        l10n.str('downloaded_firmware_delete_failed'),
        type: ToastType.error,
      );
      return;
    }
    if (!mounted) return;
    await _loadDownloadedFirmwares();
    if (!mounted) return;
    AppToast.show(
      context,
      l10n.str('downloaded_firmware_deleted'),
      type: ToastType.success,
    );
  }

  /// 已下载固件的展示名（模块名 · 版本，缺失时回退文件名）
  String _downloadedDisplayName(DownloadedFirmwareInfo item) {
    final l10n = AppLocalizations.of(context)!;
    final module = FirmwareModulePresentation.fromTarget(item.targetChip);
    final version = item.version?.trim() ?? '';
    if (version.isEmpty) {
      return module.displayLabel(l10n).isEmpty
          ? item.fileName
          : module.displayLabel(l10n);
    }
    return '${module.displayLabel(l10n)} · $version';
  }

  String _formatFirmwareSize(int size) {
    if (size <= 0) return '';
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (size >= 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '$size B';
  }

  Widget _buildConnectDeviceStep() {
    final l10n = AppLocalizations.of(context)!;

    // 判断是否正在自动流程中（扫描 + 连接）
    final isInProgress = _scanningWifi || _autoConnecting || _isProcessing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 小烁 OTA 引导插画（横版）：设备连接步骤引导（美术路由 C7/guide-ota）
        ClipRRect(
          borderRadius: BorderRadius.circular(14.r),
          child: Image.asset(
            CsergyAssets.xiaoshuoOtaGuide,
            width: double.infinity,
            height: 150.h,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(height: 16.h),
        _buildDeviceInfoCard(),
        SizedBox(height: 16.h),
        Center(
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              color: AppColor.primarySoft(context),
              borderRadius: BorderRadius.circular(14.r),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                if (isInProgress) ...[
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    _isProcessing
                        ? l10n.checkConnection
                        : _selectedAp != null
                            ? (_isBleChannel
                                ? l10n.str('connecting_ble_device',
                                    {'sn': widget.deviceSN},)
                                : l10n.str(
                                    'connecting_to',
                                    {'ssid': _selectedAp?.ssid ?? ''},
                                  ))
                            : (_isBleChannel
                                ? l10n.str('scanning_ble_device', {})
                                : l10n.scanningDeviceHotspot),
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
                ] else if (_selectedAp != null && _errorMessage == null) ...[
                  Icon(
                    _isBleChannel
                        ? Icons.bluetooth_rounded
                        : Icons.wifi_rounded,
                    size: 48.sp,
                    color: AppColors.successLight,
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    l10n.connected,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.successLight,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    _isBleChannel
                        ? widget.deviceSN
                        : (_selectedAp!.ssid ?? ''),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
                ] else ...[
                  Icon(
                    _isBleChannel
                        ? Icons.bluetooth_searching_rounded
                        : Icons.wifi_find_rounded,
                    size: 48.sp,
                    color: AppColors.primary,
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    _isBleChannel ? l10n.connectDevice : l10n.connectDeviceAp,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    _isBleChannel
                        ? l10n.str('ota_mode_ble_hint')
                        : l10n.autoScanHint,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColor.textSecondary(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (!_isBleChannel) ...[
                    SizedBox(height: 4.h),
                    Text(
                      '${l10n.deviceIpLabel}: ${widget.deviceIP}',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        // 扫描按钮移到状态卡下方：作为次要操作，避免顶在页面最上方显得突兀
        if (!isInProgress && _selectedAp == null) ...[
          SizedBox(height: 12.h),
          SizedBox(
            width: double.infinity,
            height: 40.h,
            child: OutlinedButton.icon(
              onPressed: widget.channel == LocalCommunicationChannel.ble
                  ? _autoScanAndConnectBle
                  : _autoScanAndConnect,
              icon: Icon(
                widget.channel == LocalCommunicationChannel.ble
                    ? Icons.bluetooth_searching_rounded
                    : Icons.refresh_rounded,
                size: 18.sp,
              ),
              label: Text(
                widget.channel == LocalCommunicationChannel.ble
                    ? l10n.str('rescan_ble_device', {})
                    : l10n.rescanHotspot,
                style: TextStyle(fontSize: 13.sp),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.4),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.r),
                ),
              ),
            ),
          ),
        ],
        if (_errorMessage != null) ...[
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.all(12.w),
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
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        SizedBox(height: 24.h),
        SizedBox(
          width: double.infinity,
          height: 48.h,
          child: ElevatedButton(
            onPressed: isInProgress ? null : _checkConnectionAndProceed,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isInProgress ? AppColor.textHint(context) : AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              elevation: 0,
            ),
            child: _isProcessing
                ? SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    l10n.checkConnection,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPushFirmwareStep() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDeviceInfoCard(),
        SizedBox(height: 16.h),
        Container(
          padding: EdgeInsets.all(20.w),
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
          child: Column(
            children: [
              Icon(
                Icons.cloud_upload_rounded,
                size: 48.sp,
                color: AppColors.primary,
              ),
              SizedBox(height: 12.h),
              Text(
                l10n.pushingFirmware,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColor.textPrimary(context),
                ),
              ),
              SizedBox(height: 20.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: LinearProgressIndicator(
                  value: _uploadProgress,
                  minHeight: 10.h,
                  backgroundColor: AppColor.border(context),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              SizedBox(height: 10.h),
              Text(
                '${(_uploadProgress * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColor.textPrimary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTriggerUpgradeStep() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDeviceInfoCard(),
        SizedBox(height: 16.h),
        Container(
          padding: EdgeInsets.all(20.w),
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
          child: Column(
            children: [
              Icon(
                Icons.system_update_rounded,
                size: 48.sp,
                color: AppColors.primary,
              ),
              SizedBox(height: 12.h),
              Text(
                _upgradeStatus.isNotEmpty ? _upgradeStatus : l10n.upgrading,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColor.textPrimary(context),
                ),
              ),
              SizedBox(height: 20.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: LinearProgressIndicator(
                  value: _upgradeProgress,
                  minHeight: 10.h,
                  backgroundColor: AppColor.border(context),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              SizedBox(height: 10.h),
              Text(
                '${(_upgradeProgress * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColor.textPrimary(context),
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                l10n.doNotDisconnect,
                style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultStep() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _buildDeviceInfoCard(),
        SizedBox(height: 16.h),
        Container(
          padding: EdgeInsets.all(24.w),
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
          child: Column(
            children: [
              if (_result == LocalOTAResult.success) ...[
                // 小烁成功动作插画：本地 OTA 升级成功（美术路由 C2/success）
                Image.asset(
                  CsergyAssets.xiaoshuoSuccess,
                  width: 108.w,
                  height: 108.w,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: 16.h),
                Text(
                  l10n.upgradeSuccess,
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColor.textPrimary(context),
                  ),
                ),
                if (_newVersion != null) ...[
                  SizedBox(height: 8.h),
                  Text(
                    l10n.str('new_version_label', {'version': _newVersion!}),
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
                ],
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    // pop(true)：供升级包串行编排器链式推进下一芯片
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.successLight,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      l10n.done,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              if (_result == LocalOTAResult.failed) ...[
                // 小烁警示动作插画：本地 OTA 升级失败（美术路由 C5/failure）
                Image.asset(
                  CsergyAssets.xiaoshuoWarning,
                  width: 108.w,
                  height: 108.w,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: 16.h),
                Text(
                  l10n.upgradeFailed,
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColor.textPrimary(context),
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  _resultMessage ?? l10n.unknown,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: AppColor.textSecondary(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _result = null;
                        _resultMessage = null;
                        _selectedAp = null;
                        _isProcessing = false;
                      });
                      _goToStep(LocalOTAStep.connectDevice);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      l10n.retry,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              if (_result == LocalOTAResult.verifyFailed) ...[
                Icon(
                  Icons.warning_rounded,
                  size: 64.sp,
                  color: AppColors.warning,
                ),
                SizedBox(height: 16.h),
                Text(
                  l10n.firmwareVerifyFailed,
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColor.textPrimary(context),
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  l10n.firmwareCorruptedHint,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: AppColor.textSecondary(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (widget.firmwareId != null) {
                        await _downloadService
                            .deleteDownloadedFirmware(widget.firmwareId!);
                      }
                      if (!mounted) return;
                      setState(() {
                        _selectedFilePath = null;
                        _currentStep = LocalOTAStep.selectFirmware;
                        _result = null;
                        _resultMessage = null;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      l10n.redownload,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceInfoCard() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.all(16.w),
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
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: AppColor.primarySoft(context),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(
              Icons.devices_rounded,
              size: 18.sp,
              color: AppColors.primary,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.currentDevice,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColor.textPrimary(context),
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  widget.deviceSN,
                  style: TextStyle(
                      fontSize: 12.sp, color: AppColor.textHint(context)),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: AppColor.primarySoft(context),
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Text(
              // BLE 通道无设备 IP，展示通道标识，避免与 WiFi AP 混淆
              _isBleChannel ? 'BLE' : widget.deviceIP,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
