import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/features/device/domain/entities/modbus_panel_alarms.dart';
import 'package:inv_app/features/device/presentation/widgets/modbus_panel_metrics.dart';

typedef PanelCommand = Future<Map<String, dynamic>> Function(
  String action,
  Map<String, dynamic> params,
);

String _label(BuildContext context, String chinese, String english) =>
    Localizations.localeOf(context).languageCode == 'zh' ? chinese : english;

int? _integer(Object? value) {
  if (value is! num || !value.isFinite || value != value.roundToDouble()) {
    return null;
  }
  return value.toInt();
}

String _utcOffset(int minutes) {
  final sign = minutes < 0 ? '−' : '+';
  final magnitude = minutes.abs();
  final hour = (magnitude ~/ 60).toString().padLeft(2, '0');
  final minute = (magnitude % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hour:$minute';
}

String _errorMessage(BuildContext context, Object error) {
  switch (error is BleCommandException ? error.code : '') {
    case 'BUSY':
      return _label(context, '面板正在处理其他操作', 'The panel is busy');
    case 'UPGRADE_BUSY':
      return _label(context, '请等待固件升级结束', 'Wait for the firmware update');
    case 'NOT_READY':
      return _label(context, '面板暂未准备好', 'The panel is not ready');
    case 'OUT_OF_RANGE':
    case 'INVALID_ARGS':
      return _label(context, '面板不支持这个值', 'The panel cannot use this value');
    case 'REVISION_CONFLICT':
    case 'CONTEXT_CHANGED':
      return _label(context, '通信配置已变化，请刷新后重试',
          'The connection configuration changed. Refresh and retry.');
    case 'STORAGE_FAILED':
      return _label(context, '面板保存失败', 'The panel could not save the change');
    case 'PROTOCOL_UNSUPPORTED':
    case 'UNSUPPORTED_ACTION':
      return _label(
          context, '此固件不支持该操作', 'This firmware does not support this action');
    default:
      return _label(
        context,
        '没有收到面板结果，请检查蓝牙连接后重试',
        'The panel did not respond. Check Bluetooth and try again.',
      );
  }
}

class ModbusPanelAuxPage extends StatefulWidget {
  const ModbusPanelAuxPage({super.key, required this.sendCommand});

  final PanelCommand sendCommand;

  @override
  State<ModbusPanelAuxPage> createState() => _ModbusPanelAuxPageState();
}

class _ModbusPanelAuxPageState extends State<ModbusPanelAuxPage> {
  static const _timeouts = [0, 30, 60, 120, 300, 600];
  Map<String, dynamic>? _settings;
  Object? _loadError;
  bool _busy = true;
  bool _statusOpen = false;
  Timer? _detectPoll;

  String _t(String zh, String en) => _label(context, zh, en);
  int? _value(String key) => _integer(_settings?[key]);
  bool get _canChange => !_busy && _loadError == null;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _detectPoll?.cancel();
    super.dispose();
  }

  Future<void> _readSettings() async {
    final settings = await widget.sendCommand('panel_aux', const {});
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loadError = null;
    });
  }

  Future<void> _refresh() async {
    try {
      await _readSettings();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scheduleDetectionRead();
      }
    }
  }

  void _scheduleDetectionRead() {
    _detectPoll?.cancel();
    if (_value('detect') != 1 || _loadError != null || _statusOpen) return;
    _detectPoll = Timer(const Duration(seconds: 1), () {
      if (!mounted || _busy || _statusOpen) return;
      setState(() => _busy = true);
      unawaited(_refresh());
    });
  }

  Future<void> _write(String key, int value) async {
    if (!_canChange) return;
    _detectPoll?.cancel();
    setState(() => _busy = true);
    try {
      final result = await widget.sendCommand('set_param', {
        'param_id': 'panel_$key',
        'value': value,
      });
      if (!mounted) return;
      final receivedValue =
          result['observed'] == true && _integer(result['value']) != null;
      final started = key == 'bms_detect' && result['submitted'] == true;
      if (!receivedValue && !started) {
        _notice(_t('面板未返回已保存的值', 'The panel did not return the saved value'));
      }
    } on Object catch (error) {
      if (mounted) _notice(_errorMessage(context, error));
    }
    if (mounted) await _refresh();
  }

  void _notice(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _choose(
    String key,
    String title,
    Map<int, String> choices,
  ) async {
    if (!_canChange) return;
    final current = _value(key);
    final result = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final option in choices.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option.key),
              child: Row(
                children: [
                  Expanded(child: Text(option.value)),
                  if (option.key == current) const Icon(Icons.check, size: 20),
                ],
              ),
            ),
        ],
      ),
    );
    if (mounted && result != null && result != current) {
      await _write(key, result);
    }
  }

  Future<void> _chooseLevel(String key, String title, int min) async {
    final current = _value(key);
    if (!_canChange || current == null) return;
    var draft = current.clamp(min, 100).toDouble();
    final level = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${draft.round()}%'),
              Slider(
                value: draft,
                min: min.toDouble(),
                max: 100,
                divisions: 100 - min,
                label: '${draft.round()}%',
                onChanged: (value) => setDialogState(() => draft = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, draft.round()),
              child: Text(_label(context, '保存', 'Save')),
            ),
          ],
        ),
      ),
    );
    if (mounted && level != null && level != current) {
      await _write(key, level);
    }
  }

  Future<void> _chooseTimeZone() async {
    if (!_canChange) return;
    final current = _value('tz');
    if (current == null) return;
    var draft = (current / 15).round().clamp(-48, 56).toDouble();
    final zone = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_label(context, '面板时区', 'Panel time zone')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_utcOffset(draft.round() * 15)),
              Slider(
                value: draft,
                min: -48,
                max: 56,
                divisions: 104,
                label: _utcOffset(draft.round() * 15),
                onChanged: (value) => setDialogState(() => draft = value),
              ),
              TextButton(
                onPressed: () {
                  final phone = DateTime.now().timeZoneOffset.inMinutes;
                  Navigator.pop(context, phone);
                },
                child: Text(_label(context, '使用手机时区', 'Use phone time zone')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, draft.round() * 15),
              child: Text(_label(context, '保存', 'Save')),
            ),
          ],
        ),
      ),
    );
    if (mounted && zone != null && zone != current) {
      await _write('tz', zone);
    }
  }

  Future<void> _syncTime() async {
    if (!_canChange) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_label(context, '同步面板时间', 'Sync panel clock')),
        content: Text(_label(
          context,
          '使用手机当前时间校准面板时钟。',
          'Set the panel clock to the current phone time.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_label(context, '同步', 'Sync')),
          ),
        ],
      ),
    );
    if (mounted && confirm == true) {
      await _write('epoch', DateTime.now().millisecondsSinceEpoch ~/ 1000);
    }
  }

  Future<void> _restorePreferences() async {
    if (!_canChange) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_label(context, '恢复面板偏好设置', 'Restore panel preferences')),
        content: Text(_label(
          context,
          '将显示、声音和时区恢复到默认值。',
          'Restore the default display, sound and time zone settings.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_label(context, '恢复', 'Restore')),
          ),
        ],
      ),
    );
    if (mounted && confirm == true) await _write('reset_prefs', 1);
  }

  Future<void> _openStatus(ModbusPanelStatusKind kind) async {
    if (_busy) return;
    _statusOpen = true;
    _detectPoll?.cancel();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => ModbusPanelStatusPage(
            sendCommand: widget.sendCommand,
            kind: kind,
          ),
        ),
      );
    } finally {
      if (mounted) {
        _statusOpen = false;
        _scheduleDetectionRead();
      }
    }
  }

  Widget _tile(String title, String? value, VoidCallback? onTap) => ListTile(
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        subtitle: Text(value ?? '—'),
        enabled: onTap != null,
        onTap: onTap,
      );

  Widget _group(String title, List<Widget> items) => Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            ...items,
          ],
        ),
      );

  Widget _choiceTile(String key, String title, Map<int, String> choices) =>
      _tile(
        title,
        choices[_value(key)],
        _canChange && choices.containsKey(_value(key))
            ? () => _choose(key, title, choices)
            : null,
      );

  Widget _levelTile(String key, String title, int minimum) {
    final value = _value(key);
    return _tile(
      title,
      value == null ? null : '$value%',
      _canChange && value != null
          ? () => _chooseLevel(key, title, minimum)
          : null,
    );
  }

  String? _panelTime() {
    final epoch = _value('epoch');
    final zone = _value('tz');
    if (epoch == null || epoch <= 0 || zone == null) return null;
    final value = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true)
        .add(Duration(minutes: zone));
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final detect = _value('detect');
    final detectLabels = {
      0: _t('自动识别当前连接的 BMS', 'Detect the connected BMS'),
      1: _t('正在识别', 'Detecting…'),
      2: _t('识别成功', 'Battery detected'),
      3: _t('未收到电池应答', 'No reply from the battery'),
      4: _t('面板未能保存识别结果', 'Could not save the detected protocol'),
    };
    final timeoutLabels = {
      for (var index = 0; index < _timeouts.length; index++)
        index: _timeouts[index] == 0
            ? _t('永不', 'Never')
            : _t('${_timeouts[index]} 秒', '${_timeouts[index]} s'),
    };
    final zone = _value('tz');
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('面板设置', 'Panel settings')),
        actions: [
          IconButton(
            tooltip: _t('刷新', 'Refresh'),
            onPressed: _busy
                ? null
                : () {
                    setState(() => _busy = true);
                    unawaited(_refresh());
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_loadError != null)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(_errorMessage(context, _loadError!)),
            ),
          if (_settings != null) ...[
            _group(_t('显示和声音', 'Display and sound'), [
              _levelTile('brightness', _t('背光亮度', 'Backlight'), 10),
              _choiceTile(
                  'timeout', _t('自动息屏', 'Screen timeout'), timeoutLabels),
              _levelTile('led', _t('指示灯亮度', 'LED brightness'), 0),
              _choiceTile('beep', _t('蜂鸣器响度', 'Buzzer volume'), {
                0: _t('关闭', 'Off'),
                1: _t('低', 'Low'),
                2: _t('中', 'Medium'),
                3: _t('高', 'High'),
              }),
              _choiceTile('alarm', _t('告警提示', 'Alarm sound'), {
                0: _t('关闭', 'Off'),
                1: _t('开启', 'On'),
              }),
              _choiceTile('theme', _t('面板主题', 'Panel theme'), {
                0: _t('深色', 'Dark'),
                1: _t('浅色', 'Light'),
              }),
              _choiceTile('lang', _t('面板语言', 'Panel language'), const {
                0: 'English',
                1: '简体中文',
              }),
            ]),
            _group(_t('电池连接', 'Battery connection'), [
              _choiceTile('bms', _t('电池协议', 'Battery protocol'), const {
                0: 'BBJ',
                1: 'CSERGY',
              }),
              _tile(
                _t('自动识别', 'Auto detect'),
                detectLabels[detect],
                _canChange && detect != null && detect != 1
                    ? () => _write('bms_detect', 1)
                    : null,
              ),
            ]),
            _group(_t('日期和时间', 'Date and time'), [
              _tile(
                _t('时区', 'Time zone'),
                zone == null ? null : _utcOffset(zone),
                _canChange && zone != null ? _chooseTimeZone : null,
              ),
              _tile(
                _t('同步手机时间', 'Sync with phone'),
                _panelTime(),
                _canChange ? _syncTime : null,
              ),
            ]),
          ],
          _group(_t('状态与诊断', 'Status and diagnostics'), [
            _tile(
              _t('运行数据', 'Operating data'),
              _t('查看逆变器各路数据', 'View inverter measurements'),
              _busy ? null : () => _openStatus(ModbusPanelStatusKind.metrics),
            ),
            _tile(
              _t('电池数据', 'Battery data'),
              _t('查看实时读数和单体电压', 'Readings and cell voltages'),
              _busy ? null : () => _openStatus(ModbusPanelStatusKind.battery),
            ),
            _tile(
              _t('故障告警', 'Faults and warnings'),
              _t('查看面板收到的告警', 'View alarms from the panel'),
              _busy ? null : () => _openStatus(ModbusPanelStatusKind.alarms),
            ),
            _tile(
              _t('通信诊断', 'Link diagnostics'),
              _t('查看机型和串口连接', 'Model and serial connection'),
              _busy
                  ? null
                  : () => _openStatus(ModbusPanelStatusKind.diagnostics),
            ),
          ]),
          if (_settings != null)
            _tile(
              _t('恢复面板偏好设置', 'Restore panel preferences'),
              _t('显示、声音和时区', 'Display, sound and time zone'),
              _canChange ? _restorePreferences : null,
            ),
        ],
      ),
    );
  }
}

