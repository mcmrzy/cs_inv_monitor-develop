import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/modbus_panel_ble.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/device/presentation/pages/modbus_panel_aux_page.dart';
import 'package:inv_app/features/device/presentation/widgets/modbus_panel_metrics.dart';
import 'package:inv_app/features/device/presentation/widgets/modbus_panel_overview.dart';

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
  late bool _showParameters = !widget.startInSettings;
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
    if (_polling || !_connected || widget.session.isOtaInProgress) return;
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
                builder: (_) => ModbusPanelPage(session: session)),
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
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(title),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (!_connected ||
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

  Future<void> _showSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _PanelSettingsPage(panel: _panel),
      ),
    );
    if (mounted) unawaited(_refresh());
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
    final modelKnown = const {'2KU', '3KU', '6KU', '12KU'}.contains(model);
    final received = _receivedAt;
    final age = _telemetry['age_ms'];
    final sampleTime =
        received != null && age is num && age.isFinite && age >= 0
            ? received.subtract(Duration(milliseconds: age.toInt()))
            : null;
    final text = !_connected
        ? _telemetry.isEmpty
            ? _label(context, '蓝牙已断开', 'Bluetooth disconnected')
            : _label(
                context,
                '蓝牙已断开 · 上次读数',
                'Bluetooth disconnected · Last readings',
              )
        : info?.online == false
            ? _label(context, '逆变器未响应', 'Inverter unavailable')
            : _live
                ? _label(context, '蓝牙实时数据', 'Live Bluetooth data')
                : _telemetry.isEmpty
                    ? _label(context, '等待逆变器数据', 'Waiting for inverter data')
                    : _label(context, '最后一次收到的数据', 'Last received data');
    return Scaffold(
      appBar: AppBar(
        title: Text(_label(context, '蓝牙直连', 'Bluetooth direct')),
        actions: [
          IconButton(
            onPressed: _connected ? _refresh : null,
            tooltip: _label(context, '刷新', 'Refresh'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              modelKnown ? model! : _label(context, '逆变器面板', 'Inverter panel'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (sn.isNotEmpty) Text(sn),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  _connected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sampleTime == null
                        ? text
                        : '$text · ${DateFormat('HH:mm:ss').format(sampleTime)}',
                  ),
                ),
              ],
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
            if (_error != null) Text(_errorText(context, _error!)),
            if (!_connected && sn.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.bluetooth_searching),
                title: Text(
                  _reconnecting
                      ? _label(context, '正在连接', 'Connecting')
                      : _label(context, '重新连接面板', 'Reconnect to panel'),
                ),
                onTap: _reconnecting ? null : _reconnect,
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: Text(_label(context, '参数查看', 'Parameters')),
                  selected: _showParameters,
                  onSelected: (_) => setState(() => _showParameters = true),
                ),
                ChoiceChip(
                  label: Text(_label(context, '蓝牙设置', 'Bluetooth settings')),
                  selected: !_showParameters,
                  onSelected: (_) => setState(() => _showParameters = false),
                ),
                if (sn.isNotEmpty)
                  ActionChip(
                    label: Text(_label(context, '远程设置', 'Remote settings')),
                    onPressed: () => context.pushNamed(
                      'deviceRealtime',
                      pathParameters: {'sn': sn},
                      queryParameters: {'view': 'remote'},
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_showParameters) ...[
              ModbusPanelOverview(telemetry: _telemetry),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _connected
                        ? () => _showStatus(ModbusPanelStatusKind.metrics)
                        : null,
                    icon: const Icon(Icons.insights_outlined),
                    label: Text(_label(context, '完整运行参数', 'All parameters')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _connected
                        ? () => _showStatus(ModbusPanelStatusKind.alarms)
                        : null,
                    icon: const Icon(Icons.warning_amber_outlined),
                    label: Text(_label(context, '故障告警', 'Faults and warnings')),
                  ),
                ],
              ),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed:
                        _connected && info != null ? _showSettings : null,
                    icon: const Icon(Icons.tune),
                    label: Text(_label(context, '逆变器设置', 'Inverter settings')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed:
                        !_powerBusy && _connected && info?.canPowerOn == true
                            ? () => _power(1)
                            : null,
                    icon: const Icon(Icons.power_settings_new),
                    label: Text(_label(context, '开启', 'Start')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed:
                        !_powerBusy && _connected && info?.canPowerOff == true
                            ? () => _power(2)
                            : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(_label(context, '关闭', 'Stop')),
                  ),
                  OutlinedButton.icon(
                    onPressed: !_powerBusy &&
                            _connected &&
                            info?.confirmed == true &&
                            info?.online == true
                        ? () => _power(0)
                        : null,
                    icon: const Icon(Icons.settings_power_outlined),
                    label: Text(_label(
                        context, '停用远程开关机', 'Disable remote power control')),
                  ),
                ],
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(_label(context, '辅助设置', 'Panel settings')),
                enabled: _connected,
                trailing: const Icon(Icons.chevron_right),
                onTap: _connected
                    ? () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) =>
                                ModbusPanelAuxPage(sendCommand: _panel.command),
                          ),
                        )
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.wifi),
                title: Text(_label(context, 'Wi-Fi 配网', 'Wi-Fi setup')),
                trailing: const Icon(Icons.chevron_right),
                onTap: sn.isEmpty
                    ? null
                    : () => context
                        .pushNamed('wifiConfig', queryParameters: {'sn': sn}),
              ),
              ListTile(
                leading: const Icon(Icons.system_update_outlined),
                title:
                    Text(_label(context, '本地固件升级', 'Local firmware upgrade')),
                trailing: const Icon(Icons.chevron_right),
                onTap: !_connected || sn.isEmpty
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
          ],
        ),
      ),
    );
  }
}

