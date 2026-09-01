import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/domain/entities/device_param.dart';

typedef ConfirmDeviceParamWrite = FutureOr<void> Function(num value);

/// Numeric parameter editor with route-scoped input and submission state.
class DeviceParamWriteDialog extends StatefulWidget {
  const DeviceParamWriteDialog({
    super.key,
    required this.param,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onConfirm,
  });

  final DeviceParam param;
  final String cancelLabel;
  final String confirmLabel;
  final ConfirmDeviceParamWrite onConfirm;

  @override
  State<DeviceParamWriteDialog> createState() =>
      _DeviceParamWriteDialogState();
}

class _DeviceParamWriteDialogState extends State<DeviceParamWriteDialog> {
  late final TextEditingController _controller;
  late final double _minValue;
  late final double _maxValue;
  late double _sliderValue;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final param = widget.param;
    _controller = TextEditingController(text: '${param.value}');
    _minValue =
        param.minValue is num ? (param.minValue as num).toDouble() : 0.0;
    _maxValue =
        param.maxValue is num ? (param.maxValue as num).toDouble() : 100.0;
    _sliderValue =
        (param.value is num ? (param.value as num).toDouble() : _minValue)
            .clamp(_minValue, _maxValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_isSubmitting) return;
    Navigator.pop(context);
  }

  Future<void> _confirm() async {
    if (_isSubmitting) return;
    final value = num.tryParse(_controller.text);
    if (value == null) return;

    setState(() => _isSubmitting = true);
    try {
      await Future<void>.sync(() => widget.onConfirm(value));
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final param = widget.param;
    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        title: Text(param.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (param.description != null)
              Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Text(
                  param.description!,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColor.textSecondary(context),
                  ),
                ),
              ),
            if (_maxValue - _minValue <= 200 &&
                (_maxValue - _minValue) > 1)
              Row(
                children: [
                  Text(
                    '${_minValue.toInt()}',
                    style: TextStyle(fontSize: 12.sp),
                  ),
                  Expanded(
                    child: Slider(
                      value: _sliderValue.clamp(_minValue, _maxValue),
                      min: _minValue,
                      max: _maxValue,
                      divisions:
                          ((_maxValue - _minValue) ~/ 1).clamp(1, 200),
                      label: _sliderValue.toStringAsFixed(0),
                      onChanged: (value) {
                        if (_isSubmitting) return;
                        setState(() => _sliderValue = value);
                        _controller.text = value.toStringAsFixed(0);
                      },
                    ),
                  ),
                  Text(
                    '${_maxValue.toInt()}',
                    style: TextStyle(fontSize: 12.sp),
                  ),
                ],
              ),
            SizedBox(height: 8.h),
            TextField(
              controller: _controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: '$_minValue ~ $_maxValue',
                suffixText: param.unit,
              ),
              onChanged: (value) {
                if (_isSubmitting) return;
                final parsed = double.tryParse(value);
                if (parsed != null) {
                  setState(
                    () => _sliderValue = parsed.clamp(_minValue, _maxValue),
                  );
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _cancel,
            child: Text(widget.cancelLabel),
          ),
          FilledButton(
            onPressed: _confirm,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}
