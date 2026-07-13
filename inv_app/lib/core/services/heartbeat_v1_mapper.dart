import 'package:inv_app/core/entities/inverter_data.dart';

class HeartbeatV1Mapper {
  static InverterRealtime parse(String deviceSN, Map<String, dynamic> payload) {
    if ((payload['v'] as num?)?.toInt() != 1) {
      throw const FormatException('unsupported heartbeat version');
    }
    final ac = _group(payload, 'ac', 8);
    final bat = _group(payload, 'bat', 21);
    final pv = _group(payload, 'pv', 12);
    final sys = _group(payload, 'sys', 10);
    final eng = _group(payload, 'eng', 8);
    final cells = payload['cells'];
    if (cells is! List ||
        cells.length != 2 ||
        cells[0] is! List ||
        cells[1] is! List) {
      throw const FormatException(
          'cells must contain voltage and temperature arrays');
    }
    final voltages = _numberList(cells[0] as List);
    final temperatures = _numberList(cells[1] as List);
    if (voltages.length != temperatures.length) {
      throw const FormatException('cell array lengths differ');
    }

    final timestamp = (payload['t'] as num?)?.toInt();
    final updatedAt = timestamp == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
    final workState = _integer(sys[0]);
    final batteryState = _integer(bat[13]);
    final mpptState = _integer(pv[11]);

    return InverterRealtime(
      deviceSN: deviceSN,
      ac: ACData(
        voltage: _number(ac[0]),
        current: _number(ac[1]),
        power: _number(ac[2]),
        apparentPower: _number(ac[3]),
        frequency: _number(ac[4]),
        pf: _number(ac[5]),
        loadPercent: _number(ac[6]),
        voltageThd: _number(ac[7]),
      ),
      battery: BatteryData(
        soc: _number(bat[0]),
        soh: _number(bat[1]),
        voltage: _number(bat[2]),
        current: _number(bat[3]),
        power: _number(bat[4]),
        capacityRemain: _number(bat[5]),
        capacityTotal: _number(bat[6]),
        cycleCount: _integer(bat[7]),
        tempMax: _number(bat[8]),
        tempMin: _number(bat[9]),
        cellVoltageMax: _number(bat[10]),
        cellVoltageMin: _number(bat[11]),
        cellVoltageDiff: _number(bat[12]),
        chargeState: _batteryState(batteryState),
        protectStatus: _integer(bat[14]),
        bmsFaultCode: _integer(bat[15]),
        maxChargeCurrent: _number(bat[16]),
        maxDischargeCurrent: _number(bat[17]),
        chargeVoltageRef: _number(bat[18]),
        dischargeCutoffVoltage: _number(bat[19]),
        temperature: _number(bat[20]),
      ),
      pv: PVData(
        pvVoltage: _number(pv[0]),
        pvCurrent: _number(pv[1]),
        pv1Power: _number(pv[2]),
        pv1VoltageMax: _number(pv[3]),
        pv1PowerMax: _number(pv[4]),
        pv2Voltage: _number(pv[5]),
        pv2Current: _number(pv[6]),
        pv2Power: _number(pv[7]),
        pv2VoltageMax: _number(pv[8]),
        pv2PowerMax: _number(pv[9]),
        pvPower: _number(pv[10]),
        mpptState: _mpptState(mpptState),
      ),
      sysStatus: SystemStatus(
        state: _workState(workState),
        faultCode: _integer(sys[1]),
        alarmCode: _integer(sys[2]),
        tempInv: _number(sys[3]),
        tempMos: _number(sys[4]),
        ambientTemperature: _number(sys[5]),
        dcBusVoltage: _number(sys[6]),
        runtimeHours: _integer(sys[7]),
        fanSpeedPercent: _number(sys[8]),
        efficiency: _number(sys[9]),
      ),
      energy: EnergyData(
        dailyPV: _number(eng[0]),
        totalPV: _number(eng[1]),
        dailyCharge: _number(eng[2]),
        totalCharge: _number(eng[3]),
        dailyDischarge: _number(eng[4]),
        totalDischarge: _number(eng[5]),
        dailyLoad: _number(eng[6]),
        totalLoad: _number(eng[7]),
        runtimeHours: _integer(sys[7]),
      ),
      cells: CellsData(
          cellCount: voltages.length, voltages: voltages, temps: temperatures),
      onlineStatus: const OnlineStatus(online: true),
      loadPower: _number(ac[2]),
      updatedAt: updatedAt,
    );
  }

  static List<dynamic> _group(
      Map<String, dynamic> payload, String key, int length) {
    final value = payload[key];
    if (value is! List || value.length != length) {
      throw FormatException('$key must contain $length values');
    }
    return value;
  }

  static double _number(dynamic value) {
    if (value == null) return 0;
    if (value is! num)
      throw const FormatException('heartbeat value must be numeric or null');
    return value.toDouble();
  }

  static int _integer(dynamic value) => _number(value).toInt();

  static List<double> _numberList(List<dynamic> values) =>
      values.map(_number).toList(growable: false);

  static String _workState(int value) => const [
        'standby',
        'inverting',
        'bypass',
        'shutdown',
        'fault'
      ].elementAt(value >= 0 && value <= 4 ? value : 0);

  static String _batteryState(int value) => const [
        'idle',
        'charging',
        'discharging',
        'fault'
      ].elementAt(value >= 0 && value <= 3 ? value : 0);

  static String _mpptState(int value) => const ['tracking', 'standby', 'fault']
      .elementAt(value >= 0 && value <= 2 ? value : 0);
}
