import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/slider_captcha_dialog.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/core/data/continents_data.dart';
import 'package:inv_app/features/auth/presentation/widgets/auth_country_picker_sheet.dart';
import 'package:inv_app/l10n/app_localizations.dart';

typedef CaptchaPresenter = Future<String?> Function(BuildContext context);

/// 注册表单组件（创建账号标题 / 国家地区选择 / 验证码 / 密码 / 确认密码）
/// 仅中国大陆（CN）走手机号+短信验证码注册，其余国家/地区走邮箱注册；
/// 注册不设昵称字段，海外昵称由后端以邮箱前缀兜底。
/// 由 AuthPage 通过 AnimatedSwitcher 与登录表单切换展示
class RegisterForm extends StatefulWidget {
  const RegisterForm({
    super.key,
    this.captchaPresenter = showSliderCaptcha,
  });

  final CaptchaPresenter captchaPresenter;

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isCodeRequestInProgress = false;
  bool _isAwaitingCodeResult = false;
  String? _pendingCodeRequestCountryCode;
  String? _pendingCodeRequestTarget;
  String? _pendingCodeRequestId;
  bool _isSendingCode = false;
  bool _isSubmitting = false;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;
  String _selectedCountryCode = 'CN'; // 默认中国大陆；其余国家/地区走邮箱注册

  /// 仅中国大陆走手机号注册，其他国家/地区走邮箱注册
  bool get _isMainland => _selectedCountryCode == 'CN';

