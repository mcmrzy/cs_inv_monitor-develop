import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/jverify_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberPassword = false;
  bool _jverifyAvailable = false;

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
    super.dispose();
  }

  void _handleLogin() {
    if (!_formKey.currentState!.validate()) return;

    context.read<AuthBloc>().add(
          AuthLoginRequested(
            account: _accountController.text.trim(),
            password: _passwordController.text,
            rememberPassword: _rememberPassword,
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
          } else if (state is AuthAuthenticated) {
            debugPrint('[LoginPage] Login success, navigate to /home');
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
                  offset: Offset(0, -28.h),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                    padding: EdgeInsets.fromLTRB(24.w, 32.h, 24.w, 8.h),
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
                        ],
                      ),
                    ),
                  ),
                ),
                // 视觉间隙由 Transform 上移补偿
                const SizedBox(height: 0),
                _buildRegisterRow(),
                SizedBox(height: 32.h),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 品牌区：渐变头部 + Logo + 品牌名 + 卖点胶囊
  Widget _buildBrandHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 320.h,
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
                      horizontal: 18.w,
                      vertical: 8.h,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/brand_logo.png',
                      height: 44.h,
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(height: 18.h),
                  // 小 Logo：辰烁科技.png
                  Image.asset(
                    'assets/images/brand_name.png',
                    height: 26.h,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    l10n.pvInverterMonitor,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  SizedBox(height: 22.h),
                  // 卖点胶囊：实时数据 / 告警推送 / OTA升级
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildFeatureChip(l10n.realtimeData),
                      SizedBox(width: 10.w),
                      _buildFeatureChip(l10n.alarmPush),
                      SizedBox(width: 10.w),
                      _buildFeatureChip(l10n.otaTitle),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 品牌卖点胶囊
  Widget _buildFeatureChip(String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.sp, color: Colors.white),
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
                  color: _rememberPassword ? AppColors.primary : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _rememberPassword
                        ? AppColors.primary
                        : const Color(0xFFD1D5DB),
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
                style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
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
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.phone_iphone_rounded,
              size: 16,
              color: AppColors.primary,
            ),
            SizedBox(width: 4.w),
            TextButton(
              onPressed: state is AuthLoading
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
        ),
      ],
    );
  }

  Widget _buildRegisterRow() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          l10n.notHaveAccount,
          style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
        ),
        TextButton(
          onPressed: () => context.push('/register'),
          child: Text(
            l10n.registerNow,
            style: TextStyle(fontSize: 14.sp, color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}
