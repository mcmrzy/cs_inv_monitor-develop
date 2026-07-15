class TelemetryQualityFlag {
  const TelemetryQualityFlag(this.mask, this.key, this.label);

  final int mask;
  final String key;
  final String label;
}

class DecodedTelemetryQuality {
  const DecodedTelemetryQuality({
    required this.value,
    required this.flags,
    required this.unknownMask,
  });

  final int? value;
  final List<TelemetryQualityFlag> flags;
  final int unknownMask;

  bool? get isNormal => value == null ? null : value == 0;
}

// This is the server/storage contract, not a presentation-only interpretation.
// OUT_OF_ORDER is also used as the compatibility marker for backfilled samples.
const telemetryQualityFlags = <TelemetryQualityFlag>[
  TelemetryQualityFlag(0x01, 'missing', '缺失值 (missing)'),
  TelemetryQualityFlag(0x02, 'out_of_range', '数值越界 (out_of_range)'),
  TelemetryQualityFlag(0x04, 'time_drift', '设备时钟异常 (time_drift)'),
  TelemetryQualityFlag(
      0x08, 'out_of_order/backfill', '乱序/回填 (out_of_order/backfill)'),
  TelemetryQualityFlag(0x10, 'counter_reset', '累计量复位 (counter_reset)'),
  TelemetryQualityFlag(0x20, 'comm_fault', '通信异常 (comm_fault)'),
];

int? parseTelemetryQualityFlags(Object? input) {
  if (input is int && input >= 0) return input;
  if (input is num && input >= 0 && input == input.roundToDouble()) {
    return input.toInt();
  }
  if (input is! String || input.trim().isEmpty) return null;
  final text = input.trim();
  if (RegExp(r'^0x[0-9a-f]+$', caseSensitive: false).hasMatch(text)) {
    return int.tryParse(text.substring(2), radix: 16);
  }
  if (!RegExp(r'^\d+$').hasMatch(text)) return null;
  return int.tryParse(text);
}

DecodedTelemetryQuality decodeTelemetryQuality(Object? input) {
  final value = parseTelemetryQualityFlags(input);
  if (value == null) {
    return const DecodedTelemetryQuality(
        value: null, flags: [], unknownMask: 0);
  }
  final knownMask =
      telemetryQualityFlags.fold<int>(0, (mask, flag) => mask | flag.mask);
  return DecodedTelemetryQuality(
    value: value,
    flags: telemetryQualityFlags
        .where((flag) => value & flag.mask != 0)
        .toList(growable: false),
    unknownMask: value & ~knownMask,
  );
}
