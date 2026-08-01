import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
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

  void _handleSendCode() {
    final l10n = AppLocalizations.of(context)!;
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseInputCorrectEmail),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    context
        .read<AuthBloc>()
        .add(AuthSendEmailCodeRequested(email: email, type: 'register'));
  }

  void _handleRegister() {
    if (!_formKey.currentState!.validate()) return;

    context.read<AuthBloc>().add(
          AuthEmailRegisterRequested(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            code: _codeController.text.trim(),
            phone: _phoneController.text.trim(),
            nickname: _nicknameController.text.trim(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)!.translateError(state.message),
                ),
                backgroundColor: AppColors.error,
              ),
            );
          } else if (state is AuthCodeSent) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(AppLocalizations.of(context)!.verificationCodeSent),
                backgroundColor: AppColors.success,
              ),
            );
            _startCountdown();
          } else if (state is AuthAuthenticated) {
            context.go('/home');
          }
        },
        builder: (context, state) {
          // 顶部品牌渐变区 + 悬浮表单卡片，键盘弹出仍可滚动
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBrandHeader(),
                // 悬浮卡片：Transform 视觉上叠（Container 负 margin 会触发运行时断言崩溃）
                Transform.translate(
                  offset: Offset(0, -24.h),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                    padding: EdgeInsets.fromLTRB(24.w, 28.h, 24.w, 8.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1565C0).withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(),
                          SizedBox(height: 28.h),
                          _buildEmailField(),
                          SizedBox(height: 16.h),
                          _buildCodeField(state),
                          SizedBox(height: 16.h),
                          _buildPhoneField(),
                          SizedBox(height: 16.h),
                          _buildNicknameField(),
                          SizedBox(height: 16.h),
                          _buildPasswordField(),
                          SizedBox(height: 16.h),
                          _buildConfirmPasswordField(),
                          SizedBox(height: 28.h),
                          _buildRegisterButton(state),
                        ],
                      ),
                    ),
                  ),
                ),
                // 视觉间隙由 Transform 上移补偿
                const SizedBox(height: 0),
                _buildLoginRow(),
                SizedBox(height: 32.h),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 品牌区：渐变头部 + 返回按钮 + Logo + 品牌名
  Widget _buildBrandHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 260.h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF42A5F5)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(36.r)),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // 返回按钮（白色，浮于渐变区）
            if (Navigator.of(context).canPop())
              Positioned(
                left: 4.w,
                top: 0,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            // 装饰：右上大圆环
            Positioned(
              right: -70.w,
              top: -70.w,
              child: Container(
                width: 230.w,
                height: 230.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 26,
                  ),
                ),
              ),
            ),
            // 装饰：左下光斑
            Positioned(
              left: -50.w,
              bottom: -40.w,
              child: Container(
                width: 150.w,
                height: 150.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 大 Logo：白底圆角卡 + csergy.png
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 6.h,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/brand_logo.png',
                      height: 36.h,
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(height: 14.h),
                  // 小 Logo：辰烁科技.png
                  Image.asset(
                    'assets/images/brand_name.png',
                    height: 22.h,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    l10n.pvInverterMonitor,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
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
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          l10n.registerToUseAll,
          style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
        ),
      ],
    );
  }

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
              labelText: l10n.emailVerificationCode,
              hintText: l10n.pleaseInputVerificationCode,
              prefixIcon: const Icon(Icons.mark_email_read_outlined),
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
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade500,
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
        if (value == null || value.trim().isEmpty) return l10n.pleaseInputPhone;
        if (value.trim().length < 5) return l10n.phoneTooShort;
        return null;
      },
    );
  }

  Widget _buildNicknameField() {
    final l10n = AppLocalizations.of(context)!;
    return TextFormField(
      controller: _nicknameController,
      decoration: InputDecoration(
        labelText: l10n.pleaseInputUsername,
        hintText: l10n.pleaseInputUsername,
        prefixIcon: const Icon(Icons.person_outlined),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return l10n.pleaseInputUsername;
        }
        if (value.trim().length < 2) return l10n.usernameTooShort;
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

  Widget _buildLoginRow() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          l10n.alreadyHaveAccount,
          style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
        ),
        TextButton(
          onPressed: () {
            // 优先返回上一页（登录页/一键登录页），无上级页面时才跳转登录页
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/login');
            }
          },
          child: Text(
            l10n.loginNow,
            style: TextStyle(fontSize: 14.sp, color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}
