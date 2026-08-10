import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/jverify_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';

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
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          context.go('/home');
        } else if (state is AuthUnauthenticated) {
          _redirectUnauthenticated();
        }
      },
      child: Scaffold(
        // 底色取开屏图顶部主色（#6EABE4 浅蓝）：图片解码完成前与系统启动屏同色，
        // 冷启动全程只见开屏图，无深蓝渐变突兀
        backgroundColor: const Color(0xFF6EABE4),
        body: Stack(
          children: [
            // 品牌开屏完整图（用户设计稿：品牌字标/小烁/底座一体画面，全屏展示）
            Positioned.fill(
              child: IgnorePointer(
                child: Image.asset(
                  CsergyAssets.bgSplash,
                  fit: BoxFit.cover,
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
    );
  }
}

