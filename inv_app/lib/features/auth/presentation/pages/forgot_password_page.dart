import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/slider_captcha_dialog.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({
    super.key,
    this.captchaLauncher,
  });

  @visibleForTesting
  final Future<String?> Function(BuildContext context)? captchaLauncher;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isRequestingCode = false;
  bool _isAwaitingCodeResult = false;
  String? _pendingCodePhone;
  String? _pendingCodeRequestId;
  bool _isSendingCode = false;
  bool _isResetting = false;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    if (!mounted) return;
    setState(() {
      _countdownSeconds = 60;
      _isRequestingCode = false;
      _isAwaitingCodeResult = false;
      _pendingCodePhone = null;
      _pendingCodeRequestId = null;
      _isSendingCode = true;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_countdownSeconds <= 1) {
          _countdownSeconds = 0;
          _isSendingCode = false;
          timer.cancel();
        } else {
          _countdownSeconds--;
        }
      });
    });
  }

  void _releaseCodeRequest() {
    if (!mounted) return;
    setState(() {
      _isRequestingCode = false;
      _isAwaitingCodeResult = false;
      _pendingCodePhone = null;
      _pendingCodeRequestId = null;
    });
  }

  void _cancelCooldownForChangedPhone() {
    if (!_isSendingCode) return;
    _countdownTimer?.cancel();
    setState(() {
      _countdownSeconds = 0;
      _isSendingCode = false;
      _codeController.clear();
    });
  }

  void _handlePhoneChanged() {
    if (_isAwaitingCodeResult) {
      _codeController.clear();
      _releaseCodeRequest();
      return;
    }
    _cancelCooldownForChangedPhone();
  }

  Future<void> _handleSendCode() async {
    if (_isRequestingCode || _isSendingCode) return;
    final l10n = AppLocalizations.of(context)!;
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseInputCorrectPhone),
        ),
      );
      return;
    }
    setState(() => _isRequestingCode = true);
    // 后端要求先通过滑块验证，获取 verifyToken 后随请求携带
    final launchCaptcha = widget.captchaLauncher ?? showSliderCaptcha;
    String? captchaToken;
    try {
      captchaToken = await launchCaptcha(context);
    } catch (_) {
      if (!mounted) return;
      _releaseCodeRequest();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sliderCaptchaFailed)),
      );
      return;
    }
    if (!mounted) return;
    if (captchaToken == null) {
      _releaseCodeRequest();
      return;
    }
    if (_phoneController.text.trim() != phone) {
      _releaseCodeRequest();
      return;
    }
    final requestId = AuthCodeRequestId.next();
    setState(() {
      _isAwaitingCodeResult = true;
      _pendingCodePhone = phone;
      _pendingCodeRequestId = requestId;
    });
    context.read<AuthBloc>().add(
          AuthSendCodeRequested(
            phone: phone,
            type: 'reset',
            requestId: requestId,
            captchaToken: captchaToken,
          ),
        );
  }

  void _handleResetPassword() {
    if (_isResetting) return;
    if (_formKey.currentState!.validate()) {
      setState(() => _isResetting = true);
      context.read<AuthBloc>().add(
            AuthResetPasswordRequested(
              phone: _phoneController.text.trim(),
              code: _codeController.text.trim(),
              newPassword: _passwordController.text,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 认证背景图（品牌蓝抽象场景，铺满）
          Positioned.fill(
            child: IgnorePointer(
              child: Image.asset(
                CsergyAssets.bgAuth,
                fit: BoxFit.cover,
              ),
            ),
          ),
          BlocConsumer<AuthBloc, AuthState>(
            listenWhen: (previous, current) => !current.isProfileUpdateTerminal,
            listener: (context, state) {
              if (state is AuthCodeSendError) {
                if (!_isAwaitingCodeResult ||
                    state.type != 'reset' ||
                    state.channel != 'phone' ||
                    state.target != _pendingCodePhone ||
                    state.requestId != _pendingCodeRequestId) {
                  return;
                }
                if (_pendingCodePhone != _phoneController.text.trim()) {
                  _releaseCodeRequest();
                  return;
                }
                _releaseCodeRequest();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.translateError(state.message),
                    ),
                  ),
                );
              } else if (state is AuthError) {
                if (_isResetting) {
                  setState(() => _isResetting = false);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.translateError(state.message),
                    ),
                  ),
                );
              } else if (state is AuthCodeSent) {
                if (!_isAwaitingCodeResult ||
                    state.type != 'reset' ||
                    state.channel != 'phone' ||
                    state.target != _pendingCodePhone ||
                    state.requestId != _pendingCodeRequestId) {
                  return;
                }
                if (_pendingCodePhone != _phoneController.text.trim()) {
                  _releaseCodeRequest();
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text(AppLocalizations.of(context)!.verificationCodeSent),
                  ),
                );
                _startCountdown();
              } else if (state is AuthPasswordResetSuccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text(AppLocalizations.of(context)!.passwordResetSuccess),
                  ),
                );
                context.go('/login');
              }
            },
            builder: (context, state) {
              return SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 24.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 56.h),
                      _buildHeader(),
                      SizedBox(height: 32.h),
                      // 毛玻璃表单卡片：半透明白底 + 背景模糊，浮于整页背景图上
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24.r),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0D47A1).withValues(alpha: 0.14),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24.r),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              padding: EdgeInsets.fromLTRB(24.w, 28.h, 24.w, 24.h),
                              decoration: BoxDecoration(
                                color: AppColor.surfaceContainer(context)
                                    .withValues(alpha: 0.82),
                                borderRadius: BorderRadius.circular(24.r),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildPhoneField(),
                                    SizedBox(height: 16.h),
                                    _buildCodeField(state),
                                    SizedBox(height: 16.h),
                                    _buildPasswordField(),
                                    SizedBox(height: 16.h),
                                    _buildConfirmPasswordField(),
                                    SizedBox(height: 28.h),
                                    _buildResetButton(state),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 20.h),
                      _buildLoginRow(),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Text(
          l10n.forgotPassword,
          style: TextStyle(
            fontSize: 28.sp,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: const [
              Shadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          l10n.pleaseInputRegisterPhone,
          style: TextStyle(
            fontSize: 14.sp,
            color: Colors.white.withValues(alpha: 0.9),
            shadows: const [
              Shadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    final l10n = AppLocalizations.of(context)!;
    return TextFormField(
      controller: _phoneController,
      onChanged: (_) => _handlePhoneChanged(),
      keyboardType: TextInputType.phone,
      maxLength: 11,
      decoration: InputDecoration(
        labelText: l10n.phone,
        hintText: l10n.pleaseInputRegisterPhone,
        prefixIcon: const Icon(Icons.phone_outlined),
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return l10n.pleaseInputPhone;
        }
        if (value.length != 11) {
          return l10n.pleaseInputCorrect11digitPhone;
        }
        return null;
      },
    );
  }

  Widget _buildCodeField(AuthState state) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: l10n.verifyCode,
              hintText: l10n.pleaseInputVerificationCode,
              prefixIcon: const Icon(Icons.security_outlined),
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.pleaseInputVerificationCode;
              }
              if (value.length != 6) {
                return l10n.pleaseInput6digitCode;
              }
              return null;
            },
          ),
        ),
        SizedBox(width: 12.w),
        SizedBox(
          width: 120.w,
          height: 56.h,
          child: ElevatedButton(
            key: const Key('forgot-password-send-code-button'),
            onPressed: _isSendingCode || _isRequestingCode || _isResetting
                ? null
                : _handleSendCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColor.surfaceHover(context),
              disabledForegroundColor: AppColor.textHint(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
              padding: EdgeInsets.zero,
            ),
            child: _isRequestingCode
                ? SizedBox(
                    height: 20.h,
                    width: 20.w,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    _isSendingCode ? '${_countdownSeconds}s' : l10n.send,
                    style: TextStyle(fontSize: 14.sp),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    final l10n = AppLocalizations.of(context)!;
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: l10n.newPassword,
        hintText: l10n.inputNewPasswordHint,
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return l10n.pleaseInputNewPassword;
        }
        if (value.length < 6 || value.length > 20) {
          return l10n.passwordLength;
        }
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField() {
    final l10n = AppLocalizations.of(context)!;
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      decoration: InputDecoration(
        labelText: l10n.confirmPassword,
        hintText: l10n.pleaseConfirmPassword,
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirmPassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () {
            setState(() {
              _obscureConfirmPassword = !_obscureConfirmPassword;
            });
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return l10n.pleaseConfirmPassword;
        }
        if (value != _passwordController.text) {
          return l10n.passwordNotMatch;
        }
        return null;
      },
    );
  }

  Widget _buildResetButton(AuthState state) {
    final l10n = AppLocalizations.of(context)!;
    return ElevatedButton(
      key: const Key('forgot-password-reset-button'),
      onPressed: _isResetting || _isRequestingCode || state is AuthLoading
          ? null
          : _handleResetPassword,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 14.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.r),
        ),
      ),
      child: _isResetting || state is AuthLoading
          ? SizedBox(
              height: 20.h,
              width: 20.w,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Text(l10n.reset, style: TextStyle(fontSize: 16.sp)),
    );
  }

  Widget _buildLoginRow() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          l10n.rememberPassword,
          style: TextStyle(fontSize: 14.sp, color: AppColor.textSecondary(context)),
        ),
        TextButton(
          onPressed: () => context.go('/login'),
          child: Text(l10n.returnToLogin, style: TextStyle(fontSize: 14.sp)),
        ),
      ],
    );
  }
}
