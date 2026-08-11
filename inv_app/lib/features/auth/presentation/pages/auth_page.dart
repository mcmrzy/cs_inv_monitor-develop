import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/auth/presentation/widgets/login_form.dart';
import 'package:inv_app/features/auth/presentation/widgets/register_form.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 登录/注册模式
enum AuthMode { login, register }

/// 登录注册页：品牌深蓝渐变背景图 + 毛玻璃表单卡片
/// 背景图全屏铺满（上部深色放品牌名，下部浅色放表单），表单卡片悬浮于中下部；登录/注册通过 AnimatedSwitcher 组件级切换
class AuthPage extends StatefulWidget {
  final AuthMode initialMode;

  const AuthPage({super.key, this.initialMode = AuthMode.login});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  late AuthMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  void _switchMode(AuthMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.surface(context),
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
            context.go('/home');
          }
        },
        builder: (context, state) {
          return Stack(
            children: [
              // 整页品牌背景图：深蓝渐变 + 抽象光伏/能量元素，无图形叠加
              Positioned.fill(
                child: IgnorePointer(
                  child: Image.asset(
                    CsergyAssets.bgAuth,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              // 前景：品牌名 + 毛玻璃表单卡片 + 切换行（键盘弹出可滚动）
              SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 24.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBrandArea(),
                      SizedBox(height: 36.h),
                      _buildFormCard(),
                      SizedBox(height: 24.h),
                      _buildSwitchRow(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 表单切换动画：淡入 + 水平滑动（新表单从右滑入，旧表单向右滑出）
  Widget _buildSwitchTransition(Widget child, Animation<double> animation) {
    final slide = Tween<Offset>(
      begin: const Offset(0.18, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(position: slide, child: child),
    );
  }

  /// 品牌区：品牌名 + 副标语（白字带阴影，浮于深蓝渐变背景上；无任何图形叠加）
  /// 注册模式副标语淡出且不占位，品牌名缩小，给表单留出滚动空间
  Widget _buildBrandArea() {
    final l10n = AppLocalizations.of(context)!;
    final isRegister = _mode == AuthMode.register;
    return Column(
      children: [
        SizedBox(height: 64.h),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
          style: TextStyle(
            fontSize: isRegister ? 22.sp : 30.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 1.5,
            shadows: const [
              Shadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(l10n.brandName, textAlign: TextAlign.center),
        ),
        // 副标语：光伏逆变器智能监控（注册模式淡出且不占位）
        AnimatedOpacity(
          opacity: isRegister ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: Visibility(
            visible: !isRegister,
            maintainState: true,
            maintainAnimation: true,
            child: Padding(
              padding: EdgeInsets.only(top: 10.h),
              child: Text(
                l10n.pvInverterMonitor,
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
            ),
          ),
        ),
      ],
    );
  }

  /// 毛玻璃表单卡片：白底半透明 + 背景模糊，浮于背景图上，保证输入区可读性
  Widget _buildFormCard() {
    return Container(
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
            padding: EdgeInsets.fromLTRB(24.w, 30.h, 24.w, 10.h),
            decoration: BoxDecoration(
              color: AppColor.surfaceContainer(context).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(24.r),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            // 登录/注册表单组件级切换动画
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: _buildSwitchTransition,
              child: _mode == AuthMode.login
                  ? const LoginForm(key: ValueKey('login-form'))
                  : const RegisterForm(
                      key: ValueKey('register-form'),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// 底部切换行：登录 ⇄ 注册（背景图下部为浅色，用常规深色文字保证对比度）
  Widget _buildSwitchRow() {
    final l10n = AppLocalizations.of(context)!;
    final isLogin = _mode == AuthMode.login;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isLogin ? l10n.notHaveAccount : l10n.alreadyHaveAccount,
          style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
        ),
        TextButton(
          onPressed: () =>
              _switchMode(isLogin ? AuthMode.register : AuthMode.login),
          child: Text(
            isLogin ? l10n.registerNow : l10n.loginNow,
            style: TextStyle(fontSize: 14.sp, color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}
