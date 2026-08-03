import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/auth/presentation/widgets/login_form.dart';
import 'package:inv_app/features/auth/presentation/widgets/register_form.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 登录/注册模式
enum AuthMode { login, register }

/// 登录注册页：品牌头 + 表单卡片
/// 登录/注册表单通过 AnimatedSwitcher 做组件级切换动画（滑动 + 淡入）
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
            context.go('/home');
          }
        },
        builder: (context, state) {
          final l10n = AppLocalizations.of(context)!;
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
                          color:
                              const Color(0xFF1565C0).withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 卖点胶囊：实时数据 / 告警推送 / OTA升级（置于表单上方）
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
                        SizedBox(height: 20.h),
                        // 登录/注册表单组件级切换动画
                        AnimatedSwitcher(
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
                      ],
                    ),
                  ),
                ),
                // 视觉间隙由 Transform 上移补偿
                const SizedBox(height: 0),
                _buildSwitchRow(),
                SizedBox(height: 32.h),
              ],
            ),
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

  /// 品牌区：渐变头部 + 品牌名（副标语与卖点胶囊已移至表单卡片，无 CSERGY）
  /// 注册模式时头部向上缩小收起（高度 320→120、品牌名淡出），表单随之整体上移
  Widget _buildBrandHeader() {
    final l10n = AppLocalizations.of(context)!;
    final isRegister = _mode == AuthMode.register;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
      height: isRegister ? 120.h : 320.h,
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
            // 品牌名（随语言切换：辰烁科技 / CSERGY；注册模式隐藏）
            Center(
              child: AnimatedOpacity(
                opacity: isRegister ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                child: Text(
                  l10n.brandName,
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 卖点胶囊（白底卡片样式：浅蓝底 + 蓝字）
  Widget _buildFeatureChip(String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.sp, color: const Color(0xFF2563EB)),
      ),
    );
  }

  /// 底部切换行：登录 ⇄ 注册（点击后表单组件动画切换）
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
