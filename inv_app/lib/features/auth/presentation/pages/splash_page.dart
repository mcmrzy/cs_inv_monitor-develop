import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inv_app/core/services/jverify_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
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
              // 左上太阳放射光线（光伏主题装饰）
              const Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _SunRayPainter()),
                ),
              ),
              // 右上双圆环装饰
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
              // 左下光斑
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
              // 中右小光斑
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
              // 底部斜切渐变带
              Positioned(
                left: -80.w,
                right: -80.w,
                bottom: -70.h,
                child: Transform.rotate(
                  angle: -0.1,
                  child: Container(
                    height: 150.h,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.05),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 中心品牌内容：太阳能板图标 + 品牌名 + 副标语（淡入上浮）
              Transform.translate(
                offset: Offset(0, -20.h),
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 650),
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 太阳能板图标（白色光晕圆底）
                        Container(
                          width: 112.w,
                          height: 112.w,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.22),
                                blurRadius: 36,
                                spreadRadius: 6,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(22.w),
                            child: Image.asset(
                              'assets/images/solar_panel.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        SizedBox(height: 26.h),
                        // 品牌名文字（随语言切换：辰烁科技 / CSERGY）
                        Text(
                          l10n.brandName,
                          style: TextStyle(
                            fontSize: 24.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ),
                        SizedBox(height: 10.h),
                        Text(
                          l10n.pvInverterMonitor,
                          style: GoogleFonts.notoSansSc(
                            fontSize: 14.sp,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 底部版本号
              Positioned(
                left: 0,
                right: 0,
                bottom: 48.h,
                child: Text(
                  'V1.0.0',
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

/// 左上角太阳放射光线装饰（光伏主题）
class _SunRayPainter extends CustomPainter {
  const _SunRayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.2;
    // 光源在屏幕左上角外，向中上区域放射
    const origin = Offset(-50, -50);
    const sector = math.pi / 2.6;
    for (int i = 0; i < 20; i++) {
      final angle = (i / 19) * sector;
      final length = size.width * 0.62;
      canvas.drawLine(
        origin,
        origin + Offset(math.cos(angle), math.sin(angle)) * length,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SunRayPainter oldDelegate) => false;
}
