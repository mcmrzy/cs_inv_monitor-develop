import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/domain/entities/device_param.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DeviceParamTextControl extends StatefulWidget {
  const DeviceParamTextControl({
    super.key,
    required this.param,
    required this.value,
    required this.onChanged,
  });

  final DeviceParam param;
  final dynamic value;
  final void Function(String key, String value) onChanged;

  @override
  State<DeviceParamTextControl> createState() =>
      _DeviceParamTextControlState();
}

class _DeviceParamTextControlState extends State<DeviceParamTextControl> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _valueText(widget.value));
  }

  @override
  void didUpdateWidget(covariant DeviceParamTextControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = _valueText(widget.value);
    if (oldWidget.value != widget.value && _controller.text != nextText) {
      _controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText:
            '${AppLocalizations.of(context)!.inputParam}${widget.param.label}',
        hintStyle: TextStyle(
          fontSize: 13.sp,
          color: AppColor.textHint(context),
        ),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        filled: true,
        fillColor: AppColor.surfaceHover(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: BorderSide(
            color: AppColor.primary(context).withValues(alpha: 0.5),
          ),
        ),
      ),
      style: TextStyle(fontSize: 14.sp, color: AppColor.textPrimary(context)),
      onChanged: (value) => widget.onChanged(widget.param.key, value),
    );
  }

  String _valueText(dynamic value) => '${value ?? ''}';
}
