import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 密码修改弹窗
class ChangePasswordDialog extends StatefulWidget {
  /// 是否强制设置为设置密码模式（外部传入使用）
  final bool isSetPassword;
  
  const ChangePasswordDialog({super.key, this.isSetPassword = false});
  
  static Future<void> show(BuildContext context, {bool isSetPassword = false}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangePasswordDialog(isSetPassword: isSetPassword),
    );
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  
  late bool _setPasswordMode;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 如果是外部传入的 isSetPassword=true，则强制使用设置密码模式
    // 否则检查用户是否有密码
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    _setPasswordMode = widget.isSetPassword || (user != null && !user.hasPassword);
    _newPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (_formKey.currentState!.validate() && !_isLoading) {
      setState(() => _isLoading = true);
      
      try {
        context.read<AuthBloc>().add(
              AuthChangePasswordRequested(
                oldPassword: _setPasswordMode ? '' : _oldPasswordController.text,
                newPassword: _newPasswordController.text,
              ),
            );
        
        await Future.delayed(const Duration(seconds: 2));
        
        if (!mounted) return;
        Navigator.pop(context);
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (previous, current) => !current.isProfileUpdateTerminal,
      listener: (context, state) {
        if (state is AuthPasswordResetSuccess) {
          if (mounted) {
            AppToast.show(context, l10n.passwordChanged, type: ToastType.success);
            Navigator.pop(context);
          }
        } else if (state is AuthError) {
          if (mounted) {
            AppToast.show(context, l10n.translateError(state.message), type: ToastType.error);
          }
        }
      },
      builder: (context, state) {
        return Dialog(
          child: Container(
            padding: EdgeInsets.all(24.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部圆形图标
                Container(
                  width: 64.w,
                  height: 64.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _setPasswordMode
                        ? Icons.lock_reset_rounded
                        : Icons.lock_outline,
                    size: 32.sp,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  _setPasswordMode ? l10n.setPassword : l10n.changePassword,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 24.h),
                // 表单
                Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_setPasswordMode) ...[
                        TextFormField(
                          controller: _oldPasswordController,
                          obscureText: _obscureOld,
                          decoration: InputDecoration(
                            labelText: l10n.currentPassword,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureOld ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscureOld = !_obscureOld),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? l10n.pleaseInputCurrentPassword
                              : null,
                        ),
                        SizedBox(height: 14.h),
                      ],
                      TextFormField(
                        controller: _newPasswordController,
                        obscureText: _obscureNew,
                        decoration: InputDecoration(
                          labelText: l10n.newPasswordLabel,
                          prefixIcon: const Icon(Icons.password_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureNew = !_obscureNew),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return l10n.pleaseInputNewPassword;
                          if (value.length < 6 || value.length > 20) return l10n.passwordLengthHint;
                          return null;
                        },
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: 8.h),
                        child: _buildStrengthIndicator(l10n, _newPasswordController.text),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: 6.h),
                        child: Row(
                          children: [
                            Icon(Icons.lightbulb_outline, size: 12.sp, color: AppColor.textHint(context)),
                            SizedBox(width: 4.w),
                            Expanded(child: Text(l10n.passwordRuleHint, style: TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)))),
                          ],
                        ),
                      ),
                      SizedBox(height: 14.h),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        decoration: InputDecoration(
                          labelText: l10n.confirmPasswordLabel,
                          prefixIcon: const Icon(Icons.lock_reset_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return l10n.pleaseConfirmPassword;
                          if (value != _newPasswordController.text) return l10n.passwordNotConsistent;
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24.h),
                // 按钮行：取消 + 确认（与编辑页弹窗风格一致）
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading || state is AuthLoading ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: state is AuthLoading || _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        child: _isLoading || state is AuthLoading
                            ? SizedBox(width: 18.w, height: 18.w, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(_setPasswordMode ? l10n.setPassword : l10n.confirmChange),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStrengthIndicator(AppLocalizations l10n, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    
    var score = 0;
    if (value.length >= 8) {
      score += 2;
    } else if (value.length >= 6) {
      score += 1;
    }
    if (RegExp(r'[A-Z]').hasMatch(value)) score += 1;
    if (RegExp(r'[a-z]').hasMatch(value)) score += 1;
    if (RegExp(r'[0-9]').hasMatch(value)) score += 1;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score += 1;
    
    final strength = score <= 2 
        ? _PasswordStrength.weak 
        : score <= 4 
            ? _PasswordStrength.medium 
            : _PasswordStrength.strong;
    
    final (label, color) = switch (strength) {
      _PasswordStrength.weak => (l10n.passwordStrengthWeak, AppColors.error),
      _PasswordStrength.medium => (l10n.passwordStrengthMedium, AppColors.warning),
      _PasswordStrength.strong => (l10n.passwordStrengthStrong, AppColors.success),
    };
    
    return Padding(
      padding: EdgeInsets.only(left: 4.w),
      child: Text(
        label,
        style: TextStyle(fontSize: 12.sp, color: color),
      ),
    );
  }
}

enum _PasswordStrength { weak, medium, strong }
