import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart' hide State;

import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 智能链接二维码绑定页（云端优先，BLE 后备）
///
/// 新流程：
/// 1. 用户输入/确认 PIN
/// 2. **云端绑定**（POST /devices/bind 带 PIN，~1 秒完成）
///    - 成功 → 展示成功页，用户点击「完成」返回
///    - 失败（设备未注册/网络错误）→ 展示选择界面
/// 3. 用户可选择：
///    - 重试云端绑定
///    - **尝试 BLE 扫描**（扫描附近 BLE 设备 → 匹配 SN → 绑定）
///    - 返回
class DeviceQrBindPage extends StatefulWidget {
  final String sn;
  final String pin;
  final int? stationId;
  final BleAdapter? adapter;
  final BleDeviceManager? manager;
  final BleBindingService? bindingService;
  final DeviceRepository? deviceRepository;

  const DeviceQrBindPage({
    super.key,
    required this.sn,
    required this.pin,
    this.stationId,
    this.adapter,
    this.manager,
    this.bindingService,
    this.deviceRepository,
  });

  @override
  State<DeviceQrBindPage> createState() => _DeviceQrBindPageState();
}

/// 绑定流程阶段
enum _QrBindPhase {
  /// 深链接/二维码未带 PIN：等待用户输入
  pinInput,

  /// 正在云端绑定
  cloudBinding,

  /// 云端绑定失败，展示选择界面（重试云端 / 尝试 BLE / 返回）
  cloudFailed,

  /// 检查蓝牙状态
  bleChecking,

  /// 扫描附近 BLE 设备
  bleScanning,

  /// 逐个连接候选设备匹配 SN
  bleMatching,

  /// 写入绑定信息
  bleBinding,

  /// BLE 失败（蓝牙关闭 / 未找到匹配设备）
  bleFailed,

  /// 绑定流程结束（含各结果）
  done,
}

class _DeviceQrBindPageState extends State<DeviceQrBindPage> {
  late final BleAdapter _adapter;
  late final BleDeviceManager _manager;
  late final BleBindingService _bindingService;
  late final DeviceRepository _deviceRepository;

  /// 当前使用的 PIN（空时需用户输入，见 [_QrBindPhase.pinInput]）
  late String _pin;
  final _pinController = TextEditingController();

  _QrBindPhase _phase = _QrBindPhase.cloudBinding;
  BindOutcome? _doneOutcome;

  /// 匹配到的设备名（BLE matching 阶段显示当前候选，done 阶段显示最终匹配）
  String? _matchName;

  /// 云端绑定失败消息（用于展示在 cloudFailed 界面）
  String? _cloudErrorMessage;

  /// BLE 失败原因 l10n 键
  String? _failKey;

  /// 云端绑定防重复点击
  bool _cloudBindingPending = false;

