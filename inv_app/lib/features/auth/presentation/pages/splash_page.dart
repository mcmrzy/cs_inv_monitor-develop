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
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      context.read<AuthBloc>().add(AuthCheckRequested());
    }
  }

  /// 未登录时判断是否自动进入一键登录（初始化成功 + 获取手机号成功才可）
  Future<void> _redirectUnauthenticated() async {
    bool canOneClick = false;
    try {
      final jverifyService = getIt<JVerifyService>();
      if (jverifyService.isSupported) {
        bool initOk = false;
        for (int i = 0; i < 3 && !initOk; i++) {
          if (i > 0) {
            await Future.delayed(const Duration(milliseconds: 800));
          }
          initOk = await jverifyService.isInitSuccess();
        }
        if (initOk) {
          final enabled = await jverifyService.checkVerifyEnable();
          if (enabled) {
            // 预取号成功即"获取手机号成功"，随后可拉起展示脱敏号码的自绘授权页
            canOneClick = await jverifyService.preLogin();
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
              // 中心品牌内容
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // csergy.png 大 Logo（白底圆角卡）
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20.w,
                        vertical: 10.h,
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
                        height: 64.h,
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(height: 18.h),
                    // 辰烁科技.png 小 Logo
                    Image.asset(
                      'assets/images/brand_name.png',
                      height: 30.h,
                      fit: BoxFit.contain,
                    ),
                    SizedBox(height: 10.h),
                    Text(
                      l10n.pvInverterMonitor,
                      style: GoogleFonts.notoSansSc(
                        fontSize: 14.sp,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    SizedBox(height: 44.h),
                    // 小号加载动画：浅蓝细圈
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFFB3E5FC)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
