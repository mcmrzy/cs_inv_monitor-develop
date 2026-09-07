import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';

typedef SendContactCode = Future<bool> Function(String value);
typedef ConfirmContactChange = Future<bool> Function(
  String value,
  String code,
);

/// 修改手机号/邮箱的验证码弹窗。
///
/// 弹窗自行管理输入框和倒计时生命周期；调用方只负责验证码接口、
/// 联系方式变更接口以及成功后的页面状态同步。
class ContactChangeDialog extends StatefulWidget {
  const ContactChangeDialog({
    required this.icon,
    required this.title,
    required this.description,
    required this.valueLabel,
    required this.valueHint,
    required this.valueKeyboardType,
    required this.valuePrefixIcon,
    required this.codeLabel,
    required this.codeHint,
    required this.sendCodeLabel,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onSendCode,
    required this.onConfirm,
    required this.onConfirmed,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final String valueLabel;
  final String valueHint;
  final TextInputType valueKeyboardType;
  final IconData valuePrefixIcon;
  final String codeLabel;
  final String codeHint;
  final String sendCodeLabel;
  final String cancelLabel;
  final String confirmLabel;
  final SendContactCode onSendCode;
  final ConfirmContactChange onConfirm;
  final ValueChanged<String> onConfirmed;

  @override
  State<ContactChangeDialog> createState() => _ContactChangeDialogState();
}

class _ContactChangeDialogState extends State<ContactChangeDialog> {
  final _valueController = TextEditingController();
  final _codeController = TextEditingController();
  Timer? _countdownTimer;
  int _countdown = 0;
  bool _isSending = false;
  bool _isConfirming = false;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _valueController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_isSending || _isConfirming || _countdown > 0) return;
    setState(() => _isSending = true);
    try {
      final sent = await widget.onSendCode(_valueController.text);
      if (!mounted || !sent) return;

      _countdownTimer?.cancel();
      setState(() => _countdown = 60);
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_countdown > 0) {
          setState(() => _countdown--);
        } else {
          timer.cancel();
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _confirm() async {
    if (_isSending || _isConfirming) return;
    final value = _valueController.text;
    final onConfirmed = widget.onConfirmed;
    setState(() => _isConfirming = true);
    try {
      final confirmed = await widget.onConfirm(value, _codeController.text);
      if (!confirmed) return;

      onConfirmed(value);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) {
        setState(() => _isConfirming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sendDisabled = _isSending || _isConfirming || _countdown > 0;
    final confirmDisabled = _isSending || _isConfirming;
    return PopScope(
      canPop: !_isConfirming,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Container(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64.w,
                height: 64.w,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  size: 32.sp,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                widget.description,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColor.textSecondary(context),
                ),
              ),
              SizedBox(height: 24.h),
              TextField(
                controller: _valueController,
                enabled: !_isConfirming,
                keyboardType: widget.valueKeyboardType,
                decoration: InputDecoration(
                  labelText: widget.valueLabel,
                  hintText: widget.valueHint,
                  prefixIcon: Icon(widget.valuePrefixIcon, size: 20.sp),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 14.h,
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      enabled: !_isConfirming,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: widget.codeLabel,
                        hintText: widget.codeHint,
                        prefixIcon: Icon(Icons.lock_outline, size: 20.sp),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 14.h,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  SizedBox(
                    height: 52.h,
                    child: ElevatedButton(
                      onPressed: sendDisabled ? null : _sendCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: sendDisabled
                            ? AppColors.offline
                            : AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                      ),
                      child: Text(
                        _countdown > 0
                            ? '${_countdown}s'
                            : widget.sendCodeLabel,
                        style: TextStyle(fontSize: 13.sp),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isConfirming ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text(widget.cancelLabel),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: confirmDisabled ? null : _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text(widget.confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
