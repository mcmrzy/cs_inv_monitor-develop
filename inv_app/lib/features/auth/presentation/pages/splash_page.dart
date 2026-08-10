import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/jverify_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  /// JVerify 预检查任务：与登录态检查并行启动，最迟 1.2s 内结束（不阻塞已登录跳转）
  late final Future<void> _jverifyPrefetch;
  bool _canOneClick = false;

  @override
  void initState() {
    super.initState();
    // 并行启动：登录态检查 + 一键登录预检查，互不阻塞、互不等待
    _jverifyPrefetch = _prefetchJVerify();
    context.read<AuthBloc>().add(AuthCheckRequested());
  }

  /// 预检查一键登录可用性（与登录态检查并行；总时长 ≤1.2s，超时直接放弃走登录页）
  Future<void> _prefetchJVerify() async {
    bool canOneClick = false;
    try {
      final jverifyService = getIt<JVerifyService>();
      if (jverifyService.isSupported) {
        final deadline =
            DateTime.now().add(const Duration(milliseconds: 1200));
        bool initOk = false;
        // 初始化成功即继续，否则最多重试一次后放弃（一键登录不是必需能力）
        for (int i = 0;
            i < 2 && !initOk && DateTime.now().isBefore(deadline);
            i++) {
          if (i > 0) {
            await Future.delayed(const Duration(milliseconds: 400));
          }
          initOk = await jverifyService.isInitSuccess();
        }
        if (initOk && DateTime.now().isBefore(deadline)) {
          final enabled = await jverifyService.checkVerifyEnable();
          if (enabled) {
            // 预取号成功即"获取手机号成功"，随后可拉起展示脱敏号码的自绘授权页
            canOneClick = await jverifyService.preLogin(timeoutMs: 800);
          }
        }
      }
    } catch (e) {
      debugPrint('[SplashPage] JVerify precheck error: $e');
    }
    _canOneClick = canOneClick;
  }

  /// 未登录分流：等待并行中的预检查收尾（≤1.2s），完成后跳转
  Future<void> _redirectUnauthenticated() async {
    await _jverifyPrefetch;
    if (!mounted) return;
    context.go(_canOneClick ? '/jverify-login' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final topPadding = MediaQuery.of(context).padding.top;
    final xiaoshuoHeight = MediaQuery.of(context).size.height * 0.52;
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          context.go('/home');
        } else if (state is AuthUnauthenticated) {
          _redirectUnauthenticated();
        }
      },
      child: Scaffold(
        // 底色与原生启动屏渐变起始色一致：淡入动画期间不闪白，无缝衔接成一段开屏画面
        backgroundColor: const Color(0xFF0D47A1),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0D47A1),
                Color(0xFF1565C0),
                Color(0xFF42A5F5),
              ],
            ),
          ),
          child: Stack(
            children: [
              // 开屏背景图（纯净品牌蓝渐变 + 细腻磨砂光感，无主体，与前景小烁不重复）
              Positioned.fill(
                child: IgnorePointer(
                  child: Image.asset(
                    CsergyAssets.bgSplash,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              // 右上双圆环装饰（克制几何元素 1）
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
              Positioned(
                right: -16.w,
                top: 96.h,
                child: Container(
                  width: 96.w,
                  height: 96.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 10,
                    ),
                  ),
                ),
              ),
              // 左下光斑（克制几何元素 2）
              Positioned(
                left: -50.w,
                bottom: -50.w,
                child: Container(
                  width: 150.w,
                  height: 150.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              // 中右小光斑（克制几何元素 3）
              Positioned(
                right: -30.w,
                bottom: 220.h,
                child: Container(
                  width: 110.w,
                  height: 110.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              // 顶部品牌字标 CSERGY（白色细光晕，规范预留位）
              Positioned(
                top: topPadding + 64.h,
                left: 0,
                right: 0,
                child: _FadeInUp(
                  duration: const Duration(milliseconds: 650),
                  child: Text(
                    'CSERGY',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.white.withValues(alpha: 0.9),
                          blurRadius: 6,
                        ),
                        Shadow(
                          color: Colors.white.withValues(alpha: 0.45),
                          blurRadius: 14,
                        ),
                        Shadow(
                          color: const Color(0xFF90CAF9)
                              .withValues(alpha: 0.55),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 中部副标语
              Positioned(
                top: topPadding + 122.h,
                left: 0,
                right: 0,
                child: _FadeInUp(
                  duration: const Duration(milliseconds: 650),
                  child: Text(
                    l10n.pvInverterMonitor,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.sp,
                      letterSpacing: 2.5,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              ),
              // 主体：小烁（居中偏下，占屏高约 52%）+ 透明泛蓝光亚克力底座
              Positioned(
                left: 0,
                right: 0,
                bottom: 128.h,
                child: _FadeInUp(
                  duration: const Duration(milliseconds: 650),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        CsergyAssets.xiaoshuoWelcome,
                        height: xiaoshuoHeight,
                        fit: BoxFit.contain,
                      ),
                      // 亚克力底座：透明泛蓝光椭圆，营造悬浮陈列感
                      Container(
                        margin: EdgeInsets.only(top: -22.h),
                        width: 320.w,
                        height: 46.h,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(23.h),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.30),
                              Colors.white.withValues(alpha: 0.10),
                              Colors.white.withValues(alpha: 0.03),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF64B5F6)
                                  .withValues(alpha: 0.38),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 底部版本号（动态读取 AppConfig.version，避免硬编码）
              Positioned(
                left: 0,
                right: 0,
                bottom: 48.h,
                child: Text(
                  'V${AppConfig.version}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white.withValues(alpha: 0.4),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 品牌开屏统一动效：650ms 淡入上浮（easeOutCubic）
class _FadeInUp extends StatelessWidget {
  const _FadeInUp({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18.h),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}