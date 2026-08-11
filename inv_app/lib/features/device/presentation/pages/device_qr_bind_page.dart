import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 智能链接二维码 BLE 扫码绑定页
///
/// 深链接 `csinv://bind?sn=&pin=` 或 App 内扫码（URL 格式）进入：
/// 二维码只有 SN+PIN 没有 MAC → 扫描蓝牙设备 → 连接读 INFO 匹配 SN →
/// 调 [BleBindingService.bindAfterProvision] 完成绑定（离网可用）。
/// BLE 不可达时提供云端兑底（带 PIN，由后端校验所有权）。
class DeviceQrBindPage extends StatefulWidget {
  final String sn;
  final String pin;
  final int? stationId;
  final BleAdapter? adapter;
  final BleDeviceManager? manager;
  final BleBindingService? bindingService;

  const DeviceQrBindPage({
    super.key,
    required this.sn,
    required this.pin,
    this.stationId,
    this.adapter,
    this.manager,
    this.bindingService,
  });

  @override
  State<DeviceQrBindPage> createState() => _DeviceQrBindPageState();
}

/// 绑定流程阶段
enum _QrBindPhase {
  /// 深链接/二维码未带 PIN：等待用户输入
  pinInput,

  /// 检查蓝牙状态
  checking,

  /// 扫描附近 BLE 设备
  scanning,

  /// 逐个连接候选设备匹配 SN
  matching,

  /// 写入绑定信息
  binding,

  /// 蓝牙关闭 / 未找到匹配设备（可重试）
  failed,

  /// 绑定流程结束（含各结果）
  done,
}

class _DeviceQrBindPageState extends State<DeviceQrBindPage> {
  late final BleAdapter _adapter;
  late final BleDeviceManager _manager;
  late final BleBindingService _bindingService;

  /// 当前使用的 PIN（空时需用户输入，见 [_QrBindPhase.pinInput]）
  late String _pin;
  final _pinController = TextEditingController();

  _QrBindPhase _phase = _QrBindPhase.checking;
  BindOutcome? _doneOutcome;

  /// 匹配到的设备名（matching 阶段显示当前候选，done 阶段显示最终匹配）
  String? _matchName;

  /// 失败原因 l10n 键（蓝牙关闭 / 未找到匹配设备）
  String? _failKey;

  /// 云端兑底绑定进行中（防重复点击）
  bool _cloudBinding = false;

  @override
  void initState() {
    super.initState();
    _pin = widget.pin;
    _adapter = widget.adapter ?? getIt<BleAdapter>();
    _manager = widget.manager ?? getIt<BleDeviceManager>();
    _bindingService = widget.bindingService ?? getIt<BleBindingService>();
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
    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _phase = _QrBindPhase.checking;
      _doneOutcome = null;
      _matchName = null;
      _failKey = null;
    });

    // 深链接/二维码未带 PIN：先让用户输入（6 位数字，见设计文档 §5.4）
    if (_pin.trim().isEmpty) {
      setState(() => _phase = _QrBindPhase.pinInput);
      return;
    }
    await _bindFlow(l10n);
  }

  Future<void> _bindFlow(AppLocalizations l10n) async {

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
        _phase = _QrBindPhase.failed;
        _failKey = 'ble_bluetooth_off';
      });
      return;
    }

    // 2. 扫描附近设备（按 CSIV-CT 服务 UUID 过滤）
    setState(() => _phase = _QrBindPhase.scanning);
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
        _phase = _QrBindPhase.failed;
        _failKey = 'qr_bind_not_found';
      });
      return;
    }

    // 3. 逐个连接候选设备，读 INFO 匹配 SN
    String? matchedMac;
    for (final result in results) {
      if (!mounted) return;
      setState(() {
        _phase = _QrBindPhase.matching;
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
          // （使用 disconnectDevice 而非 session.dispose：dispose 后会话仍留在
          //   manager 缓存，复用会因已关闭的 state controller 抛错）
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
        _phase = _QrBindPhase.failed;
        _failKey = 'qr_bind_not_found';
      });
      return;
    }

    // 5. 写入绑定信息（离网可用）
    setState(() => _phase = _QrBindPhase.binding);
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
    // 监听云端兑底绑定结果：成功直接返回（入口页的 DeviceBindSuccess
    // 监听负责刷新列表/提示）；失败留在本页展示错误。
    return BlocConsumer<DeviceBloc, DeviceState>(
      listener: (context, state) {
        if (!_cloudBinding) return;
        if (state is DeviceBindSuccess) {
          _cloudBinding = false;
          Navigator.of(context).pop();
        } else if (state is DeviceError) {
          _cloudBinding = false;
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.translateError(state.message))),
          );
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
      case _QrBindPhase.checking:
        return _progressBody(l10n.str('qr_bind_checking'), Icons.bluetooth_searching);
      case _QrBindPhase.scanning:
        return _progressBody(l10n.str('qr_bind_scanning'), Icons.bluetooth_searching);
      case _QrBindPhase.matching:
        return _progressBody(
          l10n.str('qr_bind_matching', {'name': _matchName ?? ''}),
          Icons.bluetooth,
        );
      case _QrBindPhase.binding:
        return _progressBody(l10n.str('qr_bind_binding'), Icons.link);
      case _QrBindPhase.failed:
        return _failedBody(l10n);
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

  Widget _failedBody(AppLocalizations l10n) {
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
          onPressed: _start,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.str('ble_retry')),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.qrBindBack),
        ),
        const SizedBox(height: 12),
        // 云端兑底：带 PIN 由后端校验所有权（无蓝牙/未找到设备时仍可绑定）
        if (_cloudBinding)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          )
        else
          TextButton.icon(
            onPressed: _cloudBinding ? null : () => _cloudBindFallback(),
            icon: const Icon(Icons.cloud_outlined, size: 18),
            label: Text(l10n.cloudBindFallback),
          ),
      ],
    );
  }

  /// BLE 不可达时的云端绑定兑底：POST /devices/bind 带 PIN，
  /// 后端按 HMAC-SHA256(PRODUCT_SECRET, SN) 校验设备所有权。
  Future<void> _cloudBindFallback() async {
    setState(() => _cloudBinding = true);
    context.read<DeviceBloc>().add(
          DeviceBindRequested(
            sn: widget.sn,
            stationId: widget.stationId,
            pin: _pin,
          ),
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
