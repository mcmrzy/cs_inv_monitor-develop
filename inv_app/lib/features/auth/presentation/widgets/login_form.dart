import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/jverify_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/slider_captcha_dialog.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 登录方式：密码 / 验证码
enum _LoginMode { password, code }

/// 验证码通道：手机短信 / 邮箱
enum _CodeChannel { phone, email }

/// 登录表单组件
/// 密码模式：账户 / 密码 / 记住密码 / 登录 / 一键登录入口
/// 验证码模式：手机短信 / 邮箱双通道验证码登录
/// 由 AuthPage 通过 AnimatedSwitcher 与注册表单切换展示
class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberPassword = false;
  bool _jverifyAvailable = false;
  _LoginMode _loginMode = _LoginMode.password;
  _CodeChannel _codeChannel = _CodeChannel.phone;
  bool _isSendingCode = false;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _checkJVerifyAvailability();
  }

  /// 检查一键登录是否可用（决定是否展示"本机号码一键登录"入口）
  Future<void> _checkJVerifyAvailability() async {
    try {
      final jverifyService = getIt<JVerifyService>();

      // 重试机制：等待 SDK 完成远程配置获取
      bool initOk = false;
      for (int i = 0; i < 3 && !initOk && mounted; i++) {
        if (i > 0) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
        initOk = await jverifyService.isInitSuccess();
      }

      if (initOk && mounted) {
        final enabled = await jverifyService.checkVerifyEnable();
        if (mounted) {
          setState(() {
            _jverifyAvailable = enabled;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSavedCredentials() async {
    final storage = getIt<StorageService>();
    final rememberPassword = await storage.getRememberPassword();
    if (rememberPassword) {
      _accountController.text = await storage.getSavedPhone() ?? '';
      _passwordController.text = await storage.getSavedPassword() ?? '';
      setState(() {
        _rememberPassword = true;
      });
    }
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _codeController.dispose();
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

  /// 验证码模式下发送验证码：先滑块验证，再按通道调用短信/邮箱发送
  Future<void> _handleSendCode() async {
    final l10n = AppLocalizations.of(context)!;
    if (_codeChannel == _CodeChannel.phone) {
      final phone = _phoneController.text.trim();
      if (phone.isEmpty || phone.length < 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pleaseInputPhone)),
        );
        return;
      }
      // 后端要求先通过滑块验证，获取 verifyToken 后随请求携带
      final captchaToken = await showSliderCaptcha(context);
      if (captchaToken == null || !mounted) return;
      context.read<AuthBloc>().add(
            AuthSendCodeRequested(
              phone: phone,
              type: 'login',
              captchaToken: captchaToken,
            ),
          );
    } else {
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
              type: 'login',
              captchaToken: captchaToken,
            ),
          );
    }
  }

  void _handleLogin() {
    if (!_formKey.currentState!.validate()) return;

    if (_loginMode == _LoginMode.password) {
      context.read<AuthBloc>().add(
            AuthLoginRequested(
              account: _accountController.text.trim(),
              password: _passwordController.text,
              rememberPassword: _rememberPassword,
            ),
          );
    } else if (_codeChannel == _CodeChannel.phone) {
      context.read<AuthBloc>().add(
            AuthPhoneCodeLoginRequested(
              phone: _phoneController.text.trim(),
              code: _codeController.text.trim(),
            ),
          );
    } else {
      context.read<AuthBloc>().add(
            AuthEmailCodeLoginRequested(
              email: _emailController.text.trim(),
              code: _codeController.text.trim(),
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
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
            _buildModeSwitcher(),
            SizedBox(height: 24.h),
            if (_loginMode == _LoginMode.password) ...[
              _buildAccountField(),
              SizedBox(height: 16.h),
              _buildPasswordField(),
              SizedBox(height: 8.h),
              _buildRememberRow(),
              SizedBox(height: 24.h),
              _buildLoginButton(state),
              if (_jverifyAvailable) ...[
                SizedBox(height: 12.h),
                _buildJVerifyEntry(state),
              ],
            ] else ...[
              _buildChannelSwitcher(),
              SizedBox(height: 20.h),
              if (_codeChannel == _CodeChannel.phone)
                _buildPhoneField()
              else
                _buildEmailField(),
              SizedBox(height: 16.h),
              _buildCodeField(state),
              SizedBox(height: 24.h),
              _buildLoginButton(state),
            ],
          ],
        ),
      ),
    );
  }

  /// 登录方式切换条：密码登录 / 验证码登录（胶囊式，与管理后台登录页一致）
  /// 单个白色滑块在两个选项间平移，避免两侧背景交叉淡入淡出造成的闪烁
  Widget _buildModeSwitcher() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 44.h,
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 滑动指示器：唯一白色圆角块，切换时左右平移（无双块交叉过渡）
          AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: _loginMode == _LoginMode.password
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildModeTab(
                  l10n.str('login_mode_password'),
                  _loginMode == _LoginMode.password,
                  () => setState(() => _loginMode = _LoginMode.password),
                ),
              ),
              Expanded(
                child: _buildModeTab(
                  l10n.str('login_mode_code'),
                  _loginMode == _LoginMode.code,
                  () => setState(() => _loginMode = _LoginMode.code),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? AppColors.primary
                : AppColor.textSecondary(context),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  /// 验证码通道切换：手机验证码 / 邮箱验证码（文字 + 下划线指示器）
  Widget _buildChannelSwitcher() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildChannelTab(
          l10n.str('code_channel_phone'),
          _codeChannel == _CodeChannel.phone,
          () => setState(() {
            _codeChannel = _CodeChannel.phone;
            _codeController.clear();
          }),
        ),
        SizedBox(width: 32.w),
        _buildChannelTab(
          l10n.str('code_channel_email'),
          _codeChannel == _CodeChannel.email,
          () => setState(() {
            _codeChannel = _CodeChannel.email;
            _codeController.clear();
          }),
        ),
      ],
    );
  }

  Widget _buildChannelTab(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? AppColors.primary
                  : AppColor.textSecondary(context),
            ),
          ),
          SizedBox(height: 5.h),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: selected ? 24.w : 0,
            height: 2.5,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountField() {
    final l10n = AppLocalizations.of(context)!;
    return TextFormField(
      controller: _accountController,
      keyboardType: TextInputType.text,
      decoration: InputDecoration(
        labelText: l10n.phoneOrEmailOrUsername,
        hintText: l10n.inputPhoneEmailUsername,
        prefixIcon: const Icon(Icons.person_outlined),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return l10n.pleaseInputAccount;
        return null;
      },
    );
  }

  /// 验证码模式：手机号输入
  Widget _buildPhoneField() {
    final l10n = AppLocalizations.of(context)!;
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
        if (value == null || value.trim().isEmpty) {
          return l10n.pleaseInputPhone;
        }
        if (value.trim().length < 5) return l10n.phoneTooShort;
        return null;
      },
    );
  }

  /// 验证码模式：邮箱输入
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

  /// 验证码模式：验证码输入 + 发送按钮（滑块验证 + 60s 倒计时）
  Widget _buildCodeField(AuthState state) {
    final l10n = AppLocalizations.of(context)!;
    final isPhone = _codeChannel == _CodeChannel.phone;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: isPhone
                  ? l10n.str('sms_verification_code')
                  : l10n.emailVerificationCode,
              hintText: l10n.pleaseInputVerificationCode,
              prefixIcon: Icon(
                isPhone
                    ? Icons.sms_outlined
                    : Icons.mark_email_read_outlined,
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
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
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
        labelText: l10n.password,
        hintText: l10n.inputPasswordHint,
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
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return l10n.pleaseInputPassword;
        }
        if (value.length < 6 || value.length > 20) {
          return l10n.passwordLength;
        }
        return null;
      },
    );
  }

  Widget _buildRememberRow() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        // 自绘圆角勾选框，替代原生 Checkbox
        GestureDetector(
          onTap: () {
            setState(() {
              _rememberPassword = !_rememberPassword;
            });
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20.w,
                height: 20.w,
                decoration: BoxDecoration(
                  color: _rememberPassword
                      ? AppColors.primary
                      : AppColor.surfaceContainer(context),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _rememberPassword
                        ? AppColors.primary
                        : AppColor.outline(context),
                    width: 1.5,
                  ),
                ),
                child: _rememberPassword
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.rememberPassword,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColor.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => context.push('/forgot-password'),
          child: Text(
            l10n.forgotPasswordQ,
            style: TextStyle(fontSize: 14.sp, color: AppColors.primary),
          ),
        ),
      ],
    );
  }

  /// 登录主按钮（品牌渐变）
  Widget _buildLoginButton(AuthState state) {
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
          onTap: state is AuthLoading ? null : _handleLogin,
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
                    l10n.login,
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

  /// 一键登录入口（蓝色文字链，跳转一键登录页）
  Widget _buildJVerifyEntry(AuthState state) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.phone_iphone_rounded,
          size: 16,
          color: AppColors.primary,
        ),
        SizedBox(width: 4.w),
        TextButton(
          onPressed:
              state is AuthLoading ? null : () => context.push('/jverify-login'),
          child: Text(
            l10n.oneClickLoginTitle,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}
