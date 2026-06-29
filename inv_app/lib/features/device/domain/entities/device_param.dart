class ParamOption {
  final dynamic value;
  final String label;

  const ParamOption({required this.value, required this.label});
}

class DeviceParam {
  final String key;
  final String label;
  final dynamic value;
  final dynamic minValue;
  final dynamic maxValue;
  final String unit;
  final String paramType;
  final List<ParamOption> options;
  final bool isDangerous;
  final String? description;

  const DeviceParam({
    required this.key,
    required this.label,
    required this.value,
    this.minValue,
    this.maxValue,
    this.unit = '',
    this.paramType = 'number',
    this.options = const [],
    this.isDangerous = false,
    this.description,
  });

  DeviceParam copyWith({dynamic value}) {
    return DeviceParam(
      key: key,
      label: label,
      value: value ?? this.value,
      minValue: minValue,
      maxValue: maxValue,
      unit: unit,
      paramType: paramType,
      options: options,
      isDangerous: isDangerous,
      description: description,
    );
  }

  String get groupKey {
    final parts = key.split('_');
    return parts.length > 1 ? parts.first : 'other';
  }
}
