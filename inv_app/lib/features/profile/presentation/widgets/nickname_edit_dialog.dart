import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';

typedef ConfirmNicknameEdit = Future<void> Function(String nickname);

/// 昵称编辑弹窗，负责输入与提交状态的完整生命周期。
class NicknameEditDialog extends StatefulWidget {
  const NicknameEditDialog({
    required this.initialValue,
    required this.title,
    required this.label,
    required this.hint,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onConfirm,
    super.key,
  });

  final String initialValue;
  final String title;
  final String label;
  final String hint;
  final String cancelLabel;
  final String confirmLabel;
  final ConfirmNicknameEdit onConfirm;

  @override
  State<NicknameEditDialog> createState() => _NicknameEditDialogState();
}

class _NicknameEditDialogState extends State<NicknameEditDialog> {
  late final TextEditingController _controller;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_isSubmitting) return;

    final nickname = _controller.text;
    final onConfirm = widget.onConfirm;
    setState(() => _isSubmitting = true);
    try {
      await onConfirm(nickname);
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
    return PopScope(
      canPop: !_isSubmitting,
      child: Dialog(
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
                  Icons.person_outline,
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
              SizedBox(height: 24.h),
              TextField(
                controller: _controller,
                enabled: !_isSubmitting,
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: widget.hint,
                  prefixIcon: Icon(Icons.person, size: 20.sp),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 14.h,
                  ),
                ),
              ),
              SizedBox(height: 24.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
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
                      onPressed: _isSubmitting ? null : _confirm,
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
