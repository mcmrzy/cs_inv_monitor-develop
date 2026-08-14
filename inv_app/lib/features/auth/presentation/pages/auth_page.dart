import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/auth/presentation/widgets/login_form.dart';
import 'package:inv_app/features/auth/presentation/widgets/register_form.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:wifi_iot/wifi_iot.dart';

/// 登录/注册模式
enum AuthMode { login, register }

/// 登录注册页：品牌渐变头部 + 悬浮表单卡片
/// 登录/注册表单通过 AnimatedSwitcher 做组件级切换动画（滑动 + 淡入）。
/// 整体布局恢复自历史提交 eb75752be：白底 + 渐变品牌头（含圆环/光斑呼吸
/// 装饰与卖点胶囊）+ 白色悬浮卡片 + 底部切换行。
class AuthPage extends StatefulWidget {
  final AuthMode initialMode;

  const AuthPage({super.key, this.initialMode = AuthMode.login});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  late AuthMode _mode;

  /// 品牌区装饰呼吸动画控制器（圆环/光斑错相脉动，4s 周期）
  /// 仅登录模式运行；注册模式品牌头收缩后装饰被裁剪，暂停动画省电
  late final AnimationController _decorController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    // 初始即注册模式时品牌头收缩、装饰被裁剪：不启动呼吸动画
    if (_mode == AuthMode.register) {
      _decorController.stop();
      _decorController.value = 0;
    }
  }

  @override
  void dispose() {
    _decorController.dispose();
    super.dispose();
  }

  void _switchMode(AuthMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    // 注册模式品牌头收缩后装饰被裁剪：暂停呼吸动画省电，切回登录恢复
    if (mode == AuthMode.register) {
      _decorController.stop();
      _decorController.value = 0;
    } else {
      _decorController.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            AppToast.show(
              context,
              AppLocalizations.of(context)!.translateError(state.message),
              type: ToastType.error,
            );
          } else if (state is AuthAuthenticated) {
            context.go('/home');
          }
        },
        builder: (context, state) {
          // 顶部品牌渐变头 + 悬浮表单卡片，键盘弹出仍可滚动
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBrandHeader(),
                SizedBox(height: 10.h),
                // 悬浮卡片：表单上覆盖住品牌区底部一块（Transform 视觉上叠，负 margin 会触发运行时断言崩溃）
                Transform.translate(
                  offset: Offset(0, -30.h),
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
                _buildSwitchRow(),
                SizedBox(height: 16.h),
                // 本地离网模式入口（需求 6：产品化，与登录卡片同风格的描边卡片）
                GestureDetector(
                  onTap: _enterGuestLocalMode,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 13.h,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF1565C0,
                          ).withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 18.sp,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(
                              context,
                            )!.str('auth_local_mode_link'),
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18.sp,
                          color: AppColors.textHint,
                        ),
                      ],
                    ),
                  ),
                ),
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

  /// 品牌区：渐变头部 + 品牌名 + 副标语（无 CSERGY）
  /// 卖点胶囊沉在头部底部与文字分层；表单卡片上覆盖住头部底部一块。
  /// 注册模式向上缩小收起（高度 260→110、品牌名/副标语/胶囊淡出且不占位），只留渐变条
  Widget _buildBrandHeader() {
    final l10n = AppLocalizations.of(context)!;
    final isRegister = _mode == AuthMode.register;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
      height: isRegister ? 110.h : 260.h,
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
            // 装饰：右上大圆环（缓慢呼吸：缩放 + 透明度脉动）
            Positioned(
              right: -70.w,
              top: -70.w,
              child: AnimatedBuilder(
                animation: _decorController,
                builder: (context, child) {
                  final v =
                      const _BreathingCurve().transform(_decorController.value);
                  return Transform.scale(
                    scale: 0.94 + 0.08 * v,
                    child: Opacity(opacity: 0.7 + 0.3 * v, child: child),
                  );
                },
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
            ),
            // 装饰：左下光斑（与圆环错相呼吸：放大 + 变亮）
            Positioned(
              left: -50.w,
              bottom: -40.w,
              child: AnimatedBuilder(
                animation: _decorController,
                builder: (context, child) {
                  final v = const _BreathingCurve(phase: 0.5)
                      .transform(_decorController.value);
                  return Transform.scale(
                    scale: 1.0 + 0.22 * v,
                    child: Opacity(opacity: 0.5 + 0.5 * v, child: child),
                  );
                },
                child: Container(
                  width: 150.w,
                  height: 150.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
            ),
            // 品牌内容：品牌名 + 副标语（注册模式均淡出且不占位）
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 品牌名（随语言切换：辰烁科技 / CSERGY；注册模式淡出且不占位）
                  AnimatedOpacity(
                    opacity: isRegister ? 0 : 1,
                    duration: const Duration(milliseconds: 250),
                    child: Visibility(
                      visible: !isRegister,
                      maintainState: true,
                      maintainAnimation: true,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOutCubic,
                        style: TextStyle(
                          fontSize: isRegister ? 22.sp : 28.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                        child: Text(l10n.brandName),
                      ),
                    ),
                  ),
                  // 副标语：光伏逆变器智能监控（注册模式淡出且不占位）
                  AnimatedOpacity(
                    opacity: isRegister ? 0 : 1,
                    duration: const Duration(milliseconds: 250),
                    child: Visibility(
                      visible: !isRegister,
                      maintainState: true,
                      maintainAnimation: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: 8.h),
                          Text(
                            l10n.pvInverterMonitor,
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 卖点胶囊：沉到品牌头底部，与上方文字拉开距离（注册模式隐藏）
            Positioned(
              left: 0,
              right: 0,
              bottom: 36.h,
              child: AnimatedOpacity(
                opacity: isRegister ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                child: Visibility(
                  visible: !isRegister,
                  maintainState: true,
                  maintainAnimation: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildFeatureChip(l10n.realtimeData),
                      SizedBox(width: 10.w),
                      _buildFeatureChip(l10n.str('remote_settings')),
                      SizedBox(width: 10.w),
                      _buildFeatureChip(l10n.alarmPush),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 卖点胶囊（渐变品牌头样式：半透明白底 + 白字）
  Widget _buildFeatureChip(String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.sp, color: Colors.white),
      ),
    );
  }

  /// 本地离网模式入口（Q4）：以 guest 身份进入本地模式，免登录直接使用
  /// 本地数据链路（蓝牙/AP/本地 OTA）；已连接设备 AP 则直接进离网主界面，
  /// 否则进入 /local-mode 引导页
  Future<void> _enterGuestLocalMode() async {
    await getIt<ConnectionModeService>().enterGuestLocalMode();
    if (!mounted) return;
    final connectedToDeviceAP = await _isConnectedToDeviceAP();
    if (!mounted) return;
    if (connectedToDeviceAP) {
      context.go('/home');
    } else {
      context.go('/local-mode');
    }
  }

  /// 当前 WiFi 是否已连接到逆变器热点（CS-INV-xxxx / CS_INV_xxxx）
  Future<bool> _isConnectedToDeviceAP() async {
    try {
      final ssid = await WiFiForIoTPlugin.getSSID();
      if (ssid == null || ssid.isEmpty) return false;
      final upper = ssid.toUpperCase();
      return upper.startsWith('CS-INV') || upper.startsWith('CS_INV');
    } catch (_) {
      return false;
    }
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

/// 呼吸曲线：t∈[0,1] → 0→1→0 平滑正弦（phase 控制相位偏移，0.5 为反相）
class _BreathingCurve extends Curve {
  final double phase;
  const _BreathingCurve({this.phase = 0});

  @override
  double transformInternal(double t) {
    final v = (math.cos((t + phase) * 2 * math.pi) + 1) / 2;
    return v.clamp(0.0, 1.0);
  }
}
