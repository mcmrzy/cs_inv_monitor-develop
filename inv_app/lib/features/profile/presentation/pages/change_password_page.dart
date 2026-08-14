import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 密码强度等级：弱 / 中 / 强
enum _PasswordStrength { weak, medium, strong }

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  /// 无密码账号（手机号一键登录注册）为 true 时隐藏原密码输入，直接设置新密码
  late bool _setPasswordMode;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    _setPasswordMode = user != null && !user.hasPassword;
    // 新密码输入变化时实时刷新密码强度提示
    _newPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(
            AuthChangePasswordRequested(
              oldPassword: _setPasswordMode ? '' : _oldPasswordController.text,
              newPassword: _newPasswordController.text,
            ),
          );
    }
  }

  /// 密码强度评分：长度 + 字符种类组合
  _PasswordStrength _passwordStrength(String value) {
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
    if (score <= 2) return _PasswordStrength.weak;
    if (score <= 4) return _PasswordStrength.medium;
    return _PasswordStrength.strong;
  }

  Widget _buildStrengthIndicator(AppLocalizations l10n, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    final strength = _passwordStrength(value);
    final (label, color) = switch (strength) {
      _PasswordStrength.weak => (l10n.passwordStrengthWeak, AppColors.error),
      _PasswordStrength.medium =>
        (l10n.passwordStrengthMedium, AppColors.warning),
      _PasswordStrength.strong => (l10n.passwordStrengthStrong, AppColors.success),
    };
    final activeSegments = strength.index + 1;
    return Row(
      children: [
        // 三段式强度条
        Expanded(
          child: Row(
            children: List.generate(3, (i) {
              return Expanded(
                child: Container(
                  height: 4.h,
                  margin: EdgeInsets.only(right: i < 2 ? 6.w : 0),
                  decoration: BoxDecoration(
                    color: i < activeSegments ? color : AppColor.border(context),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              );
            }),
          ),
        ),
        SizedBox(width: 10.w),
        Text(
          '${l10n.passwordStrengthLabel}：$label',
          style: TextStyle(
            fontSize: 12.sp,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(_setPasswordMode ? l10n.setPassword : l10n.changePassword),
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthPasswordResetSuccess) {
            AppToast.show(
              context,
              l10n.passwordChanged,
              type: ToastType.success,
            );
            context.pop();
          } else if (state is AuthError) {
            AppToast.show(
              context,
              l10n.translateError(state.message),
              type: ToastType.error,
            );
          }
        },
        builder: (context, state) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 32.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 渐变头部卡片
                Container(
                  padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 24.h),
                  decoration: AppColor.heroCard(context),
                  child: Column(
                    children: [
                      Container(
                        width: 56.w,
                        height: 56.w,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.lock_reset,
                          size: 28.w,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        _setPasswordMode
                            ? l10n.setPassword
                            : l10n.changePassword,
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (_setPasswordMode) ...[
                        SizedBox(height: 6.h),
                        Text(
                          l10n.setPasswordDesc,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.white.withValues(alpha: 0.9),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 16.h),
                // 圆角表单卡片
                Container(
                  padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 12.h),
                  decoration: AppColor.cardElevated(context),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (!_setPasswordMode) ...[
                          TextFormField(
                            controller: _oldPasswordController,
                            obscureText: _obscureOld,
                            decoration: InputDecoration(
                              labelText: l10n.currentPassword,
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureOld
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () => setState(
                                  () => _obscureOld = !_obscureOld,
                                ),
                              ),
                            ),
                            validator: (value) =>
                                value == null || value.isEmpty
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
                              icon: Icon(
                                _obscureNew
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () =>
                                  setState(() => _obscureNew = !_obscureNew),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n.pleaseInputNewPassword;
                            }
                            if (value.length < 6 || value.length > 20) {
                              return l10n.passwordLengthHint;
                            }
                            return null;
                          },
                        ),
                        // 密码强度提示（弱/中/强，颜色区分）
                        Padding(
                          padding: EdgeInsets.only(top: 8.h),
                          child:
                              _buildStrengthIndicator(l10n, _newPasswordController.text),
                        ),
                        // 密码规则提示
                        Padding(
                          padding: EdgeInsets.only(top: 6.h),
                          child: Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                size: 12.sp,
                                color: AppColor.textHint(context),
                              ),
                              SizedBox(width: 4.w),
                              Expanded(
                                child: Text(
                                  l10n.passwordRuleHint,
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: AppColor.textHint(context),
                                  ),
                                ),
                              ),
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
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n.pleaseConfirmPassword;
                            }
                            if (value != _newPasswordController.text) {
                              return l10n.passwordNotConsistent;
                            }
                            return null;
                          },
                        ),
                        // 品牌渐变胶囊提交按钮
                        SizedBox(
                          width: double.infinity,
                          height: 48.h,
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(24.r),
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF1565C0),
                                    Color(0xFF2196F3),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(24.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF1565C0)
                                        .withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24.r),
                                onTap: state is AuthLoading ? null : _submit,
                                child: Center(
                                  child: state is AuthLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          _setPasswordMode
                                              ? l10n.setPassword
                                              : l10n.confirmChange,
                                          style: TextStyle(
                                            fontSize: 16.sp,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
