import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
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

    context.read<AuthBloc>().add(AuthLoginRequested(
      account: _accountController.text.trim(),
      password: _passwordController.text,
      rememberPassword: _rememberPassword,
    ));
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
                content: Text(state.message),
                backgroundColor: AppColors.error,
              ),
            );
          } else if (state is AuthAuthenticated) {
            context.go('/home');
          }
        },
        builder: (context, state) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24.w),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 60.h),
                    _buildLogo(),
                    SizedBox(height: 40.h),
                    _buildAccountField(),
                    SizedBox(height: 16.h),
                    _buildPasswordField(),
                    SizedBox(height: 16.h),
                    _buildRememberRow(),
                    SizedBox(height: 32.h),
                    _buildLoginButton(state),
                    SizedBox(height: 24.h),
                    _buildSocialLoginDivider(),
                    SizedBox(height: 20.h),
                    _buildSocialLoginButtons(),
                    SizedBox(height: 24.h),
                    _buildRegisterRow(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Text(
          '光伏逆变器',
          style: TextStyle(
            fontSize: 28.sp,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          '智能监控平台',
          style: TextStyle(
            fontSize: 16.sp,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildAccountField() {
    return TextFormField(
      controller: _accountController,
      keyboardType: TextInputType.text,
      decoration: InputDecoration(
        labelText: '手机号 / 邮箱 / 用户名',
        hintText: '输入手机号、邮箱或用户名',
        prefixIcon: const Icon(Icons.person_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return '请输入账号';
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: '密码',
        hintText: '请输入密码',
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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
          return '请输入密码';
        }
        if (value.length < 6 || value.length > 20) {
          return '密码长度为6-20位';
        }
        return null;
      },
    );
  }

  Widget _buildRememberRow() {
    return Row(
      children: [
        Checkbox(
          value: _rememberPassword,
          onChanged: (value) {
            setState(() {
              _rememberPassword = value ?? false;
            });
          },
        ),
        Text('记住密码', style: TextStyle(fontSize: 14.sp)),
        const Spacer(),
        TextButton(
          onPressed: () => context.push('/forgot-password'),
          child: Text('忘记密码?', style: TextStyle(fontSize: 14.sp)),
        ),
      ],
    );
  }

  Widget _buildLoginButton(AuthState state) {
    return ElevatedButton(
      onPressed: state is AuthLoading ? null : _handleLogin,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 14.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.r),
        ),
      ),
      child: state is AuthLoading
          ? SizedBox(
              height: 20.h,
              width: 20.w,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Text('登录', style: TextStyle(fontSize: 16.sp)),
    );
  }

  Widget _buildRegisterRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('还没有账号?', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
        TextButton(
          onPressed: () => context.push('/register'),
          child: Text('立即注册', style: TextStyle(fontSize: 14.sp)),
        ),
      ],
    );
  }

  Widget _buildSocialLoginDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: const Color(0xFFE5E7EB), thickness: 1.h)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Text('其他登录方式', style: TextStyle(fontSize: 12.sp, color: const Color(0xFF9CA3AF))),
        ),
        Expanded(child: Divider(color: const Color(0xFFE5E7EB), thickness: 1.h)),
      ],
    );
  }

  Widget _buildSocialLoginButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildSocialButton(
          iconPath: 'assets/icons/wechat.svg',
          label: '微信',
          onTap: () {
            context.read<AuthBloc>().add(const AuthWechatLoginRequested(code: ''));
          },
        ),
        SizedBox(width: 40.w),
        _buildSocialButton(
          iconPath: 'assets/icons/google.svg',
          label: 'Google',
          onTap: () {
            context.read<AuthBloc>().add(const AuthGoogleLoginRequested(idToken: ''));
          },
        ),
      ],
    );
  }

  Widget _buildSocialButton({
    required String iconPath,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52.w,
            height: 52.w,
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
            ),
            child: SvgPicture.asset(
              iconPath,
              width: 32.w,
              height: 32.w,
            ),
          ),
          SizedBox(height: 8.h),
          Text(label, style: TextStyle(fontSize: 12.sp, color: const Color(0xFF6B7280))),
        ],
      ),
    );
  }
}