enum ModbusPanelStatusKind { battery, alarms, diagnostics, metrics }

class ModbusPanelStatusPage extends StatefulWidget {
  const ModbusPanelStatusPage({
    super.key,
    required this.sendCommand,
    required this.kind,
  });

  final PanelCommand sendCommand;
  final ModbusPanelStatusKind kind;

  @override
  State<ModbusPanelStatusPage> createState() => _ModbusPanelStatusPageState();
}

class _ModbusPanelStatusPageState extends State<ModbusPanelStatusPage> {
  static const _metricPages = [0, 1, 2, 4, 5, 6, 7];
  static const _bauds = [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200];
  Map<String, dynamic>? _data;
  Object? _error;
  bool _loading = false;
  DateTime? _scanRequestedUntil;
  int _page = 0;
  Timer? _refreshTimer;

  String _t(String zh, String en) => _label(context, zh, en);

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _read([int? newPage]) async {
    if (_loading) return;
    _refreshTimer?.cancel();
    setState(() => _loading = true);
    var page = newPage ?? _page;
    try {
      var result = switch (widget.kind) {
        ModbusPanelStatusKind.battery =>
          await widget.sendCommand('panel_battery', {'page': page}),
        ModbusPanelStatusKind.alarms =>
          await widget.sendCommand('panel_alarms', const {}),
        ModbusPanelStatusKind.diagnostics =>
          await widget.sendCommand('panel_diag', const {}),
        ModbusPanelStatusKind.metrics => await _readMetrics(page),
      };
      if (!mounted) return;
      final cells = (_integer(result['count']) ?? 0).clamp(0, 32);
      if (widget.kind == ModbusPanelStatusKind.battery &&
          page > 0 &&
          page * 8 >= cells) {
        page = 0;
        result = await widget.sendCommand('panel_battery', {'page': page});
        if (!mounted) return;
      }
      setState(() {
        _data = result;
        _page = page;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        final scanPending =
            _scanRequestedUntil?.isAfter(DateTime.now()) == true;
        if (widget.kind != ModbusPanelStatusKind.diagnostics ||
            (_error == null && (_data?['scanning'] == true || scanPending))) {
          _scheduleRefresh();
        }
      }
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final seconds = _error != null
        ? 5
        : widget.kind == ModbusPanelStatusKind.diagnostics
            ? 1
            : 3;
    _refreshTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _scheduleRefresh();
      } else {
        unawaited(_read());
      }
    });
  }

  Future<Map<String, dynamic>> _readMetrics(int page) async {
    final first = await widget.sendCommand('panel_metric', {
      'page': _metricPages[page],
      'offset': 0,
    });
    if (!mounted || first['next'] != 4) return first;
    final second = await widget.sendCommand('panel_metric', {
      'page': _metricPages[page],
      'offset': 4,
    });
    return {
      ...first,
      'rows': [
        if (first['rows'] case final List<dynamic> rows) ...rows,
        if (second['rows'] case final List<dynamic> rows) ...rows,
      ],
    };
  }

  ListTile _row(String title, String value, {IconData? icon}) => ListTile(
        leading: icon == null ? null : Icon(icon),
        title: Text(title),
        trailing: Text(value),
      );

  String _number(
      Map<String, dynamic> data, String key, String unit, int decimals) {
    final value = data[key];
    return value is num && value.isFinite
        ? '${value.toStringAsFixed(decimals)} $unit'
        : '—';
  }

  Iterable<Widget> _battery(Map<String, dynamic> data) sync* {
    final online = data['online'] == true && _error == null;
    final age = _integer(data['age']);
    final pack = switch (_integer(data['protocol'])) {
      0 => 'BBJ',
      1 => 'CSERGY',
      _ => '—',
    };
    yield _row(
      _t('电池连接', 'Battery connection'),
      online ? _t('在线', 'Online') : _t('离线', 'Offline'),
      icon: online ? Icons.battery_full : Icons.battery_unknown,
    );
    if (!online && age != null) {
      yield ListTile(
        title: Text(_t('以下是上次收到的数据', 'Showing the last available readings')),
      );
    }
    if (age != null) yield _row(_t('电池协议', 'Battery protocol'), pack);
    yield _row(_t('电压', 'Voltage'), _number(data, 'voltage', 'V', 2));
    yield _row(_t('电流', 'Current'), _number(data, 'current', 'A', 2));
    yield _row('SOC', _number(data, 'soc', '%', 1));
    yield _row('SOH', _number(data, 'soh', '%', 1));
    for (final entry in {
      'warning': _t('BMS 告警', 'BMS warning'),
      'protection': _t('BMS 保护', 'BMS protection'),
    }.entries) {
      final bits = _integer(data[entry.key]);
      if (bits == null) continue;
      yield _row(
        entry.value,
        bits == 0
            ? _t('无', 'None')
            : '0x${bits.toRadixString(16).toUpperCase()}',
      );
    }
    final cells = data['cells'];
    final count = (_integer(data['count']) ?? 0).clamp(0, 32);
    if (cells is List && count > 0) {
      final pages = (count + 7) ~/ 8;
      yield Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(child: Text(_t('单体电压', 'Cell voltages'))),
            IconButton(
              onPressed: !_loading && _page > 0 ? () => _read(_page - 1) : null,
              tooltip: _t('上一组', 'Previous group'),
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${_page + 1}/$pages'),
            IconButton(
              onPressed: !_loading && _page + 1 < pages
                  ? () => _read(_page + 1)
                  : null,
              tooltip: _t('下一组', 'Next group'),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      );
      for (var index = 0; index < 8 && _page * 8 + index < count; index++) {
        final mv = index < cells.length ? _integer(cells[index]) : null;
        yield _row(
          _t('单体 ${_page * 8 + index + 1}', 'Cell ${_page * 8 + index + 1}'),
          mv == null ? '—' : '$mv mV',
        );
      }
    }
  }

  Iterable<Widget> _alarms(Map<String, dynamic> data) sync* {
    final valid = _integer(data['valid']) ?? 0;
    final fresh = _error == null ? _integer(data['fresh']) ?? 0 : 0;
    final keys = ['fault_low', 'fault_high', 'warn_low', 'warn_high'];
    var count = 0;
    for (final current in [true, false]) {
      for (var word = 0; word < keys.length; word++) {
        final mask = 1 << word;
        if (valid & mask == 0 || (fresh & mask != 0) != current) continue;
        final bits = _integer(data[keys[word]]) ?? 0;
        for (var bit = 0; bit < 16; bit++) {
          if (bits & (1 << bit) == 0) continue;
          count++;
          final fault = word < 2;
          final index = word % 2 * 16 + bit;
          final code =
              '${fault ? 'F' : 'W'}${(index + 1).toString().padLeft(2, '0')}';
          yield ListTile(
            leading: Icon(
              fault ? Icons.error_outline : Icons.warning_amber,
              color: current
                  ? (fault
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.tertiary)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(modbusPanelAlarmLabel(
              index: index,
              fault: fault,
              is3ku: data['model'] == '3KU',
              chinese: Localizations.localeOf(context).languageCode == 'zh',
            )),
            subtitle: Text(
                '$code · ${current ? _t('当前告警', 'Active') : _t('上次记录', 'Last reading')}'),
          );
        }
      }
    }
    if (fresh != 15 || count == 0) {
      yield ListTile(
        title: Text(fresh == 15
            ? _t('当前没有告警', 'No active alarms')
            : _t('告警数据不完整', 'Alarm data is incomplete')),
      );
    }
  }

  Iterable<Widget> _diagnostics(Map<String, dynamic> data) sync* {
    final parity = switch (data['parity']) {
      0 || 'N' => _t('无校验', 'None'),
      1 || 'E' => _t('偶校验', 'Even'),
      2 || 'O' => _t('奇校验', 'Odd'),
      _ => '—',
    };
    final age = _integer(data['age']);
    yield _row(
      _t('逆变器连接', 'Inverter link'),
      data['online'] == true && _error == null
          ? _t('在线', 'Online')
          : _t('离线', 'Offline'),
    );
    yield _row(_t('配置机型', 'Configured model'), '${data['model'] ?? '—'}');
    yield _row(_t('识别机型', 'Detected model'), '${data['detected'] ?? '—'}');
    yield _row(_t('从站地址', 'Slave address'), '${data['address'] ?? '—'}');
    yield _row(_t('波特率', 'Baud rate'), '${data['baud'] ?? '—'}');
    yield _row(_t('校验', 'Parity'), parity);
    yield _row(_t('成功轮询', 'Successful polls'), '${data['polls'] ?? '—'}');
    yield _row(_t('通信错误', 'Link errors'), '${data['errors'] ?? '—'}');
    if (age != null) {
      yield _row(
          _t('上次应答', 'Last reply'), '${(age / 1000).toStringAsFixed(1)} s');
    }
    final scanning = data['scanning'] == true;
    final scanPending = _scanRequestedUntil?.isAfter(DateTime.now()) == true;
    final found = _integer(data['found']);
    if (found != null && found > 0 && found <= 247) {
      yield ListTile(
        leading: const Icon(Icons.pin_outlined),
        title: Text(_t('搜索到地址 $found', 'Found address $found')),
        subtitle: Text(_t('填入通信设置', 'Use in connection settings')),
        trailing: const Icon(Icons.chevron_right),
        onTap: _loading || scanning || scanPending || _error != null
            ? null
            : () => _editConnection(data, suggestedAddress: found),
      );
    }
    yield ListTile(
      leading: const Icon(Icons.tune),
      title: Text(_t('修改通信配置', 'Edit connection configuration')),
      enabled: !_loading && !scanning && !scanPending && _error == null,
      onTap: _loading || scanning || scanPending || _error != null
          ? null
          : () => _editConnection(data),
    );
    yield ListTile(
      leading: Icon(scanning ? Icons.stop_circle_outlined : Icons.search),
      title: Text(scanning
          ? _t('停止搜索', 'Stop scanning')
          : scanPending
              ? _t('正在启动搜索', 'Starting scan')
              : _t('搜索逆变器', 'Scan for inverter')),
      onTap: _loading || _error != null || (scanPending && !scanning)
          ? null
          : () => _scan(data, !scanning),
    );
  }

  Future<void> _editConnection(Map<String, dynamic> data,
      {int? suggestedAddress}) async {
    final generation = _integer(data['context']);
    final address = _integer(data['address']);
    var baud = _integer(data['baud']);
    var parity = _integer(data['parity']);
    var profile = _integer(data['profile']);
    if (generation == null ||
        address == null ||
        !_bauds.contains(baud) ||
        parity == null ||
        parity < 0 ||
        parity > 2 ||
        profile == null ||
        !const [0, 5, 7, 1, 4].contains(profile)) return;
    var addressText = '${suggestedAddress ?? address}';
    final locked = data['locked'] == true;
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final nextAddress = int.tryParse(addressText);
          final addressValid =
              nextAddress != null && nextAddress >= 1 && nextAddress <= 247;
          return AlertDialog(
            title: Text(_t('逆变器通信设置', 'Inverter connection')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    initialValue: addressText,
                    decoration: InputDecoration(
                      labelText: _t('从站地址', 'Slave address'),
                      errorText: addressValid ? null : '1–247',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) =>
                        setDialogState(() => addressText = value),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: baud,
                    decoration:
                        InputDecoration(labelText: _t('波特率', 'Baud rate')),
                    items: [
                      for (final rate in _bauds)
                        DropdownMenuItem(value: rate, child: Text('$rate'))
                    ],
                    onChanged: (value) => setDialogState(() => baud = value),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: parity,
                    decoration: InputDecoration(labelText: _t('校验', 'Parity')),
                    items: [
                      DropdownMenuItem(
                          value: 0, child: Text(_t('无校验', 'None'))),
                      DropdownMenuItem(
                          value: 1, child: Text(_t('偶校验', 'Even'))),
                      DropdownMenuItem(value: 2, child: Text(_t('奇校验', 'Odd'))),
                    ],
                    onChanged: (value) => setDialogState(() => parity = value),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: profile,
                    decoration: InputDecoration(labelText: _t('机型', 'Model')),
                    items: [
                      DropdownMenuItem(
                          value: 0, child: Text(_t('自动识别', 'Auto detect'))),
                      const DropdownMenuItem(value: 5, child: Text('2KU')),
                      const DropdownMenuItem(value: 7, child: Text('3KU')),
                      const DropdownMenuItem(value: 1, child: Text('6KU')),
                      const DropdownMenuItem(value: 4, child: Text('12KU')),
                    ],
                    onChanged: locked
                        ? null
                        : (value) => setDialogState(() => profile = value),
                  ),
                  const SizedBox(height: 12),
                  Text(_t('请按逆变器的实际配置填写。保存后面板会重新连接逆变器。',
                      'Use the inverter settings. Saving reconnects the panel to the inverter.')),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel)),
              FilledButton(
                onPressed: !addressValid
                    ? null
                    : () => Navigator.pop(context, {
                          'param_id': 'panel_comm',
                          'value': 1,
                          'context': generation,
                          'address': nextAddress,
                          'baud': baud,
                          'parity': parity,
                          'profile': profile,
                        }),
                child: Text(_t('保存并重新连接', 'Save and reconnect')),
              ),
            ],
          );
        },
      ),
    );
    if (mounted && draft != null) await _sendDiagnostic(draft);
  }

  Future<void> _scan(Map<String, dynamic> data, bool start) async {
    final generation = _integer(data['context']);
    if (generation == null) return;
    await _sendDiagnostic({
      'param_id': 'panel_scan',
      'value': start ? 1 : 0,
      'context': generation,
    }, scan: start);
  }

  Future<void> _sendDiagnostic(Map<String, dynamic> request,
      {bool scan = false}) async {
    if (_loading) return;
    _refreshTimer?.cancel();
    setState(() => _loading = true);
    try {
      final result = await widget.sendCommand('set_param', request);
      if (result['observed'] != true && result['submitted'] != true) {
        throw const BleCommandException(
            'RESULT_UNAVAILABLE', 'Missing diagnostic receipt');
      }
      if (scan)
        _scanRequestedUntil = DateTime.now().add(const Duration(seconds: 3));
      if (!mounted) return;
      setState(() => _loading = false);
      await _read();
    } on Object catch (error) {
      if (mounted)
        setState(() {
          _error = error;
          _loading = false;
        });
    }
  }

  Iterable<Widget> _metrics(Map<String, dynamic> data) sync* {
    final groups = [
      _t('市电与负载', 'Grid and load'),
      _t('电池与充电', 'Battery and charging'),
      _t('光伏输入', 'Solar input'),
      _t('温度监测', 'Temperatures'),
      _t('发电机', 'Generator'),
      _t('电量与输出', 'Energy and output'),
      _t('当前运行设置', 'Operating settings'),
    ];
    yield Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: _t('参数分类', 'Data category'),
          border: const OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _page,
            isExpanded: true,
            isDense: true,
            items: [
              for (var i = 0; i < groups.length; i++)
                DropdownMenuItem(value: i, child: Text(groups[i])),
            ],
            onChanged: _loading
                ? null
                : (page) {
                    if (page != null && page != _page) unawaited(_read(page));
                  },
          ),
        ),
      ),
    );
    final rows = data['rows'];
    if (rows is! List) return;
    yield Padding(
      padding: const EdgeInsets.all(16),
      child: ModbusPanelMetrics(
        values: [
          for (final row in rows)
            if (row is List && row.length == 2)
              (
                '${row[0]}',
                _error != null && !'${row[1]}'.endsWith('*')
                    ? '${row[1]}*'
                    : '${row[1]}'
              ),
        ],
        staleLabel: _t('上次读数', 'Last reading'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final title = switch (widget.kind) {
      ModbusPanelStatusKind.battery => _t('电池数据', 'Battery data'),
      ModbusPanelStatusKind.alarms => _t('故障告警', 'Faults and warnings'),
      ModbusPanelStatusKind.diagnostics => _t('通信诊断', 'Link diagnostics'),
      ModbusPanelStatusKind.metrics => _t('运行参数', 'Operating data'),
    };
    final rows = data == null
        ? const <Widget>[]
        : switch (widget.kind) {
            ModbusPanelStatusKind.battery => _battery(data),
            ModbusPanelStatusKind.alarms => _alarms(data),
            ModbusPanelStatusKind.diagnostics => _diagnostics(data),
            ModbusPanelStatusKind.metrics => _metrics(data),
          };
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _read(),
            tooltip: _t('刷新', 'Refresh'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (_loading && data == null) const LinearProgressIndicator(),
          if (_error != null)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(_errorMessage(context, _error!)),
            ),
          ...rows,
        ],
      ),
    );
  }
}
