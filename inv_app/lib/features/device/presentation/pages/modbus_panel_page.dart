import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';
import 'package:inv_app/core/widgets/device_list_view.dart'
    show DeviceSearchBar;
import 'package:inv_app/features/device/presentation/widgets/device_section_navigation.dart';
import 'package:inv_app/features/device/presentation/widgets/device_settings_group_card.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/modbus_panel_ble.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/device/presentation/pages/modbus_panel_aux_page.dart';
import 'package:inv_app/features/device/presentation/widgets/device_connection_card.dart';
import 'package:inv_app/features/device/presentation/widgets/device_settings_heading.dart';
import 'package:inv_app/features/device/presentation/widgets/device_settings_navigation.dart';
import 'package:inv_app/features/device/presentation/widgets/device_setting_change.dart';
import 'package:inv_app/features/device/presentation/widgets/modbus_panel_overview.dart';
import 'package:inv_app/features/device/presentation/widgets/device_power_buttons.dart';
import 'package:inv_app/features/device/presentation/widgets/device_action_button.dart';

String _label(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

String _errorText(BuildContext context, Object error) {
  final code = error is BleCommandException ? error.code : '';
  return switch (code) {
    'PROFILE_REQUIRED' =>
      _label(context, '请先确认逆变器机型。', 'Confirm the inverter model first.'),
    'CONTEXT_CHANGED' || 'STALE_CONTEXT' || 'REVISION_CONFLICT' => _label(
        context,
        '设备配置或建议值已变化，请刷新后重试。',
        'The device configuration or suggested value changed. Refresh and retry.',
      ),
    'VALUE_MISMATCH' => _label(
        context,
        '逆变器读回值与目标值不一致。',
        'The inverter reported a different value.',
      ),
    'SYNC_TIMEOUT' => _label(
        context,
        '等待逆变器结果超时，请先刷新当前值。',
        'The inverter result timed out. Refresh its value before retrying.',
      ),
    'INVERTER_REJECTED' =>
      _label(context, '逆变器拒绝了此次操作。', 'The inverter rejected this operation.'),
    'BUSY' || 'OTA_IN_PROGRESS' || 'UPGRADE_BUSY' => _label(
        context,
        '设备正在处理其他操作，请稍后再试。',
        'The device is busy. Try again shortly.',
      ),
    'OUT_OF_RANGE' || 'INVALID_ARGS' => _label(
        context,
        '当前机型或运行状态不接受此值。',
        'This value is unavailable for the current model or operating state.',
      ),
    'UNSUPPORTED_PARAM' || 'PROTOCOL_UNSUPPORTED' => _label(
        context,
        '当前机型不支持此操作。',
        'This operation is unavailable on the current model.',
      ),
    'NOT_READY' || 'UNAUTHENTICATED' => _label(
        context,
        '设备已断开或尚未准备就绪。',
        'The device disconnected or is not ready.',
      ),
    _ => _label(
        context,
        '通信失败，请检查设备连接后重试。',
        'Communication failed. Check the connection and retry.',
      ),
  };
}

String _receiptText(BuildContext context, ModbusPanelWriteOutcome outcome) =>
    outcome == ModbusPanelWriteOutcome.applied
        ? _label(context, '已回读确认', 'Verified by readback')
        : _label(context, '逆变器已受理', 'Accepted by inverter');

class ModbusPanelPage extends StatefulWidget {
  const ModbusPanelPage({
    super.key,
    required this.session,
    this.startInSettings = false,
  });

  final BleDeviceSession session;
  final bool startInSettings;

  @override
  State<ModbusPanelPage> createState() => _ModbusPanelPageState();
}

class _ModbusPanelPageState extends State<ModbusPanelPage> {
  late ModbusPanelBle _panel;
  bool? _english;
  late final StreamSubscription<BleDeviceState> _stateSubscription;
  late final StreamSubscription<Map<String, dynamic>> _telemetrySubscription;
  Timer? _timer;
  ModbusPanelInfo? _info;
  Map<String, dynamic> _telemetry = const {};
  DateTime? _receivedAt;
  bool _snapshotOnline = false;
  late int _section = widget.startInSettings ? 1 : 0;
  Object? _error;
  bool _polling = false;
  bool _powerBusy = false;
  bool _reconnecting = false;

  bool get _connected =>
      widget.session.state == BleDeviceState.ready &&
      widget.session.supportsPanelApi;

  bool get _live {
    final age = _telemetry['age_ms'];
    final received = _receivedAt;
    return _connected &&
        _snapshotOnline &&
        _info?.online != false &&
        received != null &&
        age is num &&
        age.isFinite &&
        age >= 0 &&
        age + DateTime.now().difference(received).inMilliseconds < 8000;
  }

  @override
  void initState() {
    super.initState();
    _stateSubscription = widget.session.stateStream.listen((_) {
      if (!mounted) return;
      setState(() {
        _info = null;
        _snapshotOnline = false;
      });
      if (_connected) unawaited(_refresh());
    });
    _telemetrySubscription = widget.session.telemetry.listen(_applyTelemetry);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final english = Localizations.localeOf(context).languageCode != 'zh';
    if (_english == english) return;
    _english = english;
    _panel = ModbusPanelBle(widget.session, english: english);
    unawaited(_refresh());
  }

  void _applyTelemetry(Map<String, dynamic> telemetry) {
    if (!mounted ||
        !_connected ||
        telemetry['device_sn'] != widget.session.sn) {
      return;
    }
    setState(() {
      _snapshotOnline = telemetry['online'] == true;
      if ((_snapshotOnline || _telemetry.isEmpty) &&
          (telemetry['updated_at'] != null
              ? telemetry['updated_at'] != _telemetry['updated_at']
              : !mapEquals(_telemetry, telemetry))) {
        _telemetry = telemetry;
        _receivedAt = DateTime.now();
      }
    });
  }

  Future<void> _refresh() async {
    if (_polling ||
        _powerBusy ||
        !_connected ||
        widget.session.isOtaInProgress) {
      return;
    }
    _polling = true;
    final sessionId = widget.session.connectionSessionId;
    try {
      final info = await _panel.info();
      if (!mounted || widget.session.connectionSessionId != sessionId) return;
      setState(() {
        _info = info;
        _error = null;
      });
      final telemetry = await widget.session.readTelemetrySnapshot();
      if (widget.session.connectionSessionId == sessionId) {
        _applyTelemetry(telemetry);
      }
    } catch (error) {
      if (mounted && widget.session.connectionSessionId == sessionId) {
        setState(() => _error = error);
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _reconnect() async {
    final sn = widget.session.sn;
    if (sn == null || _reconnecting || _connected) return;
    setState(() {
      _reconnecting = true;
      _error = null;
    });
    try {
      final session = await getIt<BleDeviceManager>().connectDevice(
        widget.session.macAddress,
      );
      if (!mounted) return;
      if (session.sn != sn ||
          session.state != BleDeviceState.ready ||
          !session.supportsPanelApi) {
        throw const BleCommandException('NOT_READY', 'Panel is not ready');
      }
      if (!identical(session, widget.session)) {
        unawaited(
          Navigator.of(context).pushReplacement<void, void>(
            MaterialPageRoute(
              builder: (_) => ModbusPanelPage(
                session: session,
                startInSettings: _section == 1,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  Future<void> _power(int action) async {
    final info = _info;
    if (!_connected || info == null || _powerBusy) return;
    final sessionId = widget.session.connectionSessionId;
    final (title, description) = switch (action) {
      1 => (
          _label(context, '开启逆变器', 'Start inverter'),
          _label(
            context,
            '开启后逆变器可能向负载供电。',
            'The inverter may energize its output.',
          ),
        ),
      2 => (
          _label(context, '关闭逆变器', 'Stop inverter'),
          _label(context, '关闭后负载可能断电。', 'Stopping may cut power to the load.'),
        ),
      _ => (
          _label(context, '停用远程开关机', 'Disable remote power control'),
          _label(
            context,
            '将开关机控制交回逆变器。',
            'Return power control to the inverter.',
          ),
        ),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_label(context, '取消', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(144, 52)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(title),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final allowed = switch (action) {
      1 => _info?.canPowerOn == true,
      2 => _info?.canPowerOff == true,
      _ => _info?.confirmed == true && _info?.online == true,
    };
    if (!_connected ||
        _powerBusy ||
        !allowed ||
        widget.session.connectionSessionId != sessionId ||
        _info?.context != info.context) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _label(
              context,
              '设备连接已变化，请重新确认。',
              'The device connection changed. Confirm again.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _powerBusy = true);
    try {
      final result = await _panel.write('panel_4123', action, info.context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText(context, result))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorText(context, error))),
      );
    } finally {
      if (mounted) {
        setState(() => _powerBusy = false);
        unawaited(_refresh());
      }
    }
  }

  void _showStatus(ModbusPanelStatusKind kind) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ModbusPanelStatusPage(kind: kind, sendCommand: _panel.command),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_stateSubscription.cancel());
    unawaited(_telemetrySubscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final sn = widget.session.sn ?? '';
    final model = info?.model;
    final modelKnown =
        const {'2KU', '3KU', '6KU', '6KU Parallel', '12KU'}.contains(model);
    final received = _receivedAt;
    final age = _telemetry['age_ms'];
    final sampleTime = received != null &&
            age is num &&
            age.isFinite &&
            age >= 0 &&
            age < 0xffffffff
        ? received.subtract(Duration(milliseconds: age.toInt()))
        : null;
    final text = !_connected
        ? _telemetry.isEmpty
            ? _label(context, '无设备数据', 'No device data')
            : _label(context, '上次读数', 'Last readings')
        : info?.online == false
            ? _label(context, '逆变器未响应', 'Inverter unavailable')
            : _live
                ? _label(context, '蓝牙实时数据', 'Live Bluetooth data')
                : _telemetry.isEmpty
                    ? _label(context, '等待逆变器数据', 'Waiting for inverter data')
                    : _label(context, '最后一次收到的数据', 'Last received data');
    final theme = Theme.of(context);
    final localMode = getIt.isRegistered<ConnectionModeService>() &&
        getIt<ConnectionModeService>().isLocal;
    return Scaffold(
      backgroundColor: AppColor.background(context),
      appBar: AppBar(
        title: Text(
          _label(context, '设备详情', 'Device details'),
        ),
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
        actions: [
          IconButton(
            onPressed: _connected ? _refresh : null,
            tooltip: _label(context, '刷新', 'Refresh'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: DeviceSectionNavigation(
        tabs: [
          (Icons.assessment_outlined, _label(context, '概览', 'Overview')),
          (Icons.tune_rounded, _label(context, '设置', 'Settings')),
          (Icons.router_outlined, _label(context, '设备', 'Device')),
        ],
        selectedIndex: _section,
        onSelected: (index) => setState(() => _section = index),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: PageStorageKey(('panel-section', _section)),
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          children: [
            if (_section != 1)
              DeviceConnectionCard(
                icon: _connected ? Icons.bluetooth_connected : Icons.bluetooth,
                connection: _reconnecting
                    ? _label(context, '正在连接蓝牙', 'Connecting over Bluetooth')
                    : _connected
                        ? _label(context, '蓝牙已连接', 'Bluetooth connected')
                        : _label(context, '蓝牙已断开', 'Bluetooth disconnected'),
                connected: _connected,
                dataStatus: text,
                sampleTime: sampleTime,
                action: !_connected && sn.isNotEmpty
                    ? IconButton(
                        tooltip:
                            _label(context, '重新连接面板', 'Reconnect to panel'),
                        onPressed: _reconnecting ? null : _reconnect,
                        icon: _reconnecting
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                      )
                    : null,
              ),
            if (info != null && !info.confirmed)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () =>
                      _showStatus(ModbusPanelStatusKind.diagnostics),
                  icon: const Icon(Icons.tune),
                  label: Text(
                    _label(context, '确认逆变器机型', 'Confirm inverter model'),
                  ),
                ),
              ),
            if (_error != null)
              ListTile(
                leading:
                    Icon(Icons.error_outline, color: theme.colorScheme.error),
                title: Text(_errorText(context, _error!)),
              ),
            const SizedBox(height: 12),
            if (_section == 0) ...[
              ModbusPanelOverview(
                telemetry: _telemetry,
                live: _live,
                model: modelKnown ? model : null,
              ),
              const SizedBox(height: 12),
              DeviceActionButton(
                icon: Icons.insights_outlined,
                title: _label(context, '完整运行参数', 'All parameters'),
                description: _label(context, '查看电压、电流、温度和输出读数',
                    'View voltage, current, temperature and output readings'),
                onPressed: _connected
                    ? () => _showStatus(ModbusPanelStatusKind.metrics)
                    : null,
              ),
              const SizedBox(height: 10),
              DeviceActionButton(
                icon: Icons.warning_amber_outlined,
                title: _label(context, '故障告警', 'Faults and warnings'),
                description: _label(context, '查看当前故障和面板告警',
                    'View current faults and panel alarms'),
                onPressed: _connected
                    ? () => _showStatus(ModbusPanelStatusKind.alarms)
                    : null,
              ),
            ] else if (_section == 1) ...[
              if (_connected && info != null)
                _PanelSettings(
                  key: ValueKey((
                    widget.session.connectionSessionId,
                    info.context,
                    _english,
                  )),
                  panel: _panel,
                  device: sn,
                )
              else ...[
                DeviceSettingsHeader(
                  title: _label(context, '逆变器设置', 'Inverter settings'),
                  icon: Icons.bluetooth_rounded,
                  device: sn,
                  status: _reconnecting
                      ? _label(context, '正在连接蓝牙', 'Connecting over Bluetooth')
                      : _connected
                          ? _label(context, '蓝牙直连', 'Bluetooth direct')
                          : _label(context, '蓝牙已断开', 'Bluetooth disconnected'),
                  ready: _connected,
                  detail: _connected
                      ? _label(
                          context, '正在读取参数目录', 'Reading settings catalogue')
                      : null,
                  readLabel: _label(context, '读取设备', 'Read device'),
                  reading: _connected && _error == null,
                  refreshLabel: _connected || sn.isEmpty
                      ? null
                      : _label(context, '重新连接面板', 'Reconnect to panel'),
                  onRefresh: _reconnecting ? null : _reconnect,
                ),
                if (!_connected) ...[
                  const SizedBox(height: 10),
                  DeviceSettingsNotice(
                    warning: true,
                    text: _label(
                      context,
                      '靠近面板并重新连接蓝牙后，可读取设置。',
                      'Reconnect near the panel to read settings.',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              SettingsCard(
                [
                  SettingsValueRow(
                    icon: Icons.settings_outlined,
                    accent: _connected
                        ? AppColor.primary(context)
                        : AppColor.textSecondary(context),
                    title: _label(context, '辅助设置', 'Panel settings'),
                    subtitle: _label(
                      context,
                      '显示、声音、电池协议和时间',
                      'Display, sound, battery protocol and time',
                    ),
                    onTap: _connected
                        ? () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => ModbusPanelAuxPage(
                                  sendCommand: _panel.command,
                                ),
                              ),
                            )
                        : null,
                  ),
                ],
                margin: EdgeInsets.zero,
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppColor.card(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DeviceSettingsHeading(
                      title: _label(context, '逆变器开关机', 'Inverter power'),
                      description: !_connected
                          ? _label(context, '连接蓝牙后可操作',
                              'Connect over Bluetooth to control power')
                          : info == null
                              ? _label(context, '正在读取控制状态',
                                  'Reading control availability')
                              : !info.confirmed
                                  ? _label(context, '请先确认逆变器机型',
                                      'Confirm the inverter model first')
                                  : !info.online
                                      ? _label(context, '逆变器未响应，请检查通信',
                                          'No inverter response. Check the connection.')
                                      : !info.canPowerOn && !info.canPowerOff
                                          ? _label(context, '设备当前未开放开关机操作',
                                              'Power control is currently unavailable')
                                          : _label(context, '通过蓝牙控制逆变器供电',
                                              'Control inverter power over Bluetooth'),
                    ),
                    DevicePowerButtons(
                      startLabel: _label(context, '开机', 'Start'),
                      stopLabel: _label(context, '关机', 'Stop'),
                      busy: _powerBusy,
                      onStart:
                          !_powerBusy && _connected && info?.canPowerOn == true
                              ? () => _power(1)
                              : null,
                      onStop:
                          !_powerBusy && _connected && info?.canPowerOff == true
                              ? () => _power(2)
                              : null,
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                      ),
                      onPressed: !_powerBusy &&
                              _connected &&
                              info?.confirmed == true &&
                              info?.online == true
                          ? () => _power(0)
                          : null,
                      icon: const Icon(Icons.settings_power_outlined),
                      label: Text(
                        _label(
                          context,
                          '停用远程开关机',
                          'Disable remote power control',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  if (!localMode && sn.isNotEmpty) ...[
                    DeviceActionButton(
                      icon: Icons.cloud_outlined,
                      title: _label(context, '远程设置', 'Remote settings'),
                      description: _label(context, '通过云端查看和调整参数',
                          'View and change settings through the cloud'),
                      onPressed: () => context.pushNamed(
                        'deviceRealtime',
                        pathParameters: {'sn': sn},
                        queryParameters: {'view': 'remote'},
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  DeviceActionButton(
                    icon: Icons.wifi,
                    title: _label(context, 'Wi-Fi 配网', 'Wi-Fi setup'),
                    description: _label(context, '设置设备连接的无线网络',
                        'Choose the device wireless network'),
                    onPressed: sn.isEmpty
                        ? null
                        : () => context.pushNamed('wifiConfig',
                            queryParameters: {'sn': sn}),
                  ),
                  const SizedBox(height: 10),
                  DeviceActionButton(
                    icon: Icons.system_update_outlined,
                    title: _label(context, '本地固件升级', 'Local firmware upgrade'),
                    description: _label(context, '通过蓝牙传输设备固件',
                        'Transfer device firmware over Bluetooth'),
                    onPressed: !_connected || sn.isEmpty
                        ? null
                        : () => context.pushNamed(
                              'otaLocal',
                              pathParameters: {'sn': sn},
                              queryParameters: {
                                'channel': 'ble',
                                'device_model': 'CS-MB-PANEL',
                                'mac': widget.session.macAddress,
                              },
                            ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PanelSettings extends StatefulWidget {
  const _PanelSettings({
    super.key,
    required this.panel,
    required this.device,
  });

  final ModbusPanelBle panel;
  final String device;

  @override
  State<_PanelSettings> createState() => _PanelSettingsState();
}

class _PanelSettingsState extends State<_PanelSettings> {
  List<ModbusPanelSetting> _items = [];
  ModbusPanelInfo? _info;
  bool _loading = false;
  int _readCount = 0;
  int _readTotal = 0;
  Object? _error;
  String _query = '';
  String? _selectedGroup;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _readCount = 0;
      _readTotal = _info?.count ?? 0;
      _error = null;
    });
    try {
      final info = await widget.panel.info();
      if (!mounted) return;
      setState(() {
        _readTotal = info.count;
        if (info.context != _info?.context || info.count != _info?.count) {
          _items = [];
          _selectedGroup = null;
        }
        _info = info;
      });
      final snapshot = <ModbusPanelSetting>[];
      for (var index = 0; index < info.count && mounted; index++) {
        final item = await widget.panel.setting(index);
        if (!mounted) return;
        if (item.context != info.context) {
          throw const BleCommandException('CONTEXT_CHANGED', 'Model changed');
        }
        snapshot.add(item);
        setState(() => _readCount = snapshot.length);
      }
      if (mounted) setState(() => _items = snapshot);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(ModbusPanelSetting setting) async {
    final updated = await showDialog<ModbusPanelSetting>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PanelEditDialog(panel: widget.panel, original: setting),
    );
    if (!mounted ||
        updated == null ||
        updated.context != _info?.context ||
        updated.index >= _items.length) {
      return;
    }
    setState(() => _items[updated.index] = updated);
  }

  void _selectGroup(String group) {
    Scrollable.maybeOf(context)?.position.jumpTo(0);
    setState(() => _selectedGroup = group);
  }

  (IconData, Color) _groupStyle(String group) => switch (group) {
        '输出与模式' || 'Output' || 'Output and mode' => (Icons.power_outlined, AppColors.blue),
        '双路输出' || 'Dual output' || 'Output 2' => (Icons.electrical_services_rounded, AppColors.cyan),
        '并机设置' || 'Parallel' || 'Parallel settings' => (Icons.hub_outlined, AppColors.indigo),
        '充电与电池' || 'Battery' || 'Charging and battery' => (Icons.battery_charging_full_outlined, AppColors.teal),
        '均衡充电' || 'Equalize' || 'Equalization' => (Icons.balance_rounded, AppColors.indigo),
        'BMS通信' || 'BMS' || 'BMS link' => (Icons.cable_rounded, AppColors.cyan),
        '发电机' || 'Generator' => (Icons.local_gas_station_outlined, AppColors.orange),
        '系统功能' || 'System' => (Icons.settings_outlined, AppColors.purple),
        _ => (Icons.tune_rounded, AppColors.blue),
      };

  String _groupSummary(List<ModbusPanelSetting> items) {
    final total = items.length;
    final editable = items.where((item) => item.editable).length;
    if (editable == total) {
      return _label(context, '$total 项可调', '$total adjustable');
    }
    if (editable == 0) return _label(context, '$total 项只读', '$total read-only');
    return _label(
      context,
      '$total 项参数 · $editable 项可调',
      '$total settings · $editable adjustable',
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ModbusPanelSetting>>{};
    final settings = _items.where((item) => item.id != 'panel_4123');
    for (final item in settings) {
      if ('${item.label} ${item.group} ${item.id}'
          .toLowerCase()
          .contains(_query)) {
        groups.putIfAbsent(item.group, () => []).add(item);
      }
    }
    final searching = _query.isNotEmpty;
    final selected =
        _selectedGroup ?? (groups.length == 1 ? groups.keys.first : '');
    final selectedItems = groups[selected];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeviceSettingsHeader(
          title: _label(context, '逆变器设置', 'Inverter settings'),
          icon: Icons.bluetooth_connected_rounded,
          device: widget.device,
          status: _label(context, '蓝牙直连', 'Bluetooth direct'),
          ready: true,
          readLabel: _label(context, '读取设备', 'Read device'),
          detail: _loading
              ? _label(
                  context,
                  _readTotal > 0 ? '读取中 $_readCount/$_readTotal' : '正在读取参数',
                  _readTotal > 0
                      ? 'Reading $_readCount/$_readTotal'
                      : 'Reading settings',
                )
              : _error != null
                  ? null
                  : _label(
                      context,
                      '${settings.length} 项参数',
                      '${settings.length} settings',
                    ),
          reading: _loading,
          readProgress: _readTotal > 0 ? _readCount / _readTotal : null,
          onRead: _load,
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 10),
          DeviceSettingsNotice(warning: true, text: _errorText(context, error)),
        ],
        const SizedBox(height: 14),
        DeviceSearchBar(
          padding: EdgeInsets.zero,
          hintText: _label(context, '搜索参数', 'Search settings'),
          fillColor: AppColor.surfaceContainer(context),
          onSearchChanged: (text) =>
              setState(() => _query = text.trim().toLowerCase()),
        ),
        const SizedBox(height: 16),
        if (!_loading && _error == null && groups.isEmpty)
          DeviceSettingsNotice(
            text: searching
                ? _label(context, '未找到匹配的参数', 'No matching settings')
                : _label(context, '设备当前没有可用参数', 'No settings available'),
          )
        else if (searching && groups.isNotEmpty)
          _buildGroupContent(groups)
        else if (selectedItems != null) ...[
          DeviceSettingsCategoryBack(onPressed: () => _selectGroup('')),
          _buildGroupContent({selected: selectedItems}),
        ] else if (groups.isNotEmpty)
          DeviceSettingsDirectory(
            entries: groups.entries.map((group) {
              final (icon, color) = _groupStyle(group.key);
              return (
                title: group.key,
                summary: _groupSummary(group.value),
                icon: icon,
                accent: AppColor.accent(context, color),
                onTap: () => _selectGroup(group.key),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildGroupContent(Map<String, List<ModbusPanelSetting>> groups) {
    final theme = Theme.of(context);
    final accent = AppColor.primary(context);
    final muted = AppColor.textSecondary(context);
    return SettingsCard(
      groups.entries.map((group) {
        final (icon, color) = _groupStyle(group.key);
        return DeviceSettingsGroupCard(
          key: ValueKey(group.key),
          compact: true,
          title: group.key,
          summary: _groupSummary(group.value),
          icon: icon,
          accent: AppColor.accent(context, color),
          expanded: true,
          onToggle: null,
          content: Column(
            children: [
              for (final item in group.value) ...[
                Divider(
                  height: 1,
                  indent: 14,
                  endIndent: 14,
                  color: AppColor.divider(context),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  title: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          item.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColor.textPrimary(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 2,
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            item.value != null ? item.text : '—',
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: item.editable && item.value != null
                                  ? accent
                                  : muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: item.reason.isNotEmpty ? Text(item.reason) : null,
                  trailing: Icon(
                    item.editable
                        ? Icons.chevron_right_rounded
                        : Icons.lock_outline_rounded,
                    size: 19,
                    color: muted,
                  ),
                  onTap: _loading || _error != null ? null : () => _edit(item),
                ),
              ],
            ],
          ),
        );
      }).toList(),
      margin: EdgeInsets.zero,
    );
  }
}

class _PanelEditDialog extends StatefulWidget {
  const _PanelEditDialog({required this.panel, required this.original});

  final ModbusPanelBle panel;
  final ModbusPanelSetting original;

  @override
  State<_PanelEditDialog> createState() => _PanelEditDialogState();
}

class _PanelEditDialogState extends State<_PanelEditDialog> {
  late ModbusPanelSetting _setting = widget.original;
  ModbusPanelValue? _draft;
  ModbusPanelWriteOutcome? _receipt;
  Object? _error;
  bool _busy = false;
  bool _writing = false;
  bool _ready = false;
  late final String? _sessionId = widget.panel.session.connectionSessionId;

  void _checkContext(int context) {
    if (context != widget.original.context ||
        _sessionId != widget.panel.session.connectionSessionId) {
      throw const BleCommandException(
        'CONTEXT_CHANGED',
        'Device context changed',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<ModbusPanelSetting> _readCurrent() async {
    final timer = Stopwatch()..start();
    var item = await widget.panel.setting(_setting.index, refresh: true);
    while (
        mounted && item.reading && timer.elapsed < const Duration(seconds: 5)) {
      _checkContext(item.context);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) break;
      item = await widget.panel.setting(_setting.index, refresh: true);
    }
    return item;
  }

  Future<void> _read() async {
    setState(() {
      _busy = true;
      _ready = false;
      _draft = null;
      _error = null;
    });
    try {
      final item = await _readCurrent();
      if (!mounted) return;
      _checkContext(item.context);
      setState(() {
        _setting = item;
        _ready = !item.reading;
      });
      if (item.reading) {
        throw const BleCommandException(
          'SYNC_TIMEOUT',
          'Parameter read timed out',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _step(int direction) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _checkContext(_setting.context);
      final value = await widget.panel.step(
        _setting.index,
        _draft?.raw ?? _setting.value,
        direction,
      );
      _checkContext(value.context);
      if (mounted) setState(() => _draft = value);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write() async {
    final value = _draft;
    if (_busy || value == null) return;
    setState(() {
      _busy = true;
      _writing = true;
      _error = null;
    });
    try {
      _checkContext(value.context);
      final result = await widget.panel.write(
        _setting.id,
        value.raw,
        value.context,
        bmsSuggestion: identical(value, _setting.suggestion),
      );
      if (!mounted) return;
      setState(() => _receipt = result);
      final actual = await _readCurrent();
      if (!mounted) return;
      _checkContext(actual.context);
      if (!actual.reading) setState(() => _setting = actual);
    } catch (error) {
      if (error is BleCommandException && error.code == 'VALUE_MISMATCH') {
        try {
          final actual = await _readCurrent();
          if (!mounted) return;
          _checkContext(actual.context);
          if (!actual.reading) setState(() => _setting = actual);
        } catch (_) {
          // Keep the original mismatch if the follow-up read also fails.
        }
      }
      if (mounted) {
        setState(() {
          _error = error;
          _ready = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _writing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = _ready && _setting.editable && _receipt == null;
    final suggestion = _setting.suggestion;
    return PopScope(
      canPop: !_writing,
      child: AlertDialog(
        title: Text(_setting.label),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 320,
                child: DeviceSettingChange(
                  current: _setting.text,
                  target: editing ? _draft?.text : null,
                ),
              ),
              if (_setting.reason.isNotEmpty) Text(_setting.reason),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) Text(_errorText(context, _error!)),
              if (_receipt case final receipt?)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    receipt == ModbusPanelWriteOutcome.applied
                        ? Icons.check_circle_outline
                        : Icons.pending_outlined,
                  ),
                  title: Text(_receiptText(context, receipt)),
                ),
              if (editing) ...[
                const SizedBox(height: 10),
                if (suggestion != null)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _draft = suggestion),
                    child: Text(
                      _label(
                        context,
                        '采用电池建议 ${suggestion.text}',
                        'Use battery recommendation ${suggestion.text}',
                      ),
                    ),
                  ),
                Wrap(
                  children: [
                    IconButton(
                      onPressed: _busy ? null : () => _step(-10),
                      tooltip: _label(context, '减少十步', 'Decrease ten steps'),
                      icon: const Text('−10'),
                    ),
                    IconButton(
                      onPressed: _busy ? null : () => _step(-1),
                      tooltip: _label(context, '减少', 'Decrease'),
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      onPressed: _busy ? null : () => _step(1),
                      tooltip: _label(context, '增加', 'Increase'),
                      icon: const Icon(Icons.add),
                    ),
                    IconButton(
                      onPressed: _busy ? null : () => _step(10),
                      tooltip: _label(context, '增加十步', 'Increase ten steps'),
                      icon: const Text('+10'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _writing ? null : () => Navigator.pop(context, _setting),
            child: Text(_label(context, '关闭', 'Close')),
          ),
          if (!_ready && !_busy && _receipt == null)
            TextButton(
              onPressed: _read,
              child: Text(_label(context, '读取', 'Read')),
            ),
          if (editing)
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(144, 52),
              ),
              onPressed:
                  !_busy && _draft != null && _draft!.raw != _setting.value
                      ? _write
                      : null,
              child: Text(_label(context, '写入', 'Apply')),
            ),
        ],
      ),
    );
  }
}
