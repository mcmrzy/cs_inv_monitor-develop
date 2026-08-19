import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/slider_captcha_dialog.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 注册模式：中国大陆（手机号+短信验证码）/ 海外（邮箱+邮箱验证码）
enum _RegisterMode { mainland, overseas }

/// 注册表单组件（创建账号标题 / 通道切换 / 邮箱或手机验证码 / 密码 / 确认密码）
/// 由 AuthPage 通过 AnimatedSwitcher 与登录表单切换展示
class RegisterForm extends StatefulWidget {
  const RegisterForm({super.key});

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSendingCode = false;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;
  _RegisterMode _registerMode = _RegisterMode.mainland; // 默认中国大陆

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _nicknameController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _countdownSeconds = 60;
      _isSendingCode = true;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_countdownSeconds > 0) {
          _countdownSeconds--;
        } else {
          _isSendingCode = false;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _handleSendCode() async {
    final l10n = AppLocalizations.of(context)!;
    if (_registerMode == _RegisterMode.overseas) {
      // 海外模式：仅发送邮箱验证码
      final email = _emailController.text.trim();
      if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pleaseInputCorrectEmail)),
        );
        return;
      }
      final captchaToken = await showSliderCaptcha(context);
      if (captchaToken == null || !mounted) return;
      context.read<AuthBloc>().add(
            AuthSendEmailCodeRequested(
              email: email,
              type: 'register',
              captchaToken: captchaToken,
            ),
          );
    } else {
      // 中国大陆模式：发送短信验证码到手机号
      final phone = _phoneController.text.trim();
      if (phone.isEmpty || phone.length < 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pleaseInputPhone)),
        );
        return;
      }
      final captchaToken = await showSliderCaptcha(context);
      if (captchaToken == null || !mounted) return;
      context.read<AuthBloc>().add(
            AuthSendCodeRequested(
              phone: phone,
              type: 'register',
              captchaToken: captchaToken,
            ),
          );
    }
  }

  void _handleRegister() {
    if (!_formKey.currentState!.validate()) return;

    if (_registerMode == _RegisterMode.overseas) {
      // 海外模式：仅需邮箱 + 昵称（可选）+ 密码，不需要手机号
      context.read<AuthBloc>().add(
            AuthEmailRegisterRequested(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              code: _codeController.text.trim(),
              phone: '', // 海外模式不传手机号
              nickname: _nicknameController.text.trim(),
              country: '', // 海外模式暂无具体国家选择，后端可选字段
            ),
          );
    } else {
      // 中国大陆模式：手机号 + 短信验证码 + 昵称 + 密码
      context.read<AuthBloc>().add(
            AuthRegisterRequested(
              phone: _phoneController.text.trim(),
              password: _passwordController.text,
              code: _codeController.text.trim(),
              country: 'CN', // 注册时选择的国别/地区代码落库
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = context.watch<AuthBloc>().state;
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthCodeSent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.verificationCodeSent),
            ),
          );
          _startCountdown();
        }
      },
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            SizedBox(height: 24.h),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 4.w),
                child: Text(
                  l10n.str('auth_country_region'),
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColor.textSecondary(context),
                  ),
                ),
              ),
            ),
            SizedBox(height: 8.h),
            _buildChannelSwitcher(),
            SizedBox(height: 24.h),
            if (_registerMode == _RegisterMode.mainland)
              _buildPhoneField()
            else ...[
              _buildEmailField(),
              SizedBox(height: 16.h),
              _buildNicknameField(),
            ],
            SizedBox(height: 16.h),
            _buildCodeField(state),
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

  /// 注册模式切换条：中国大陆 / 海外（胶囊式，与登录表单切换条样式一致）
  Widget _buildChannelSwitcher() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 44.h,
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildChannelTab(
              l10n.str('auth_mainland_china'),
              _registerMode == _RegisterMode.mainland,
              () => setState(() {
                _registerMode = _RegisterMode.mainland;
                _codeController.clear();
              }),
            ),
          ),
          Expanded(
            child: _buildChannelTab(
              l10n.str('auth_overseas'),
              _registerMode == _RegisterMode.overseas,
              () => setState(() {
                _registerMode = _RegisterMode.overseas;
                _codeController.clear();
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelTab(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10.r),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? AppColors.primary
                  : AppColor.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }

  /// 邮箱注册时填写（手机注册通道不展示）
  Widget _buildEmailField() {
    final l10n = AppLocalizations.of(context)!;
    return TextFormField(
      controller: _emailController,
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

  /// 验证码输入 + 发送按钮（按通道显示短信/邮箱验证码）
  Widget _buildCodeField(AuthState state) {
    final l10n = AppLocalizations.of(context)!;
    final isEmail = _registerMode == _RegisterMode.overseas;
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
            onPressed: _isSendingCode ? null : _handleSendCode,
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
            child: state is AuthCodeSending
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

  /// 手机号输入（中国大陆模式必填，海外模式不展示）
  Widget _buildPhoneField() {
    final l10n = AppLocalizations.of(context)!;
    final isMainland = _registerMode == _RegisterMode.mainland;
    return TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      maxLength: 15,
      decoration: InputDecoration(
        labelText: l10n.phone,
        hintText: l10n.pleaseInputPhone,
        prefixIcon: const Icon(Icons.phone_outlined),
        counterText: '',
      ),
      validator: (value) {
        if (isMainland && (value == null || value.trim().isEmpty)) {
          return l10n.pleaseInputPhone;
        }
        if (value != null && value.trim().isNotEmpty && value.trim().length < 5) {
          return l10n.phoneTooShort;
        }
        return null;
      },
    );
  }

  /// 昵称输入（两种模式均选填，海外模式留空时后端以邮箱前缀兜底）
  Widget _buildNicknameField() {
    final l10n = AppLocalizations.of(context)!;
    return TextFormField(
      controller: _nicknameController,
      decoration: InputDecoration(
        labelText: l10n.nickname,
        hintText: l10n.str('username_optional'),
        prefixIcon: const Icon(Icons.person_outlined),
      ),
      validator: (value) {
        if (value != null && value.trim().isNotEmpty && value.trim().length < 2) {
          return l10n.usernameTooShort;
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
          borderRadius: BorderRadius.circular(14.r),
          onTap: state is AuthLoading ? null : _handleRegister,
          child: Center(
            child: state is AuthLoading
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
