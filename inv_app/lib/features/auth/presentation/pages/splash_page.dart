import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/jverify_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/onboarding/data/onboarding_storage.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  /// JVerify 预检查任务：与登录态检查并行启动，最迟 1.2s 内结束（不阻塞已登录跳转）
  late final Future<void> _jverifyPrefetch;
  bool _canOneClick = false;

  /// 进入时刻：用于保证开屏页最短展示时长
  late final DateTime _enteredAt;

  /// 开屏最短展示时长：登录态检查只读本地存储（毫秒级完成），
  /// 不加最短展示会导致开屏图一闪而过、页面切换间隙露黑，
  /// 与系统启动屏衔接保证品牌开屏可见
  static const Duration _minDisplay = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    _enteredAt = DateTime.now();
    // 并行启动：登录态检查 + 一键登录预检查，互不阻塞、互不等待
    _jverifyPrefetch = _prefetchJVerify();
    context.read<AuthBloc>().add(AuthCheckRequested());
  }

  /// 等待开屏最短展示时长结束（不足则补齐剩余时间）
  Future<void> _waitMinDisplay() async {
    final remaining = _minDisplay - DateTime.now().difference(_enteredAt);
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
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
            // 预取号：5s 原生超时（插件合法范围下限 3000ms），外层用剩余 deadline 截断，
            // 不阻塞启动跳转；未等到的结果由 JVerifyService 缓存，供一键登录页复用
            final remaining = deadline.difference(DateTime.now());
            if (!remaining.isNegative) {
              try {
                canOneClick = await jverifyService
                    .preLogin(timeoutMs: 5000)
                    .timeout(remaining, onTimeout: () => false);
              } catch (_) {
                canOneClick = false;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[SplashPage] JVerify precheck error: $e');
    }
    _canOneClick = canOneClick;
  }

  /// 登录分流前统一收口：首次安装/版本升级需先展示引导页，
  /// 通过 extra 将登录分流目标传给 /onboarding，完成后原路返回
  Future<void> _continueAfterSplash(String target) async {
    await _waitMinDisplay();
    final needsOnboarding = await OnboardingStorage().needsOnboarding();
    if (!mounted) return;
    if (needsOnboarding) {
      context.go('/onboarding', extra: target);
    } else {
      context.go(target);
    }
  }

  /// 未登录分流：等待并行中的预检查收尾（≤1.2s），完成后跳转
  Future<void> _redirectUnauthenticated() async {
    await _waitMinDisplay();
    await _jverifyPrefetch;
    if (!mounted) return;
    // guest 离网会话保持：上次以免登录方式进入本地模式，
    // 重启后直接回到主页（本地数据链路），不再要求登录
    if (getIt<ConnectionModeService>().isGuestLocalMode) {
      context.go('/home');
      return;
    }
    await _continueAfterSplash(_canOneClick ? '/jverify-login' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (previous, current) => !current.isProfileUpdateTerminal,
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          _continueAfterSplash('/home');
        } else if (state is AuthUnauthenticated) {
          _redirectUnauthenticated();
        }
      },
      child: Scaffold(
        // 底色纯白与系统启动屏（白底+CSERGY logo）无缝衔接；开屏图解码完成即覆盖
        backgroundColor: const Color(0xFFFFFFFF),
        body: Stack(
          children: [
            // 品牌开屏完整图（用户设计稿：品牌字标/小烁/底座一体画面，全屏展示）
            // contain：横幅图（1441×513 超宽）竖屏完整显示、上下留白，不裁切
            Positioned.fill(
              child: IgnorePointer(
                child: Image.asset(
                  CsergyAssets.bgSplash,
                  fit: BoxFit.contain,
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
                    color: const Color(0xFF10284D).withValues(alpha: 0.4),
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

