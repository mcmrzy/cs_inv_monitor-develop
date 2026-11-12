import 'package:inv_app/core/services/ble/ble_device_manager.dart';

class ModbusPanelInfo {
  const ModbusPanelInfo({
    required this.model,
    required this.count,
    required this.online,
    required this.context,
    required this.confirmed,
    required this.canPowerOn,
    required this.canPowerOff,
  });

  factory ModbusPanelInfo.fromJson(Map<String, dynamic> data) {
    final count = data['count'];
    final context = data['context'];
    if (count is! int ||
        count < 0 ||
        count > 256 ||
        context is! int ||
        context < 0) {
      throw const FormatException('Invalid inverter setting catalogue');
    }
    return ModbusPanelInfo(
      model: data['model']?.toString() ?? '',
      count: count,
      online: data['online'] == true,
      context: context,
      confirmed: data['confirmed'] == true,
      canPowerOn: data['power_on'] == true,
      canPowerOff: data['power_off'] == true,
    );
  }

  final String model;
  final int count;
  final bool online;
  final int context;
  final bool confirmed;
  final bool canPowerOn;
  final bool canPowerOff;
}

class ModbusPanelSetting {
  const ModbusPanelSetting({
    required this.index,
    required this.id,
    required this.label,
    required this.group,
    required this.access,
    required this.value,
    required this.text,
    required this.reason,
    required this.reading,
    required this.context,
    this.suggestion,
  });

  factory ModbusPanelSetting.fromJson(int index, Map<String, dynamic> data) {
    final id = data['id'];
    final access = data['access'];
    final value = data['value'];
    final context = data['context'];
    final suggestion = data['suggestion'];
    final suggestedText = data['suggested_text'];
    if (id is! String ||
        !_registerId.hasMatch(id) ||
        access is! int ||
        access < 0 ||
        context is! int ||
        context < 0 ||
        (value != null && (value is! int || value < 0 || value > 65535))) {
      throw const FormatException('Invalid inverter setting');
    }
    return ModbusPanelSetting(
      index: index,
      id: id,
      label: data['label']?.toString() ?? id,
      group: data['group']?.toString() ?? '',
      access: access,
      value: value as int?,
      text: data['text']?.toString() ?? '—',
      reason: data['reason']?.toString() ?? '',
      reading: data['reading'] == true,
      context: context,
      suggestion: suggestion is int &&
              suggestion > 0 &&
              suggestion < 65535 &&
              suggestedText is String
          ? ModbusPanelValue(suggestion, suggestedText, context)
          : null,
    );
  }

  static final _registerId = RegExp(r'^panel_[0-9a-f]{4}$');

  final int index;
  final String id;
  final String label;
  final String group;
  final int access;
  final int? value;
  final String text;
  final String reason;
  final bool reading;
  final int context;
  final ModbusPanelValue? suggestion;
  bool get editable => access == 0;
}

class ModbusPanelValue {
  const ModbusPanelValue(this.raw, this.text, this.context);

  factory ModbusPanelValue.fromJson(Map<String, dynamic> data) {
    final raw = data['value'];
    final context = data['context'];
    if (raw is! int ||
        raw < 0 ||
        raw > 65535 ||
        context is! int ||
        context < 0) {
      throw const FormatException('Invalid inverter setting value');
    }
    return ModbusPanelValue(
      raw,
      data['text']?.toString() ?? raw.toString(),
      context,
    );
  }

  final int raw;
  final String text;
  final int context;
}

enum ModbusPanelWriteOutcome { applied, submitted }

class ModbusPanelBle {
  ModbusPanelBle(this.session, {this.english = false});

  final BleDeviceSession session;
  final bool english;

  Future<Map<String, dynamic>> command(
    String action,
    Map<String, dynamic> params,
  ) {
    if (!session.supportsPanelApi || session.state != BleDeviceState.ready) {
      return Future.error(
        const BleCommandException('NOT_READY', 'Panel session is unavailable'),
      );
    }
    return session.sendCommand(action, {
      ...params,
      if (english && action.startsWith('panel_')) 'en': true,
    });
  }

  Future<ModbusPanelInfo> info() async =>
      ModbusPanelInfo.fromJson(await command('panel_info', const {}));

  Future<ModbusPanelSetting> setting(int index, {bool refresh = false}) async =>
      ModbusPanelSetting.fromJson(
        index,
        await command('panel_setting', {
          'index': index,
          if (refresh) 'refresh': true,
        }),
      );

  Future<ModbusPanelValue> step(
    int index,
    int? value,
    int direction,
  ) async =>
      ModbusPanelValue.fromJson(await command('panel_step', {
        'index': index,
        'value': value,
        'direction': direction,
      }));

  Future<ModbusPanelWriteOutcome> write(
    String id,
    int value,
    int context, {
    bool bmsSuggestion = false,
  }) async {
    final receipt = await command('set_param', {
      'param_id': id,
      'value': value,
      'context': context,
      if (bmsSuggestion) 'bms_suggestion': true,
    });
    if (receipt['submitted'] == true && receipt['observed'] == false) {
      return ModbusPanelWriteOutcome.submitted;
    }
    if (receipt['observed'] == true && receipt['value'] == value) {
      return ModbusPanelWriteOutcome.applied;
    }
    throw const BleCommandException(
      'RESULT_UNAVAILABLE',
      'The inverter result does not include the requested value',
    );
  }
}
