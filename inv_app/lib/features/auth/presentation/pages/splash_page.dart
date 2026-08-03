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
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // 仅保留最短品牌展示时长（防止闪跳突兀），不再长时间占屏；
    // 登录态检查与跳转由 AuthBloc 异步完成
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      context.read<AuthBloc>().add(AuthCheckRequested());
    }
  }

  /// 未登录时判断是否自动进入一键登录（初始化成功 + 获取手机号成功才可）
  /// 所有检查限制在总时长内完成，超时直接进登录页，避免开屏页长时间转圈
  Future<void> _redirectUnauthenticated() async {
    bool canOneClick = false;
    try {
      final jverifyService = getIt<JVerifyService>();
      if (jverifyService.isSupported) {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        bool initOk = false;
        for (int i = 0; i < 3 && !initOk && DateTime.now().isBefore(deadline); i++) {
          if (i > 0) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
          initOk = await jverifyService.isInitSuccess();
        }
        if (initOk && DateTime.now().isBefore(deadline)) {
          final enabled = await jverifyService.checkVerifyEnable();
          if (enabled) {
            // 预取号成功即"获取手机号成功"，随后可拉起展示脱敏号码的自绘授权页
            canOneClick = await jverifyService.preLogin(timeoutMs: 1500);
          }
        }
      }
    } catch (e) {
      debugPrint('[SplashPage] JVerify check error: $e');
    }

    if (mounted) {
      context.go(canOneClick ? '/jverify-login' : '/login');
    }
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
              // 右上大圆环装饰
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
              // 中心品牌内容（去掉 CSERGY，整体上移保持视觉重心偏上）
              Transform.translate(
                offset: Offset(0, -28.h),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 品牌名文字（替代原辰烁科技.png 图片，随语言切换）
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
            ],
          ),
        ),
      ),
    );
  }
}