  @override
  void initState() {
    super.initState();
    _pin = widget.pin;
    _adapter = widget.adapter ?? getIt<BleAdapter>();
    _manager = widget.manager ?? getIt<BleDeviceManager>();
    _bindingService = widget.bindingService ?? getIt<BleBindingService>();
    _deviceRepository = widget.deviceRepository ?? getIt<DeviceRepository>();
    // 延迟到首帧后启动流程：initState 阶段不能访问 InheritedWidget（Localizations）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _QrBindPhase.cloudBinding;
      _doneOutcome = null;
      _matchName = null;
      _failKey = null;
      _cloudErrorMessage = null;
    });

    // 深链接/二维码未带 PIN：先让用户输入（6 位数字，见设计文档 §5.4）
    if (_pin.trim().isEmpty) {
      setState(() => _phase = _QrBindPhase.pinInput);
      return;
    }
    await _cloudBind();
  }

  /// 云端绑定：POST /devices/bind 带 PIN，后端校验设备所有权。
  Future<void> _cloudBind() async {
    if (_cloudBindingPending) return;
    setState(() {
      _phase = _QrBindPhase.cloudBinding;
      _cloudBindingPending = true;
      _cloudErrorMessage = null;
    });

    final Either<Failure, void> result = await _deviceRepository.bind(
      widget.sn,
      widget.stationId,
      pin: _pin,
    );

    if (!mounted) return;
    // 使用 switch pattern matching 替代 fold（避免分析器误报）
    switch (result) {
      case Left(value: final failure):
        setState(() {
          _cloudBindingPending = false;
          _phase = _QrBindPhase.cloudFailed;
          _cloudErrorMessage = failure.message;
        });
      case Right():
        // 云端绑定成功：展示 done 页，用户点击「完成」返回
        // （页面已直接经 repository 完成绑定，不再派发 DeviceBindRequested
        // 触发 bloc 重复调用 bind API）
        setState(() {
          _cloudBindingPending = false;
          _doneOutcome = BindOutcome.bound;
          _phase = _QrBindPhase.done;
        });
    }
  }

  /// BLE 后备绑定流程
  Future<void> _startBleFallback() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _phase = _QrBindPhase.bleChecking;
      _doneOutcome = null;
      _matchName = null;
      _failKey = null;
    });

    // 1. 检查蓝牙状态
    BleAdapterStatus status;
    try {
      status = await _adapter.status;
    } catch (_) {
      status = BleAdapterStatus.unknown;
    }
    if (!mounted) return;
    if (status != BleAdapterStatus.on) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.str('ble_bluetooth_off'))),
      );
      setState(() {
        _phase = _QrBindPhase.bleFailed;
        _failKey = 'ble_bluetooth_off';
      });
      return;
    }

    // 2. 扫描附近设备（按 CSIV-CT 服务 UUID 过滤）
    setState(() => _phase = _QrBindPhase.bleScanning);
    List<BleScanResult> results;
    try {
      results = await _adapter
          .scan(
            serviceUuids: const [BleCtProtocol.serviceUuid],
            timeout: const Duration(seconds: 15),
          )
          .toList();
    } catch (_) {
      results = const <BleScanResult>[];
    }
    if (!mounted) return;
    if (results.isEmpty) {
      setState(() {
        _phase = _QrBindPhase.bleFailed;
        _failKey = 'qr_bind_not_found';
      });
      return;
    }

    // 3. 逐个连接候选设备，读 INFO 匹配 SN
    String? matchedMac;
    for (final result in results) {
      if (!mounted) return;
      setState(() {
        _phase = _QrBindPhase.bleMatching;
        _matchName = result.name;
      });
      BleDeviceSession? session;
      try {
        session = await _manager.connectDevice(result.macAddress);
        final info = await session.readInfo();
        final deviceSn = (info['sn'] as String?)?.trim().toUpperCase();
        if (deviceSn == widget.sn.trim().toUpperCase()) {
          matchedMac = result.macAddress;
          // 断开本次匹配连接：让 bindAfterProvision 重新建立绑定会话
          await _manager.disconnectDevice(result.macAddress);
          break;
        }
        await session.dispose();
      } catch (_) {
        // 连接失败 / INFO 读取失败：跳过该候选，不阻断其他候选
        try {
          await session?.dispose();
        } catch (_) {}
      }
    }
    if (!mounted) return;
    if (matchedMac == null) {
      setState(() {
        _phase = _QrBindPhase.bleFailed;
        _failKey = 'qr_bind_not_found';
      });
      return;
    }

    // 4. 写入绑定信息（离网可用）
    setState(() => _phase = _QrBindPhase.bleBinding);
    final outcome = await _bindingService.bindAfterProvision(
      macAddress: matchedMac,
      knownSn: widget.sn,
      pin: _pin,
    );
    if (!mounted) return;
    setState(() {
      _phase = _QrBindPhase.done;
      _doneOutcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 绑定由本页直接经 repository 完成：成功停留 done 页由用户确认返回；
    // 失败（bloc 层其它事件报错且本页正处于云端绑定中）留在本页展示错误。
    return BlocConsumer<DeviceBloc, DeviceState>(
      listener: (context, state) {
        if (state is DeviceError) {
          // 云端绑定失败（bloc 层）：展示在 cloudFailed 界面
          if (_phase == _QrBindPhase.cloudBinding) {
            setState(() {
              _cloudBindingPending = false;
              _phase = _QrBindPhase.cloudFailed;
              _cloudErrorMessage = l10n.translateError(state.message);
            });
          }
        }
      },
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text(l10n.str('qr_bind_title'))),
        body: Center(child: _buildBody(l10n)),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    switch (_phase) {
      case _QrBindPhase.pinInput:
        return _pinInputBody(l10n);
      case _QrBindPhase.cloudBinding:
        return _progressBody(
          l10n.qrBindCloudBinding,
          Icons.cloud_outlined,
        );
      case _QrBindPhase.cloudFailed:
        return _cloudFailedBody(l10n);
      case _QrBindPhase.bleChecking:
        return _progressBody(l10n.str('qr_bind_checking'), Icons.bluetooth_searching);
      case _QrBindPhase.bleScanning:
        return _progressBody(l10n.str('qr_bind_scanning'), Icons.bluetooth_searching);
      case _QrBindPhase.bleMatching:
        return _progressBody(
          l10n.str('qr_bind_matching', {'name': _matchName ?? ''}),
          Icons.bluetooth,
        );
      case _QrBindPhase.bleBinding:
        return _progressBody(l10n.str('qr_bind_binding'), Icons.link);
      case _QrBindPhase.bleFailed:
        return _bleFailedBody(l10n);
      case _QrBindPhase.done:
        return _doneBody(l10n);
    }
  }

  /// 深链接未带 PIN 时的输入页（6 位数字键盘）
  Widget _pinInputBody(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.pin_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.qrBindPinRequired,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pinInputHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _pinController,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            decoration: InputDecoration(
              hintText: '••••••',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              final pin = _pinController.text.trim();
              if (pin.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.pinRequired)),
                );
                return;
              }
              _pin = pin;
              _start();
            },
            icon: const Icon(Icons.lock_open),
            label: Text(l10n.pinInputConfirm),
          ),
        ],
      ),
    );
  }

  Widget _progressBody(String message, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        const CircularProgressIndicator(strokeWidth: 3),
      ],
    );
  }

  /// 云端绑定失败：展示错误 + 三个选项
  Widget _cloudFailedBody(AppLocalizations l10n) {
    final errorMessage = _cloudErrorMessage ?? l10n.qrBindCloudFailed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_off,
          size: 56,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 32),
        // 主操作：重试云端绑定
        FilledButton.icon(
          onPressed: _cloudBind,
          icon: const Icon(Icons.cloud_outlined),
          label: Text(l10n.str('ble_retry')),
        ),
        const SizedBox(height: 12),
        // 次操作：尝试 BLE 扫描
        OutlinedButton.icon(
          onPressed: _startBleFallback,
          icon: const Icon(Icons.bluetooth_searching, size: 18),
          label: Text(l10n.qrBindTryBle),
        ),
        const SizedBox(height: 12),
        // 返回
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.qrBindBack),
        ),
      ],
    );
  }

  /// BLE 失败：蓝牙关闭 / 未找到匹配设备
  Widget _bleFailedBody(AppLocalizations l10n) {
    final message = _failKey == null
        ? l10n.str('qr_bind_not_found')
        : l10n.str(_failKey!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline,
          size: 56,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(message, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _startBleFallback,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.str('ble_retry')),
        ),
        const SizedBox(height: 12),
        // 回到云端选项
        OutlinedButton.icon(
          onPressed: _cloudBind,
          icon: const Icon(Icons.cloud_outlined, size: 18),
          label: Text(l10n.cloudBindFallback),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.qrBindBack),
        ),
      ],
    );
  }

  Widget _doneBody(AppLocalizations l10n) {
    final outcome = _doneOutcome;
    final (icon, color, text) = _outcomeInfo(l10n, outcome);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: color),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
        if (outcome == BindOutcome.bound) ...[
          const SizedBox(height: 8),
          Text(
            widget.sn,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: _start,
              child: Text(l10n.str('ble_retry')),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.str('qr_bind_done')),
            ),
          ],
        ),
      ],
    );
  }

  /// 根据绑定结果返回（图标, 颜色, 文案）
  (IconData, Color, String) _outcomeInfo(
    AppLocalizations l10n,
    BindOutcome? outcome,
  ) {
    final errorColor = Theme.of(context).colorScheme.error;
    switch (outcome) {
      case BindOutcome.bound:
        return (
          Icons.check_circle,
          AppColors.successLight,
          l10n.str('ble_binding_success'),
        );
      case BindOutcome.alreadyBound:
        return (
          Icons.info,
          AppColors.warning,
          l10n.str('ble_binding_already_bound'),
        );
      case BindOutcome.invalidPin:
        return (Icons.lock, errorColor, l10n.str('pin_invalid'));
      case BindOutcome.locked:
        return (Icons.lock, errorColor, l10n.str('pin_locked'));
      case BindOutcome.needLoginForSync:
        return (
          Icons.cloud_sync,
          AppColors.warning,
          l10n.str('ble_binding_need_login'),
        );
      case BindOutcome.failed:
        return (Icons.error_outline, errorColor, l10n.str('ble_binding_failed'));
      case null:
        return (Icons.error_outline, errorColor, l10n.str('ble_binding_failed'));
    }
  }
}
