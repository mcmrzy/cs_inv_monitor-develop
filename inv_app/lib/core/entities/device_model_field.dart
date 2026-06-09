class DeviceModelField {
  final int id;
  final int modelId;
  final String fieldKey;
  final String fieldName;
  final String fieldType;
  final String unit;
  final int sort;
  final bool isShow;
  final bool isControl;
  final String? parseRule;

  const DeviceModelField({
    required this.id,
    required this.modelId,
    required this.fieldKey,
    required this.fieldName,
    required this.fieldType,
    this.unit = '',
    this.sort = 0,
    this.isShow = true,
    this.isControl = false,
    this.parseRule,
  });

  factory DeviceModelField.fromJson(Map<String, dynamic> json) {
    return DeviceModelField(
      id: json['id'] as int? ?? 0,
      modelId: json['model_id'] as int? ?? 0,
      fieldKey: json['field_key'] as String? ?? '',
      fieldName: json['field_name'] as String? ?? '',
      fieldType: json['field_type'] as String? ?? 'float',
      unit: json['unit'] as String? ?? '',
      sort: json['sort'] as int? ?? 0,
      isShow: json['is_show'] as bool? ?? true,
      isControl: json['is_control'] as bool? ?? false,
      parseRule: json['parse_rule'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'model_id': modelId,
    'field_key': fieldKey,
    'field_name': fieldName,
    'field_type': fieldType,
    'unit': unit,
    'sort': sort,
    'is_show': isShow,
    'is_control': isControl,
    'parse_rule': parseRule,
  };
}
