import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/router/app_router.dart';
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

  /// 待恢复的冷启动深链回调（见 _restoreDeepLinkOnTop）
  VoidCallback? _pendingDeepLinkRestore;

  @override
  void initState() {
    super.initState();
    _enteredAt = DateTime.now();
    // 并行启动：登录态检查 + 一键登录预检查，互不阻塞、互不等待
    _jverifyPrefetch = _prefetchJVerify();
    context.read<AuthBloc>().add(AuthCheckRequested());
  }

  @override
  void dispose() {
    // 若 go 的路由变更回调尚未触发（理论上不会），移除监听避免泄漏
    final handler = _pendingDeepLinkRestore;
    _pendingDeepLinkRestore = null;
    if (handler != null) {
      AppRouter.router.routerDelegate.removeListener(handler);
    }
    super.dispose();
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

  /// 读取冷启动窗口内被 push 到 Splash 之上的深链完整 URI（含 query）。
  /// Splash 的 1.2s 最短展示期间，智能链接（csinv://bind）与小组件
  /// （invapp://notifications）的冷启动路径已把深链页压栈
  /// （见 main.dart _initDeepLinks/_initWidgetDeepLinks）；
  /// 栈顶仍是 Splash 说明没有深链，返回 null。
  String? _pendingDeepLinkUri() {
    final config = AppRouter.router.routerDelegate.currentConfiguration;
    final topLocation = config.lastOrNull?.matchedLocation ?? '';
    if (topLocation.isEmpty || topLocation == '/splash') return null;
    return config.uri.toString();
  }

  /// 把深链压回栈顶（go 之后调用）。go/push 经由异步解析生效，
  /// 紧跟 go 的 push 会捕获到旧的 currentConfiguration 作为 base，
  /// 因此监听一次路由配置变更（go 真正落地）后再 push，
  /// 保证最终栈为 [目标基础页, 深链页]。
  void _restoreDeepLinkOnTop(String uri) {
    void onStackChanged() {
      _pendingDeepLinkRestore = null;
      AppRouter.router.routerDelegate.removeListener(onStackChanged);
      AppRouter.router.push(uri);
    }

    _pendingDeepLinkRestore = onStackChanged;
    AppRouter.router.routerDelegate.addListener(onStackChanged);
  }

  /// 登录分流前统一收口：首次安装/版本升级需先展示引导页，
  /// 通过 extra 将登录分流目标传给 /onboarding，完成后原路返回
  Future<void> _continueAfterSplash(String target) async {
    await _waitMinDisplay();
    final needsOnboarding = await OnboardingStorage().needsOnboarding();
    if (!mounted) return;

    if (needsOnboarding) {
      // 引导优先：深链放弃（引导完成前叠加深链页体验割裂，
      // 用户可重新扫码/点小组件再次进入）
      context.go('/onboarding', extra: target);
      return;
    }
    // 冷启动深链保护：go 会按目标位置重建栈、丢掉已被压栈的深链页。
    // 先在 go 之前记录栈顶深链（此时路由配置尚未被 go 改写），
    // go 落地后把深链原样压回栈顶（首页在底、深链在顶）
    final pendingDeepLink = _pendingDeepLinkUri();
    if (pendingDeepLink != null) {
      _restoreDeepLinkOnTop(pendingDeepLink);
    }
    context.go(target);
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

