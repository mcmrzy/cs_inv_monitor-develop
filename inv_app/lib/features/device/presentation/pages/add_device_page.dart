import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart'
    hide DeviceBindRequested, DeviceBindSuccess;
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/ambient_light_service.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_direct_service.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/utils/sn_utils.dart';
import 'package:inv_app/core/utils/qr_scan_guard.dart';
import 'package:inv_app/core/utils/api_response.dart';
import 'package:inv_app/core/widgets/station_selector_sheet.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/ble_pin_bind_dialog.dart';
import 'package:inv_app/features/device/presentation/widgets/add_device_pin_dialog.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class AddDevicePage extends StatefulWidget {
  final int? stationId;

  const AddDevicePage({super.key, this.stationId});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage>
    with SingleTickerProviderStateMixin {
  final _snController = TextEditingController();
  final _pinController = TextEditingController();

  late TabController _tabController;
  bool _scanning = false;
  MobileScannerController? _cameraController;
  final _qrScanGuard = QrScanGuard();
  String _lastScanned = '';
  String _scannedPin = '';

  int _sessionBoundCount = 0;
  bool _bindSuccess = false;
  List<_ScanHistoryEntry> _scanHistory = [];

  /// 暗光检测补光（默认开启）：持续扫不到码时自动点亮，
  /// 扫码成功后自动熄灭并重新计时
  bool _autoTorch = true;

  /// 补光灯真实状态（来自 controller.value.torchState，非本地猜测）
  bool _torchOn = false;
  bool _torchAvailable = true;

  /// 当前补光灯是否由暗光检测自动点亮（区别于手动点亮）
  bool _autoTorchLit = false;

  /// 最近一次成功解码时间（无传感器时的启发式基准）
  DateTime _lastDetectAt = DateTime.now();

  /// 暗光检测定时器：周期性判断是否需要自动点灯
  Timer? _lowLightTimer;

  /// 环境光照度订阅（有传感器时按真实亮度判断）
  StreamSubscription<double>? _luxSub;

  /// 连续无成功解码多久后判定为暗光并点亮补光灯（启发式兜底）
  static const Duration _lowLightThreshold = Duration(seconds: 5);

  /// 光照度低于该值（lux）判定为暗光，自动点亮补光灯
  static const double _luxDarkThreshold = 12;

  /// 光照度高于该值（lux）判定为光线恢复，熄灭自动补光（滞回防抖动）
  static const double _luxBrightThreshold = 30;

  int? _selectedStationId;
  String? _selectedStationName;

  // --- BLE 设备扫描状态 ---
  bool _bleEnabled = false;
  bool _bleAdapterOn = false;
  bool _bleScanning = false;

  /// 绑定弹窗打开中标记，防止快速连点重复弹窗（触发 Duplicate GlobalKeys）
  bool _bleBindDialogOpen = false;
  List<BleDiscoveredDevice> _bleDevices = [];
  Map<String, bool> _bleBoundByMac = {};
  StreamSubscription<List<BleDiscoveredDevice>>? _bleDirectSub;
  StreamSubscription<BleScanResult>? _standaloneScanSub;

  /// BLE 广播名前缀（形如 CS_INV_SN / CS-INV-SN），去掉后即为 SN
  static final RegExp _snPrefixPattern =
      RegExp(r'^CS[-_]INV[-_]', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    _selectedStationId = widget.stationId;
    _tabController = TabController(length: 2, vsync: this);
    // 注意：不在构造期传 torchEnabled——此时相机尚未就绪，
    // 部分机型不生效；改为相机初始化完成后按 _autoTorch 点亮
    _cameraController = MobileScannerController();
    _cameraController!.addListener(_onCameraStateChanged);
    _loadScanHistory();
    _loadStationName();
    _initBleScan();
  }

  Future<void> _loadStationName() async {
    if (_selectedStationId == null) return;
    try {
      final dio = getIt<Dio>();
      final res = await dio.get('/stations/$_selectedStationId');
      if (res.statusCode == 200 && mounted) {
        final data = unwrapApiResponse<Map<String, dynamic>>(
          res.data,
          validate: (value) => value is Map<String, dynamic>,
          expected: 'an object',
        );
        final station = data['station'];
        if (station is! Map) {
          throw const FormatException('station detail must contain station');
        }
        final name =
            (station['station_name'] ?? station['name'] ?? '').toString();
        if (name.isNotEmpty) {
          setState(() => _selectedStationName = name);
        }
      }
    } catch (_) {}
  }

  /// 相机状态变化：同步补光灯真实状态到 UI；
  /// 相机就绪且开启自动补光时点亮一次
  void _onCameraStateChanged() {
    final controller = _cameraController;
    if (controller == null || !mounted) return;
    final value = controller.value;
    final available = value.torchState != TorchState.unavailable;
    final torchOn = value.torchState == TorchState.on ||
        value.torchState == TorchState.auto;

    // 相机就绪后启动暗光检测（持续扫不到码才自动点灯）
    if (value.isInitialized) {
      _startLowLightWatch();
    }

    if (torchOn != _torchOn || available != _torchAvailable) {
      setState(() {
        _torchOn = torchOn;
        _torchAvailable = available;
      });
    }
  }

  /// 显式设置补光灯开关（状态一致时不做无谓 toggle）
  void _setTorch(bool enable) {
    final controller = _cameraController;
    if (controller == null) return;
    final state = controller.value.torchState;
    if (state == TorchState.unavailable) return;
    final isOn = state == TorchState.on || state == TorchState.auto;
    if (isOn != enable) {
      unawaited(controller.toggleTorch());
    }
  }

  /// 暗光检测补光开关：关闭时立即熄灭由检测自动点亮的灯
  void _toggleAutoTorch() {
    setState(() => _autoTorch = !_autoTorch);
    if (!_autoTorch && _autoTorchLit) {
      _autoTorchLit = false;
      _setTorch(false);
    }
    // 切换开关视为重新开始观察，避免立即点灯
    _lastDetectAt = DateTime.now();
  }

  /// 启动暗光检测：
  /// 优先按环境光传感器的真实照度判断（lux 太低点灯、恢复后熄灯）；
  /// 无传感器时回退「连续扫不到码达阈值即点灯」启发式
  void _startLowLightWatch() {
    if (_lowLightTimer != null) return;
    _lastDetectAt = DateTime.now();
    // 真实亮度信号（Android 环境光传感器）
    AmbientLightService.start();
    _luxSub ??= AmbientLightService.luxStream.listen(_onLuxChanged);
    _lowLightTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_autoTorch || _autoTorchLit) return;
      // 传感器可用 → 完全按亮度判断，不走启发式
      if (AmbientLightService.supported) return;
      final controller = _cameraController;
      if (controller == null || !controller.value.isInitialized) return;
      final state = controller.value.torchState;
      if (state == TorchState.unavailable) return;
      if (DateTime.now().difference(_lastDetectAt) < _lowLightThreshold) {
        return;
      }
      // 已亮（手动）则不重复操作
      if (state == TorchState.on || state == TorchState.auto) return;
      _autoTorchLit = true;
      unawaited(controller.toggleTorch());
    });
  }

  /// 环境光传感器事件：暗光点灯、亮度恢复熄掉自动补光（双阈值滞回防抖动）
  void _onLuxChanged(double lux) {
    if (!mounted || !_autoTorch) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final state = controller.value.torchState;
    if (state == TorchState.unavailable) return;
    if (lux < _luxDarkThreshold && !_autoTorchLit) {
      if (state != TorchState.on && state != TorchState.auto) {
        _autoTorchLit = true;
        unawaited(controller.toggleTorch());
      }
    } else if (lux > _luxBrightThreshold && _autoTorchLit) {
      _autoTorchLit = false;
      _setTorch(false);
    }
  }

  /// 成功解码：重置暗光计时；补光灯若为暗光自动点亮则自动熄灭
  void _onDetectSuccess() {
    _lastDetectAt = DateTime.now();
    if (_autoTorchLit) {
      _autoTorchLit = false;
      _setTorch(false);
    }
  }

  @override
  void dispose() {
    _lowLightTimer?.cancel();
    _luxSub?.cancel();
    AmbientLightService.stop();
    _bleDirectSub?.cancel();
    _standaloneScanSub?.cancel();
    _snController.dispose();
    _pinController.dispose();
    _tabController.dispose();
    _cameraController?.removeListener(_onCameraStateChanged);
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanning) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;
    // 识别到二维码即说明光线足够，重置暗光计时并熄灭自动补光
    _onDetectSuccess();
    final raw = barcode.rawValue!.trim();
    if (raw.isEmpty || !_qrScanGuard.tryAcquire(raw)) return;

    _scanning = true;

    final qr = parseQRCode(raw);
    if (qr == null) {
      _lastScanned = raw;
      _scannedPin = '';
      _qrScanGuard.release();
      _scanning = false;
      if (mounted) {
        AppToast.show(
            context, '${AppLocalizations.of(context)!.qrNotRecognized}:\n$raw',
            type: ToastType.error);
      }
      return;
    }

    final sn = qr.sn.toUpperCase();
    final pin = qr.pin ?? '';

    if (!validateSNFormat(sn)) {
      _lastScanned = sn;
      _scannedPin = '';
      _qrScanGuard.release();
      _scanning = false;
      if (mounted) {
        AppToast.show(context,
            '${AppLocalizations.of(context)!.snFormatError}:\n${formatSNForDisplay(sn)}',
            type: ToastType.error);
      }
      return;
    }

    if (!validateCheckDigitOnly(sn)) {
      _scanning = false;
      if (mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.checksumMismatch),
            content: Text(
              'SN: ${formatSNForDisplay(sn)}\n${AppLocalizations.of(context)!.checksumMismatch}\n${AppLocalizations.of(context)!.snConfirmAdd}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(AppLocalizations.of(context)!.continueAdd),
              ),
            ],
          ),
        );
        if (confirm != true) {
          _qrScanGuard.release(resetPayload: true);
          return;
        }
      } else {
        _qrScanGuard.release(resetPayload: true);
        return;
      }
      _scanning = true;
    }

    _lastScanned = sn;
    _scannedPin = pin;
    if (pin.isNotEmpty) {
      // 二维码带 PIN → 跳 BLE 直连绑定页（扫描匹配 SN，离网可用）
      await _openQrBindPage(sn, pin);
      return;
    }
    // 二维码无 PIN → 弹窗要求输入铭牌 PIN（云端绑定同样强制 PIN 校验）
    await _promptPinAndBind(sn);
  }

  /// 扫码/手动二维码无 PIN 时的补充输入：弹窗要求 6 位铭牌 PIN，
  /// 随后进入 BLE 直连绑定页（后端严格模式：无 PIN 无法绑定）。
  Future<void> _promptPinAndBind(String sn) async {
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AddDevicePinDialog(
        title: AppLocalizations.of(ctx)!.pinInputTitle,
        hintText: AppLocalizations.of(ctx)!.pinInputHint,
        invalidPinMessage: AppLocalizations.of(ctx)!.pinLengthError,
        cancelLabel: AppLocalizations.of(ctx)!.cancel,
        confirmLabel: AppLocalizations.of(ctx)!.confirm,
      ),
    );
    if (pin == null || !mounted) {
      // 用户取消，重置扫码状态避免一直转圈
      _qrScanGuard.release(resetPayload: true);
      if (mounted) setState(() => _scanning = false);
      return;
    }
    if (pin.length != 6) {
      if (mounted) {
        _qrScanGuard.release(resetPayload: true);
        setState(() => _scanning = false);
        AppToast.show(context, AppLocalizations.of(context)!.pinLengthError,
            type: ToastType.info);
      }
      return;
    }
    _scannedPin = pin;
    await _openQrBindPage(sn, pin);
  }

  /// Pause the camera while the bind page is open so one QR code cannot push
  /// multiple bind routes. Resume scanning only after that route is closed.
  Future<void> _openQrBindPage(String sn, String pin) async {
    try {
      await _cameraController?.pause();
    } catch (_) {
      // The camera may not be attached in widget tests or during teardown.
    }
    if (!mounted) return;

    try {
      await context.push(
        '/device/qr-bind?sn=${Uri.encodeQueryComponent(sn)}&pin=${Uri.encodeQueryComponent(pin)}',
      );
    } finally {
      if (!mounted) return;
      _qrScanGuard.release(resetPayload: true);
      setState(() {
        _scanning = false;
        _lastScanned = '';
        _scannedPin = '';
      });
      try {
        await _cameraController?.start();
      } catch (_) {
        // The scanner will report its own state if restarting is unavailable.
      }
    }
  }

  Future<(int, String)?> _showStationSelector() async {
    final completer = Completer<(int, String)?>();
    if (!mounted) {
      completer.complete(null);
      return completer.future;
    }
    context.read<StationBloc>().add(StationSummaryRequested());

    if (!mounted) {
      completer.complete(null);
      return completer.future;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) => StationSelectorSheet(
        onSelected: (id, name) {
          Navigator.pop(ctx);
          completer.complete((id, name));
        },
        onCancel: () {
          Navigator.pop(ctx);
          completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  Future<void> _manualBind() async {
    final raw = _snController.text.trim();
    if (raw.isEmpty) {
      AppToast.show(context, AppLocalizations.of(context)!.pleaseInputSn,
          type: ToastType.info);
      return;
    }

    final qr = parseQRCode(raw);
    final sn = qr != null ? qr.sn.toUpperCase() : raw.toUpperCase();
    // 支持整串输入（SN:xxxxxxx PIN:xxxxx）自动带出 PIN；否则取 PIN 输入框
    final pin = qr?.pin ?? _pinController.text.trim();

    if (!validateSNFormat(sn)) {
      AppToast.show(context,
          '${AppLocalizations.of(context)!.snFormatError}:\n${formatSNForDisplay(sn)}',
          type: ToastType.error);
      return;
    }

    if (!validateCheckDigitOnly(sn)) {
      if (mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.checksumMismatch),
            content: Text(
              'SN: ${formatSNForDisplay(sn)}\n${AppLocalizations.of(context)!.checksumMismatch}\n${AppLocalizations.of(context)!.snConfirmAdd}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(AppLocalizations.of(context)!.continueAdd),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      } else {
        return;
      }
    }

    if (!mounted) return;
    if (pin.isEmpty || pin.length != 6) {
      // PIN 必填且必须为 6 位（后端严格模式：云端绑定同样强制 PIN 校验，见设计文档 §5.4）
      AppToast.show(context, AppLocalizations.of(context)!.pinLengthError,
          type: ToastType.info);
      return;
    }

    // 绑定前选择电站（可选，取消则不绑定）
    if (_selectedStationId == null) {
      final result = await _showStationSelector();
      if (result == null) return;
      if (!mounted) return;
      _selectedStationId = result.$1;
      _selectedStationName = result.$2;
      setState(() {});
    }
    if (!mounted) return;
    context.push(
      '/device/qr-bind?sn=${Uri.encodeQueryComponent(sn)}&pin=${Uri.encodeQueryComponent(pin)}&station_id=${_selectedStationId ?? ''}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.addDevice),
        actions: [
          if (_selectedStationId != null && _selectedStationName != null)
            Padding(
              padding: EdgeInsets.only(right: 12.w),
              child: Center(
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.solar_power,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        _selectedStationName!,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: () async {
                final result = await _showStationSelector();
                if (result != null) {
                  _selectedStationId = result.$1;
                  _selectedStationName = result.$2;
                  setState(() {});
                }
              },
              icon: const Icon(Icons.home_work, size: 18),
              label: Text(
                AppLocalizations.of(context)!.selectStation,
                style: TextStyle(fontSize: 13.sp),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColor.textHint(context),
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(
              text: AppLocalizations.of(context)!.scanCode,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
            ),
            Tab(
              text: AppLocalizations.of(context)!.manualInput,
              icon: const Icon(Icons.bluetooth_searching_rounded, size: 20),
            ),
          ],
        ),
      ),
      body: BlocConsumer<DeviceBloc, DeviceState>(
        listener: (context, state) {
          if (state is DeviceBindSuccess) {
            if (_selectedStationId != null) {
              context
                  .read<StationBloc>()
                  .add(StationDetailRequested(stationId: _selectedStationId!));
            }
            setState(() {
              _sessionBoundCount++;
              _bindSuccess = true;
              _scanning = false;
            });
            _addToScanHistory(_lastScanned, true);
            AppToast.show(
                context,
                AppLocalizations.of(context)!
                    .alreadyBoundNDevices('$_sessionBoundCount'),
                type: ToastType.success);
          } else if (state is DeviceError) {
            _scanning = false;
            _lastScanned = '';
            _scannedPin = '';
            _addToScanHistory(_lastScanned, false);
            AppToast.show(context,
                AppLocalizations.of(context)!.translateError(state.message),
                type: ToastType.error);
          }
        },
        builder: (context, state) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildScanTab(state),
              _buildManualTab(state),
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
            color: AppColors.badgeNormalBg,
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.successLight,
                  size: 18,
                ),
                SizedBox(width: 6.w),
                Text(
                  AppLocalizations.of(context)!
                      .alreadyBoundNDevices('$_sessionBoundCount'),
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.badgeNormalText,
                  ),
                ),
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
                  width: 220.w,
                  height: 220.w,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 2),
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                ),
              ),
              if (_scanning || state is DeviceLoading)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context)!.addingDevice,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.all(16.w),
          color: AppColor.surfaceContainer(context),
          child: Column(
            children: [
              if (_bindSuccess) ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _continueScanning,
                        icon: const Icon(Icons.qr_code_scanner, size: 20),
                        label: Text(
                          AppLocalizations.of(context)!.continueScan,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.check_circle_outline, size: 20),
                        label: Text(
                          AppLocalizations.of(context)!.finish,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.successLight,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
              ] else ...[
                if (_lastScanned.isNotEmpty) ...[
                  Text(
                    'SN: ${formatSNForDisplay(_lastScanned)}',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                  if (_scannedPin.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 4.h),
                      child: Text(
                        'PIN: $_scannedPin',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.successLight,
                        ),
                      ),
                    ),
                ] else
                  Text(
                    AppLocalizations.of(context)!.pointSnAtScan,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
              ],
              SizedBox(height: 8.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 补光灯：仅设备支持时显示，高亮反映真实点亮状态
                  if (_torchAvailable)
                    _toggleChip(
                      _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                      AppLocalizations.of(context)!.flashLight,
                      _torchOn,
                      () {
                        // 手动操作覆盖暗光自动补光状态
                        _autoTorchLit = false;
                        _setTorch(!_torchOn);
                      },
                    ),
                  if (_torchAvailable) SizedBox(width: 12.w),
                  _actionChip(
                    Icons.flip_camera_android,
                    AppLocalizations.of(context)!.flipCamera,
                    () => _cameraController?.switchCamera(),
                  ),
                  SizedBox(width: 12.w),
                  _toggleChip(
                    Icons.brightness_low,
                    AppLocalizations.of(context)!.autoFlash,
                    _autoTorch,
                    _toggleAutoTorch,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_scanHistory.isNotEmpty)
          Container(
            constraints: BoxConstraints(maxHeight: 160.h),
            color: AppColor.surfaceHover(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
                  child: Text(
                    AppLocalizations.of(context)!.scanRecords,
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
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
                          color: entry.success
                              ? AppColors.successLight
                              : AppColors.errorLight,
                        ),
                        title: Text(
                          formatSNForDisplay(entry.sn),
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                            color: AppColor.textPrimary(context),
                          ),
                        ),
                        trailing: Text(
                          entry.success
                              ? AppLocalizations.of(context)!.bindSuccess
                              : AppLocalizations.of(context)!.bindFailed,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: entry.success
                                ? AppColors.successLight
                                : AppColors.errorLight,
                          ),
                        ),
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
    return _toggleChip(icon, label, false, onTap, highlightWhenActive: false);
  }

  /// 可高亮的操作胶囊：[active] 为 true 时以主题色高亮（反映真实开关状态）
  Widget _toggleChip(
    IconData icon,
    String label,
    bool active,
    VoidCallback onTap, {
    bool highlightWhenActive = true,
  }) {
    final highlighted = highlightWhenActive && active;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: highlighted
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColor.surfaceHover(context),
          borderRadius: BorderRadius.circular(20.r),
          border: highlighted
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16.sp,
              color: highlighted
                  ? AppColors.primary
                  : AppColor.textSecondary(context),
            ),
            SizedBox(width: 4.w),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                color: highlighted
                    ? AppColors.primary
                    : AppColor.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualTab(DeviceState state) {
    return ListView(
      padding: EdgeInsets.all(20.w),
      children: [
        // BLE 蓝牙设备列表区域（优先展示）
        _buildBleSection(),
        SizedBox(height: 24.h),
        Divider(height: 1, color: AppColor.outline(context)),
        SizedBox(height: 16.h),
        // 手动输入区域
        Text(
          AppLocalizations.of(context)!.manualInputSn,
          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8.h),
        Text(
          AppLocalizations.of(context)!.snFormatDesc,
          style: TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
        ),
        SizedBox(height: 4.h),
        Text(
          AppLocalizations.of(context)!.snFormatHint,
          style: TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
        ),
        SizedBox(height: 16.h),
        TextField(
          controller: _snController,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.deviceSnLabel,
            hintText: AppLocalizations.of(context)!.input16DigitSn,
            prefixIcon: Icon(Icons.devices, color: AppColor.textHint(context)),
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
          controller: _pinController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.manualPinLabel,
            hintText: AppLocalizations.of(context)!.pinInputHint,
            prefixIcon:
                Icon(Icons.pin_outlined, color: AppColor.textHint(context)),
            counterText: '',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
        SizedBox(height: 6.h),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            AppLocalizations.of(context)!.manualPinDesc,
            style:
                TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
          ),
        ),
        SizedBox(height: 20.h),
        SizedBox(
          width: double.infinity,
          height: 48.h,
          child: ElevatedButton(
            onPressed: state is DeviceLoading ? null : _manualBind,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
            child: state is DeviceLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    AppLocalizations.of(context)!.bindDevice,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ==================== BLE 设备扫描 ====================

  /// 解析 BLE 广播名 → 展示用 SN
  static String _displaySnOf(BleDiscoveredDevice device) {
    if (device.name.isEmpty) return device.macAddress;
    final sn = device.name.replaceFirst(_snPrefixPattern, '');
    return sn.isEmpty ? device.name : sn;
  }

  /// 初始化 BLE 扫描：BleDirectService 已启用则复用其流，否则独立扫描
  Future<void> _initBleScan() async {
    final directService = getIt<BleDirectService>();
    _bleEnabled = directService.enabled;
    if (_bleEnabled) {
      _bleAdapterOn = true;
      _bleDevices = directService.scanResults;
      _subscribeBleDirect();
      _refreshBleBoundStatuses(_bleDevices);
    } else {
      // 蓝牙适配器已开则独立扫描一轮
      try {
        final status = await getIt<BleAdapter>().status;
        _bleAdapterOn = status == BleAdapterStatus.on;
        if (_bleAdapterOn && mounted) {
          _startStandaloneScan();
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  /// 订阅 BleDirectService 的设备发现流
  void _subscribeBleDirect() {
    _bleDirectSub?.cancel();
    _bleDirectSub =
        getIt<BleDirectService>().scanResultsStream.listen((devices) {
      if (!mounted) return;
      setState(() => _bleDevices = devices);
      _refreshBleBoundStatuses(devices);
    });
  }

  /// BleDirectService 未启用时的独立扫描（轻量，无自动连接/轮询）
  void _startStandaloneScan() {
    _standaloneScanSub?.cancel();
    _bleScanning = true;
    final seen = <String, BleDiscoveredDevice>{
      for (final d in _bleDevices) d.macAddress: d,
    };
    _standaloneScanSub = getIt<BleAdapter>().scan(
      serviceUuids: const [BleCtProtocol.serviceUuid],
      timeout: const Duration(seconds: 15),
    ).listen(
      (result) {
        if (!mounted) return;
        final device = BleDiscoveredDevice(
          macAddress: result.macAddress,
          name: result.name,
          lastSeen: DateTime.now(),
        );
        seen[result.macAddress] = device;
        setState(() => _bleDevices = seen.values.toList()
          ..sort((a, b) => (b.lastSeen ?? DateTime(0))
              .compareTo(a.lastSeen ?? DateTime(0))));
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _bleScanning = false);
        _refreshBleBoundStatuses(_bleDevices);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _bleScanning = false);
      },
    );
  }

  /// 切换 BLE 直连总开关（从添加设备页面快捷操作）
  Future<void> _toggleBleFromAddDevice(bool value) async {
    final directService = getIt<BleDirectService>();
    try {
      await directService.setEnabled(value);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, AppLocalizations.of(context)!.bleBluetoothOff,
          type: ToastType.error);
      return;
    }
    await getIt<StorageService>().saveIsBleDirectEnabled(value);
    if (!mounted) return;
    setState(() {
      _bleEnabled = value;
      _bleAdapterOn = true; // setEnabled 成功说明蓝牙已开
    });
    if (value) {
      _standaloneScanSub?.cancel();
      _standaloneScanSub = null;
      _bleDevices = directService.scanResults;
      _subscribeBleDirect();
      _refreshBleBoundStatuses(_bleDevices);
    } else {
      _bleDirectSub?.cancel();
      _bleDirectSub = null;
      // BleDirectService 已关闭，BLE 适配器已释放，启动独立扫描
      _startStandaloneScan();
    }
  }

  /// 手动刷新 BLE 扫描
  void _rescanBle() {
    final directService = getIt<BleDirectService>();
    if (directService.enabled) {
      directService.rescan();
    } else {
      _startStandaloneScan();
    }
  }

  /// 批量查询发现设备的绑定状态
  Future<void> _refreshBleBoundStatuses(
      List<BleDiscoveredDevice> devices) async {
    final keyStore = getIt<BleDeviceKeyStore>();
    final result = <String, bool>{};
    for (final device in devices) {
      final sn = device.name.replaceFirst(_snPrefixPattern, '');
      if (device.name.isEmpty || sn.isEmpty) {
        result[device.macAddress] = false;
        continue;
      }
      try {
        result[device.macAddress] = await keyStore.read(sn) != null;
      } catch (_) {
        result[device.macAddress] = false;
      }
    }
    if (!mounted) return;
    setState(() => _bleBoundByMac = result);
  }

  /// BLE 设备绑定弹窗：输入 PIN → BleBindingService.bindAfterProvision
  Future<void> _showBleBindDialog(BleDiscoveredDevice device) async {
    final l10n = AppLocalizations.of(context)!;
    // 防止快速连点重复弹窗（触发 Duplicate GlobalKeys / dirty widget in wrong build scope）
    if (_bleBindDialogOpen) return;
    _bleBindDialogOpen = true;
    try {
      final enteredPin = await showBlePinBindDialog(
        context: context,
        deviceSn: _displaySnOf(device),
      );
      if (enteredPin == null || !mounted) return;

      final outcome = await getIt<BleBindingService>().bindAfterProvision(
        macAddress: device.macAddress,
        pin: enteredPin,
      );
      if (!mounted) return;

      // 绑定失败时断开会话，避免残留 session 误判
      if (outcome != BindOutcome.bound && outcome != BindOutcome.alreadyBound) {
        try {
          await getIt<BleDeviceManager>().disconnectDevice(device.macAddress);
        } catch (_) {}
      }

      final (text, type) = switch (outcome) {
        BindOutcome.bound => (
            l10n.str('ble_binding_success'),
            ToastType.success
          ),
        BindOutcome.alreadyBound => (
            l10n.str('ble_binding_already_bound'),
            ToastType.info
          ),
        BindOutcome.invalidPin => (l10n.pinInvalid, ToastType.error),
        BindOutcome.locked => (l10n.pinLocked, ToastType.error),
        BindOutcome.needLoginForSync => (
            l10n.str('ble_binding_need_login'),
            ToastType.info
          ),
        _ => (l10n.str('ble_binding_failed'), ToastType.error),
      };
      if (!mounted) return;
      AppToast.show(context, text, type: type);
      // 绑定成功：更新状态并刷新列表
      if (outcome == BindOutcome.bound || outcome == BindOutcome.alreadyBound) {
        _bleBoundByMac = {..._bleBoundByMac, device.macAddress: true};
        _sessionBoundCount++;
        _addToScanHistory(_displaySnOf(device), true);
      }
      if (mounted)
        setState(() => _bleDevices = getIt<BleDirectService>().enabled
            ? getIt<BleDirectService>().scanResults
            : _bleDevices);
    } finally {
      _bleBindDialogOpen = false;
    }
  }

  /// BLE 设备列表项
  Widget _buildBleDeviceTile(BleDiscoveredDevice device) {
    final connected =
        getIt<BleDeviceManager>().sessionOf(device.macAddress) != null;
    final bound = _bleBoundByMac[device.macAddress] ?? false;
    final displaySn = _displaySnOf(device);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child:
                Icon(Icons.router_rounded, size: 18.sp, color: AppColors.blue),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displaySn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColor.textPrimary(context),
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  displaySn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.sp, color: AppColor.textHint(context)),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          if (connected)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 12.sp, color: AppColors.success),
                  SizedBox(width: 4.w),
                  Text(
                    AppLocalizations.of(context)!.str('ble_device_connected'),
                    style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success),
                  ),
                ],
              ),
            )
          else if (bound)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link_rounded, size: 12.sp, color: AppColors.blue),
                  SizedBox(width: 4.w),
                  Text(
                    AppLocalizations.of(context)!.str('ble_device_bound'),
                    style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.blue),
                  ),
                ],
              ),
            )
          else
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                minimumSize: Size(0, 34.h),
              ),
              onPressed: () => _showBleBindDialog(device),
              child: Text(
                AppLocalizations.of(context)!.str('ble_bind_device'),
                style: TextStyle(fontSize: 13.sp),
              ),
            ),
        ],
      ),
    );
  }

  /// BLE 设备列表区域（嵌入设备发现 tab 顶部）
  Widget _buildBleSection() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行：BLE 开关 + 刷新按钮
        Row(
          children: [
            Icon(Icons.bluetooth_rounded, size: 20.sp, color: AppColors.blue),
            SizedBox(width: 8.w),
            Text(
              l10n.str('ble_found_devices'),
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            // 刷新按钮
            IconButton(
              icon: Icon(Icons.refresh_rounded, size: 20.sp),
              onPressed: _rescanBle,
              tooltip: l10n.str('ble_rescan'),
              visualDensity: VisualDensity.compact,
            ),
            SizedBox(width: 4.w),
            // BLE 开关
            SizedBox(
              height: 28.h,
              child: Switch(
                value: _bleEnabled,
                onChanged: _toggleBleFromAddDevice,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        SizedBox(height: 4.h),
        Padding(
          padding: EdgeInsets.only(left: 28.w),
          child: Text(
            l10n.str('ble_found_devices_hint'),
            style:
                TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
          ),
        ),
        SizedBox(height: 12.h),
        // 设备列表 / 空状态
        if (_bleDevices.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: AppColor.surfaceContainer(context),
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Column(
              children: [
                for (int i = 0; i < _bleDevices.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 62.w),
                  _buildBleDeviceTile(_bleDevices[i]),
                ],
              ],
            ),
          )
        else if (_bleScanning)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20.h),
            child: Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 24.w,
                    height: 24.w,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.blue),
                  ),
                  SizedBox(height: 8.h),
                  Text(l10n.str('ble_scanning_short'),
                      style: TextStyle(
                          fontSize: 12.sp, color: AppColor.textHint(context))),
                ],
              ),
            ),
          )
        else if (!_bleAdapterOn)
          _buildBleEmptyState(
            Icons.bluetooth_disabled_rounded,
            l10n.bleBluetoothOff,
            l10n.str('ble_scan_enable_hint'),
          )
        else
          _buildBleEmptyState(
            Icons.bluetooth_searching_rounded,
            l10n.str('ble_found_empty'),
            l10n.str('ble_scanning_hint'),
          ),
        SizedBox(height: 8.h),
        if (_bleEnabled)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w),
            child: Text(
              l10n.str('ble_scanning_hint'),
              style:
                  TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
            ),
          ),
      ],
    );
  }

  Widget _buildBleEmptyState(IconData icon, String title, String? subtitle) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 24.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32.sp, color: AppColor.textHint(context)),
          SizedBox(height: 8.h),
          Text(
            title,
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13.sp, color: AppColor.textHint(context)),
          ),
          if (subtitle != null) ...[
            SizedBox(height: 4.h),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
            ),
          ],
        ],
      ),
    );
  }

  void _continueScanning() {
    _qrScanGuard.release(resetPayload: true);
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
        if (!mounted) return;
        setState(() {
          _scanHistory = list
              .map((e) => _ScanHistoryEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveScanHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = _scanHistory.length > 10
          ? _scanHistory.sublist(_scanHistory.length - 10)
          : _scanHistory;
      final jsonStr = jsonEncode(trimmed.map((e) => e.toJson()).toList());
      await prefs.setString(_scanHistoryKey, jsonStr);
    } catch (_) {}
  }

  void _addToScanHistory(String sn, bool success) {
    if (sn.isEmpty) return;
    setState(() {
      _scanHistory.add(
        _ScanHistoryEntry(sn: sn, success: success, time: DateTime.now()),
      );
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

  _ScanHistoryEntry({
    required this.sn,
    required this.success,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
        'sn': sn,
        'success': success,
        'time': time.toIso8601String(),
      };

  factory _ScanHistoryEntry.fromJson(Map<String, dynamic> json) =>
      _ScanHistoryEntry(
        sn: json['sn'] as String,
        success: json['success'] as bool,
        time: DateTime.parse(json['time'] as String),
      );
}
