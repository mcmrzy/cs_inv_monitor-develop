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
  const LoginForm({
    super.key,
    this.captchaLauncher,
  });

  /// 测试可注入的滑块验证入口；生产环境默认使用真实滑块对话框。
  final Future<String?> Function(BuildContext context)? captchaLauncher;

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
  bool _isRequestingCode = false;
  bool _isAwaitingCodeResult = false;
  _CodeChannel? _pendingCodeChannel;
  String? _pendingCodeTarget;
  String? _pendingCodeRequestId;
  bool _isSendingCode = false;
  bool _isSubmitting = false;
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
          if (!mounted) return;
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
    String? savedPhone;
    String? savedPassword;
    if (rememberPassword) {
      savedPhone = await storage.getSavedPhone();
      savedPassword = await storage.getSavedPassword();
    }
    if (!mounted) return;
    if (rememberPassword) {
      _accountController.text = savedPhone ?? '';
      _passwordController.text = savedPassword ?? '';
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
    if (!mounted) return;
    setState(() {
      _countdownSeconds = 60;
      _isRequestingCode = false;
      _isAwaitingCodeResult = false;
      _pendingCodeChannel = null;
      _pendingCodeTarget = null;
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
      _isRequestingCode = false;
      _isAwaitingCodeResult = false;
      _pendingCodeChannel = null;
      _pendingCodeTarget = null;
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

  void _selectCodeChannel(_CodeChannel channel) {
    if (_codeChannel == channel) return;
    final supersedesPendingRequest = _isAwaitingCodeResult;
    _countdownTimer?.cancel();
    setState(() {
      _codeChannel = channel;
      _codeController.clear();
      if (_isSendingCode) {
        _countdownSeconds = 0;
        _isSendingCode = false;
      }
    });
    if (supersedesPendingRequest) {
      _releaseCodeRequest();
    }
  }

  /// 验证码模式下发送验证码：先滑块验证，再按通道调用短信/邮箱发送
  Future<void> _handleSendCode() async {
    // 方法级保护同时覆盖界面尚未来得及重建的连续点击。
    if (_isRequestingCode || _isSendingCode || _isSubmitting) return;

    final l10n = AppLocalizations.of(context)!;
    final channel = _codeChannel;
    late final String target;
    if (channel == _CodeChannel.phone) {
      final phone = _phoneController.text.trim();
      if (phone.isEmpty || phone.length < 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pleaseInputPhone)),
        );
        return;
      }
      target = phone;
    } else {
      final email = _emailController.text.trim();
      if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pleaseInputCorrectEmail)),
        );
        return;
      }
      target = email;
    }

    setState(() => _isRequestingCode = true);
    // 后端要求先通过滑块验证，获取 verifyToken 后随请求携带。
    String? captchaToken;
    try {
      captchaToken = await (widget.captchaLauncher ?? showSliderCaptcha)(
        context,
      );
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
    if (_codeChannel != channel) {
      _releaseCodeRequest();
      return;
    }
    final currentTarget = channel == _CodeChannel.phone
        ? _phoneController.text.trim()
        : _emailController.text.trim();
    if (currentTarget != target) {
      _releaseCodeRequest();
      return;
    }

    final requestId = AuthCodeRequestId.next();
    setState(() {
      _isAwaitingCodeResult = true;
      _pendingCodeChannel = channel;
      _pendingCodeTarget = target;
      _pendingCodeRequestId = requestId;
    });

    if (channel == _CodeChannel.phone) {
      context.read<AuthBloc>().add(
            AuthSendCodeRequested(
              phone: target,
              // login 类型由后端在发码前校验账号是否已注册。
              type: 'login',
              requestId: requestId,
              captchaToken: captchaToken,
            ),
          );
    } else {
      context.read<AuthBloc>().add(
            AuthSendEmailCodeRequested(
              email: target,
              type: 'login',
              requestId: requestId,
              captchaToken: captchaToken,
            ),
          );
    }
  }

  void _handleLogin() {
    if (_isRequestingCode || _isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

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
          if (!_isAwaitingCodeResult) return;
          final pendingChannel = _pendingCodeChannel;
          final currentTarget = pendingChannel == _CodeChannel.phone
              ? _phoneController.text.trim()
              : _emailController.text.trim();
          if (state.type != 'login' ||
              state.channel != pendingChannel?.name ||
              state.target != _pendingCodeTarget ||
              state.requestId != _pendingCodeRequestId) {
            return;
          }
          if (pendingChannel != _codeChannel ||
              currentTarget != _pendingCodeTarget) {
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
          if (state.type == 'login' &&
              state.channel == _pendingCodeChannel?.name &&
              state.target == _pendingCodeTarget &&
              state.requestId == _pendingCodeRequestId) {
            final currentTarget = _pendingCodeChannel == _CodeChannel.phone
                ? _phoneController.text.trim()
                : _emailController.text.trim();
            if (_pendingCodeChannel != _codeChannel ||
                currentTarget != _pendingCodeTarget) {
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
          () => _selectCodeChannel(_CodeChannel.phone),
        ),
        SizedBox(width: 32.w),
        _buildChannelTab(
          l10n.str('code_channel_email'),
          _codeChannel == _CodeChannel.email,
          () => _selectCodeChannel(_CodeChannel.email),
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
            key: const Key('login-send-code-button'),
            onPressed: (_isRequestingCode ||
                    _isSendingCode ||
                    _isSubmitting)
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
            child: _isRequestingCode
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
          key: const Key('login-submit-button'),
          borderRadius: BorderRadius.circular(14.r),
          onTap: _isRequestingCode || _isSubmitting || state is AuthLoading
              ? null
              : _handleLogin,
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
          onPressed: _isRequestingCode || _isSubmitting || state is AuthLoading
              ? null
              : () => context.push('/jverify-login'),
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