  @override
  void dispose() {
    _emailController.dispose();
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
      _isSendingCode = true;
      _isCodeRequestInProgress = false;
      _isAwaitingCodeResult = false;
      _pendingCodeRequestCountryCode = null;
      _pendingCodeRequestTarget = null;
      _pendingCodeRequestId = null;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_countdownSeconds > 1) {
          _countdownSeconds--;
        } else {
          _countdownSeconds = 0;
          _isSendingCode = false;
          timer.cancel();
        }
      });
    });
  }

  void _releaseCodeRequest() {
    if (!mounted) return;
    setState(() {
      _isCodeRequestInProgress = false;
      _isAwaitingCodeResult = false;
      _pendingCodeRequestCountryCode = null;
      _pendingCodeRequestTarget = null;
      _pendingCodeRequestId = null;
    });
  }

  void _cancelCooldownForChangedTarget() {
    if (!_isSendingCode) return;
    _countdownTimer?.cancel();
    setState(() {
      _countdownSeconds = 0;
      _isSendingCode = false;
      _codeController.clear();
    });
  }

  void _handleCodeTargetChanged() {
    if (_isAwaitingCodeResult) {
      _codeController.clear();
      _releaseCodeRequest();
      return;
    }
    _cancelCooldownForChangedTarget();
  }

  Future<void> _handleSendCode() async {
    if (_isCodeRequestInProgress || _isSendingCode || _isSubmitting) return;
    final l10n = AppLocalizations.of(context)!;
    final requestCountryCode = _selectedCountryCode;
    final requestIsMainland = requestCountryCode == 'CN';
    late final String target;
    if (!requestIsMainland) {
      // 海外国家/地区：仅发送邮箱验证码
      final email = _emailController.text.trim();
      if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pleaseInputCorrectEmail)),
        );
        return;
      }
      target = email;
    } else {
      // 中国大陆：发送短信验证码到手机号
      final phone = _phoneController.text.trim();
      if (phone.isEmpty || phone.length < 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pleaseInputPhone)),
        );
        return;
      }
      target = phone;
    }

    setState(() => _isCodeRequestInProgress = true);
    try {
      final captchaToken = await widget.captchaPresenter(context);
      if (captchaToken == null || !mounted) return;
      if (_selectedCountryCode != requestCountryCode) return;
      final currentTarget = requestIsMainland
          ? _phoneController.text.trim()
          : _emailController.text.trim();
      if (currentTarget != target) return;

      final requestId = AuthCodeRequestId.next();
      _isAwaitingCodeResult = true;
      _pendingCodeRequestCountryCode = requestCountryCode;
      _pendingCodeRequestTarget = target;
      _pendingCodeRequestId = requestId;
      if (requestIsMainland) {
        context.read<AuthBloc>().add(
              AuthSendCodeRequested(
                phone: target,
                type: 'register',
                requestId: requestId,
                captchaToken: captchaToken,
              ),
            );
      } else {
        context.read<AuthBloc>().add(
              AuthSendEmailCodeRequested(
                email: target,
                type: 'register',
                requestId: requestId,
                captchaToken: captchaToken,
              ),
            );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.sliderCaptchaFailed)),
        );
      }
    } finally {
      if (mounted && !_isAwaitingCodeResult) {
        _releaseCodeRequest();
      }
    }
  }

  void _handleRegister() {
    if (_isCodeRequestInProgress || _isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    if (!_isMainland) {
      // 海外国家/地区：邮箱 + 邮箱验证码 + 密码，不需要手机号与昵称
      context.read<AuthBloc>().add(
            AuthEmailRegisterRequested(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              code: _codeController.text.trim(),
              phone: '', // 海外纯邮箱注册不传手机号
              nickname: '', // 注册不设昵称，后端以邮箱前缀兜底
              country: _selectedCountryCode, // 注册时选择的国家/地区代码落库
            ),
          );
    } else {
      // 中国大陆：手机号 + 短信验证码 + 密码
      context.read<AuthBloc>().add(
            AuthRegisterRequested(
              phone: _phoneController.text.trim(),
              password: _passwordController.text,
              code: _codeController.text.trim(),
              country: _selectedCountryCode, // 注册时选择的国家/地区代码落库
            ),
          );
    }
  }

  /// 打开国家/地区选择弹层；切换国家后验证码通道变化，清空验证码重新发送
  Future<void> _showCountryPickerSheet() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          AuthCountryPickerSheet(initialCode: _selectedCountryCode),
    );
    if (!mounted) return;
    if (result != null && result['code'] != _selectedCountryCode) {
      final supersedesPendingRequest = _isAwaitingCodeResult;
      setState(() {
        _selectedCountryCode = result['code']!;
        _codeController.clear();
        if (!_isAwaitingCodeResult) {
          _countdownTimer?.cancel();
          _countdownSeconds = 0;
          _isSendingCode = false;
        }
      });
      if (supersedesPendingRequest) {
        _releaseCodeRequest();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthBloc>().state;
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthCodeSent) {
          if (!_isAwaitingCodeResult) return;
          final expectedChannel =
              _pendingCodeRequestCountryCode == 'CN' ? 'phone' : 'email';
          if (state.type != 'register' ||
              state.channel != expectedChannel ||
              state.target != _pendingCodeRequestTarget ||
              state.requestId != _pendingCodeRequestId) {
            return;
          }
          if (_pendingCodeRequestCountryCode != _selectedCountryCode) {
            _releaseCodeRequest();
            return;
          }
          final currentTarget = _isMainland
              ? _phoneController.text.trim()
              : _emailController.text.trim();
          if (_pendingCodeRequestTarget != currentTarget) {
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
        } else if (state is AuthCodeSendError && _isAwaitingCodeResult) {
          final expectedChannel =
              _pendingCodeRequestCountryCode == 'CN' ? 'phone' : 'email';
          if (state.type == 'register' &&
              state.channel == expectedChannel &&
              state.target == _pendingCodeRequestTarget &&
              state.requestId == _pendingCodeRequestId) {
            final currentTarget = _isMainland
                ? _phoneController.text.trim()
                : _emailController.text.trim();
            if (_pendingCodeRequestCountryCode != _selectedCountryCode ||
                currentTarget != _pendingCodeRequestTarget) {
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
          }
        } else if (state is AuthError &&
            state is! AuthCodeSendError &&
            !state.isProfileUpdateTerminal &&
            _isSubmitting) {
          setState(() => _isSubmitting = false);
        }
      },
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            SizedBox(height: 24.h),
            _buildCountrySelector(),
            SizedBox(height: 16.h),
            if (_isMainland)
              _buildPhoneField()
            else
              _buildEmailField(),
            SizedBox(height: 16.h),
            _buildCodeField(),
            SizedBox(height: 16.h),
            _buildPasswordField(),
            SizedBox(height: 16.h),
            _buildConfirmPasswordField(),
            SizedBox(height: 28.h),
            _buildRegisterButton(state),
          ],
        ),
      ),
    );
  }

  /// 标题区：创建账号 + 副标语（置于表单卡片内）
  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Text(
          l10n.createAccount,
          style: TextStyle(
            fontSize: 24.sp,
            fontWeight: FontWeight.bold,
            color: AppColor.textPrimary(context),
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          l10n.registerToUseAll,
          style: TextStyle(fontSize: 14.sp, color: AppColor.textSecondary(context)),
        ),
      ],
    );
  }

  /// 国家/地区选择：点击弹出可搜索的国家列表，仅中国大陆走手机号注册
  Widget _buildCountrySelector() {
    final l10n = AppLocalizations.of(context)!;
    final countryName = countryNameByCode(_selectedCountryCode) ?? '';
    return InkWell(
      onTap: _showCountryPickerSheet,
      borderRadius: BorderRadius.circular(12.r),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.str('auth_country_region'),
          hintText: l10n.str('auth_select_country_hint'),
          prefixIcon: const Icon(Icons.public_outlined),
          suffixIcon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColor.textSecondary(context),
          ),
        ),
        child: Text(
          '$countryName ($_selectedCountryCode)',
          style: TextStyle(
            fontSize: 15.sp,
            color: AppColor.textPrimary(context),
          ),
        ),
      ),
    );
  }

  /// 邮箱注册时填写（中国大陆不展示）
  Widget _buildEmailField() {
    final l10n = AppLocalizations.of(context)!;
    return TextFormField(
      controller: _emailController,
      onChanged: (_) => _handleCodeTargetChanged(),
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: l10n.email,
        hintText: l10n.pleaseInputEmail,
        prefixIcon: const Icon(Icons.email_outlined),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return l10n.pleaseInputEmail;
        if (!value.contains('@') || !value.contains('.')) {
          return l10n.pleaseInputCorrectEmail;
        }
        return null;
      },
    );
  }

  /// 验证码输入 + 发送按钮（中国大陆为短信验证码，海外为邮箱验证码）
  Widget _buildCodeField() {
    final l10n = AppLocalizations.of(context)!;
    final isEmail = !_isMainland;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: isEmail
                  ? l10n.emailVerificationCode
                  : l10n.str('sms_verification_code'),
              hintText: l10n.pleaseInputVerificationCode,
              prefixIcon: Icon(
                isEmail
                    ? Icons.mark_email_read_outlined
                    : Icons.sms_outlined,
              ),
              counterText: '',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.pleaseInputVerificationCode;
              }
              if (value.length < 4) return l10n.pleaseInputCorrectCode;
              return null;
            },
          ),
        ),
        SizedBox(width: 12.w),
        SizedBox(
          width: 120.w,
          height: 56.h,
          child: ElevatedButton(
            onPressed:
                _isSendingCode || _isCodeRequestInProgress || _isSubmitting
                ? null
                : _handleSendCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColor.surfaceHover(context),
              disabledForegroundColor: AppColor.textHint(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              padding: EdgeInsets.zero,
            ),
            child: _isCodeRequestInProgress
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

  /// 手机号输入（仅中国大陆注册展示，其他国家/地区不展示）
  Widget _buildPhoneField() {
    final l10n = AppLocalizations.of(context)!;
    return TextFormField(
      controller: _phoneController,
      onChanged: (_) => _handleCodeTargetChanged(),
      keyboardType: TextInputType.phone,
      maxLength: 15,
      decoration: InputDecoration(
        labelText: l10n.phone,
        hintText: l10n.pleaseInputPhone,
        prefixIcon: const Icon(Icons.phone_outlined),
        counterText: '',
      ),
      validator: (value) {
        if (_isMainland && (value == null || value.trim().isEmpty)) {
          return l10n.pleaseInputPhone;
        }
        if (value != null && value.trim().isNotEmpty && value.trim().length < 5) {
          return l10n.phoneTooShort;
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    final l10n = AppLocalizations.of(context)!;
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: l10n.password,
        hintText: l10n.inputNewPasswordHint,
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return l10n.pleaseInputPassword;
        if (value.length < 6 || value.length > 20) return l10n.passwordLength;
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
          onPressed: () => setState(
            () => _obscureConfirmPassword = !_obscureConfirmPassword,
          ),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return l10n.pleaseConfirmPassword;
        if (value != _passwordController.text) return l10n.passwordNotMatch;
        return null;
      },
    );
  }

  /// 注册按钮（品牌渐变）
  Widget _buildRegisterButton(AuthState state) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 50.h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1565C0), Color(0xFF2196F3)],
        ),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('register-submit-button'),
          borderRadius: BorderRadius.circular(14.r),
          onTap: _isCodeRequestInProgress ||
                  _isSubmitting ||
                  state is AuthLoading
              ? null
              : _handleRegister,
          child: Center(
            child: _isSubmitting || state is AuthLoading
                ? SizedBox(
                    width: 20.h,
                    height: 20.h,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    l10n.register,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