class _PanelSettingsPage extends StatefulWidget {
  const _PanelSettingsPage({required this.panel});

  final ModbusPanelBle panel;

  @override
  State<_PanelSettingsPage> createState() => _PanelSettingsPageState();
}

class _PanelSettingsPageState extends State<_PanelSettingsPage> {
  final _items = <ModbusPanelSetting>[];
  ModbusPanelInfo? _info;
  bool _loading = false;
  Object? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await widget.panel.info();
      if (!mounted) return;
      setState(() {
        if (reset || info.context != _info?.context) _items.clear();
        _info = info;
      });
      for (var index = _items.length; index < info.count && mounted; index++) {
        final item = await widget.panel.setting(index);
        if (!mounted) return;
        if (item.context != info.context) {
          throw const BleCommandException('CONTEXT_CHANGED', 'Model changed');
        }
        setState(() => _items.add(item));
      }
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

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ModbusPanelSetting>>{};
    for (final item in _items) {
      if (item.id != 'panel_4123' &&
          '${item.label} ${item.group} ${item.id}'
              .toLowerCase()
              .contains(_query)) {
        groups.putIfAbsent(item.group, () => []).add(item);
      }
    }
    final count = _info?.count ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(_label(context, '逆变器设置', 'Inverter settings')),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh),
            tooltip: _label(context, '刷新', 'Refresh'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: _label(context, '搜索参数', 'Search settings'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (text) =>
                setState(() => _query = text.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
          if (_loading)
            LinearProgressIndicator(
              value: count > 0 ? _items.length / count : null,
              semanticsLabel: _label(context, '正在读取参数', 'Reading settings'),
            ),
          if (_error != null) Text(_errorText(context, _error!)),
          for (final group in groups.entries)
            Card(
              child: ExpansionTile(
                key: ValueKey((group.key, _query)),
                title: Text(group.key),
                initiallyExpanded: _query.isNotEmpty || groups.length == 1,
                children: [
                  for (final item in group.value)
                    ListTile(
                      title: Text(item.label),
                      subtitle: Text(
                        [
                          if (item.value != null) item.text,
                          if (item.value == null && item.editable)
                            _label(
                              context,
                              '打开后读取当前值',
                              'Open to read current value',
                            ),
                          if (item.reason.isNotEmpty) item.reason,
                        ].join('\n'),
                      ),
                      trailing: Icon(
                        item.editable
                            ? Icons.chevron_right
                            : Icons.lock_outline,
                      ),
                      onTap: () => _edit(item),
                    ),
                ],
              ),
            ),
          if (!_loading &&
              _error == null &&
              _query.isNotEmpty &&
              groups.isEmpty)
            ListTile(
              title: Text(_label(context, '未找到匹配的参数', 'No matching settings')),
            ),
          if (!_loading && _error != null)
            OutlinedButton(
              onPressed: () => _load(reset: true),
              child: Text(_label(context, '重新读取', 'Read again')),
            ),
        ],
      ),
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
                child: ModbusPanelMetrics(
                  values: [
                    (_label(context, '当前值', 'Current value'), _setting.text),
                    if (_draft != null)
                      (_label(context, '目标值', 'Target value'), _draft!.text),
                  ],
                ),
              ),
              if (_setting.reason.isNotEmpty) Text(_setting.reason),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) Text(_errorText(context, _error!)),
              if (_receipt != null) Text(_receiptText(context, _receipt!)),
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
                      icon: const Icon(Icons.keyboard_double_arrow_left),
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
                      icon: const Icon(Icons.keyboard_double_arrow_right),
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
