import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:jiguang_auth/jiguang_auth.dart';

/// JVerify 运营商认证异常
class JVerifyCarrierException implements Exception {
  final int code;
  final String? message;
  JVerifyCarrierException(this.code, this.message);
  @override
  String toString() => 'JVerifyCarrierException(code=$code, message=$message)';
}

/// 极光认证服务
///
/// 封装 JVerify SDK，提供一键登录能力。
/// 使用单例模式，通过 [ServiceLocator] 注册。
class JVerifyService {
  // JVerify 错误码常量（来源：极光官方文档）
  static const int codeSuccess = 7000;       // 预取号成功
  static const int codeNoSim = 2002;         // 无 SIM 卡 / 蜂窝不可用
  static const int codePreLoginFailed = 2005; // 预取号超时/失败
  static const int codeSdkNotReady = 6012;   // SDK 初始化未就绪
  static const int codeLoginSuccess = 6000;  // 登录取号成功
  static const int codeUserCancel1 = 8001;   // 用户取消（通道 1）
  static const int codeUserCancel2 = 9000;   // 用户取消（通道 2）

  static final JVerifyService _instance = JVerifyService._internal();
  factory JVerifyService() => _instance;
  JVerifyService._internal();

  final Jverify _jverify = Jverify();
  bool _initialized = false;
  int _loginAttemptCounter = 0; // 记录登录尝试次数，防止重复初始化
  Future<bool>? _preLoginFuture; // 预取号进行中/成功缓存（复用同一运营商 token，避免重复取号）
  DateTime? _preLoginAt; // 预取号发起时间（运营商 token 有效期约 30s，缓存 20s）

  /// 检查当前平台是否支持 JVerify
  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// 初始化 JVerify SDK
  ///
  /// [appKey] 为极光应用的 AppKey（与 JPush 相同），未提供时使用默认值。
  /// 应在 App 启动、依赖注入初始化完成后调用。
  Future<void> init({String? appKey}) async {
    if (!isSupported) {
      debugPrint('[JVerifyService] Platform not supported, skipping init');
      return;
    }

    debugPrint('[JVerifyService] Initiating JVerify SDK setup...');
    
    _jverify.setDebugMode(kDebugMode);
    _jverify.setup(
      appKey: appKey ?? '5a5df0da74b0ec20becb9bb1',
      channel: 'inv_app',
    );
    
    // SDK 初始化是异步的，立即设为 true，后续由 isInitSuccess() 实际验证
    _initialized = true;
    
    debugPrint('[JVerifyService] SDK setup complete, config loading asynchronously...');
  }

  /// 检查 SDK 初始化是否成功
  Future<bool> isInitSuccess() async {
    if (!_initialized || !isSupported) return false;
    try {
      final map = await _jverify.isInitSuccess();
      return map['result'] == true;
    } catch (e) {
      debugPrint('[JVerifyService] isInitSuccess error: $e');
      return false;
    }
  }

  /// 检查当前蜂窝网络环境是否支持一键认证
  ///
  /// 仅在蜂窝数据网络且有 SIM 卡时返回 true。
  /// WiFi 环境或无 SIM 卡时返回 false。
  Future<bool> checkVerifyEnable() async {
    if (!_initialized || !isSupported) return false;
    try {
      final map = await _jverify.checkVerifyEnable();
      return map['result'] == true;
    } catch (e) {
      debugPrint('[JVerifyService] checkVerifyEnable error: $e');
      return false;
    }
  }

  /// 预取号（静默获取运营商 token，等价于"获取手机号成功"）
  ///
  /// code == 7000 表示预取号成功，随后拉起授权页可立即展示脱敏手机号。
  /// 带缓存复用：20s 内进行中/成功的请求直接复用；失败不缓存，便于快速重试重新取号。
  /// [timeoutMs] 会被钳制到插件合法范围 [3000, 10000]：越界参数会被插件层静默丢弃，
  /// 原生回落默认 5s，造成"以为 800ms 超时、实际干等 5s"的隐蔽卡顿。
  Future<bool> preLogin({int timeoutMs = 5000}) {
    final now = DateTime.now();
    final cached = _preLoginFuture;
    if (cached != null &&
        now.difference(_preLoginAt ?? now) < const Duration(seconds: 20)) {
      return cached;
    }
    final safeTimeout = timeoutMs.clamp(3000, 10000).toInt();
    _preLoginAt = now;
    // 原生回调可能丢失（运营商网关无响应，日志表现为 requestPreLogin 后无结果）：
    // 外层 8s 兆底超时，避免永久 pending 的 future 被 20s 缓存反复复用，造成“一直取号失败”
    final future = _doPreLogin(timeoutMs: safeTimeout)
        .timeout(const Duration(seconds: 8), onTimeout: () {
      // 超时后同时复位时间戳，防止 20s 窗口内旧时间戳干扰
      _preLoginAt = null;
      return false;
    });
    // 失败不缓存，延迟 1.5s 自动重试 1 次；成功缓存 20s
    _preLoginFuture = future.then<bool>((ok) async {
      if (!ok) {
        _preLoginFuture = null;
        _preLoginAt = null;
        // 自动重试 1 次：运营商网关偶发无响应，延迟后重新取号
        debugPrint('[JVerifyService] preLogin failed, retrying after 1.5s...');
        await Future.delayed(const Duration(milliseconds: 1500));
        final retryOk = await _doPreLogin(timeoutMs: safeTimeout);
        if (!retryOk) {
          debugPrint('[JVerifyService] preLogin retry also failed');
        }
        return retryOk;
      }
      return true;
    });
    return _preLoginFuture!;
  }

  Future<bool> _doPreLogin({required int timeoutMs}) async {
    if (!isSupported || !_initialized) return false;
    try {
      final map = await _jverify.preLogin(timeOut: timeoutMs);
      final ok = map['code'] == codeSuccess;
      debugPrint(
          '[JVerifyService] preLogin result: code=${map['code']} msg=${map['message']} (ok=$ok)',
      );
      return ok;
    } catch (e) {
      debugPrint('[JVerifyService] preLogin error: $e');
      return false;
    }
  }

  /// 确保预取号 token 就绪：已缓存且未过期直接复用，否则重新预取号
  Future<bool> ensurePreLogin() => preLogin(timeoutMs: 5000);

  /// 拉起自绘授权页，执行一键登录
  ///
  /// 成功时返回 accessCode（用于后端验证），用户取消返回空 map，失败抛异常。
  /// 使用纯异步回调模式，避免同步接口超时问题。
  Future<Map<String, String?>?> loginAuth() async {
    if (!isSupported) return null;

    // 只有在未初始化或初始化验证失败时才重新初始化
    _loginAttemptCounter++;
    bool shouldReInit = false;

    if (!_initialized) {
      debugPrint('[JVerifyService] Session #$_loginAttemptCounter: SDK not initialized, will re-init');
      shouldReInit = true;
    } else {
      // 验证当前初始化状态是否有效
      final currentStatus = await isInitSuccess();
      if (!currentStatus) {
        debugPrint('[JVerifyService] Session #$_loginAttemptCounter: SDK initialization failed/crashed, will re-init');
        shouldReInit = true;
      }
    }

    if (shouldReInit) {
      try {
        await init();
      } catch (e) {
        debugPrint('[JVerifyService] Session #$_loginAttemptCounter: Re-init error: $e');
        return null;
      }
    }

    // 等待 SDK 初始化就绪（远程配置加载），最多 5 秒；未就绪直接抛异常，避免硬拉授权页
    bool ready = false;
    for (int i = 0; i < 10 && !ready; i++) {
      ready = await isInitSuccess();
      if (!ready && i < 9) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    if (!ready) {
      debugPrint('[JVerifyService] Session #$_loginAttemptCounter: SDK init not ready after 5s');
      throw JVerifyCarrierException(codeSdkNotReady, 'SDK init not ready');
    }

    // 蜂窝环境前置检查：无 SIM 卡 / 非移动数据网络时立即降级，避免 5s 干等
    if (!await checkVerifyEnable()) {
      debugPrint(
          '[JVerifyService] Session #$_loginAttemptCounter: no cellular env, degrade to other login',
      );
      throw JVerifyCarrierException(codeNoSim, 'Carrier not available');
    }

    // 拉起授权页前确保预取号成功：token 就绪则授权页立即显示脱敏号码、点击即秒回；
    // 预取号失败不再阻断——SDK 授权页内会自动取号（官方推荐路径）
    if (!await ensurePreLogin()) {
      debugPrint(
          '[JVerifyService] Session #$_loginAttemptCounter: preLogin failed, continue to auth page (SDK auto-fetch)',
      );
    }

    // 配置自绘授权页 UI（品牌区 + 脱敏号码 + 同意并登录 + 协议）
    _applyAuthPageUIConfig();

    final completer = Completer<Map<String, String?>>();

    try {
      // 使用同步接口 (loginAuthSyncApi2)
      _jverify.loginAuthSyncApi2(
        autoDismiss: false, // 登录成功后手动关闭，避免授权页残留
        timeout: 10000, // 授权页内登录取号超时 10s（与原生 LoginSettings.setTimeout 对齐）
        // 关闭 SDK 原生短信页跳转：其结果 Dart 侧无法获取，会导致 UI 卡死；
        // 失败统一由 App 页面降级到账号密码/其他登录方式
        enableSms: false,
        loginAuthCallback: (JVListenerEvent event) {
          debugPrint('[JVerifyService] loginAuth callback: ${event.code} - ${event.message}');

          if (completer.isCompleted) return;

          if (event.code == codeLoginSuccess && event.message != null) {
            // 成功：message 是 accessCode；先关闭授权页避免残留盖在 Flutter 之上
            debugPrint('[JVerifyService] Success! Access code: ${event.message!.substring(0, 20)}...');
            try {
              _jverify.dismissLoginAuthView();
            } catch (e) {
              debugPrint('[JVerifyService] dismissLoginAuthView error: $e');
            }

            completer.complete({
              'accessCode': event.message,
              'phoneNumber': null,
              'operator': event.operator,
            });
          } else if (event.code == codeUserCancel1 || event.code == codeUserCancel2) {
            // 用户取消：返回空结果，不视为错误
            debugPrint('[JVerifyService] User cancelled: ${event.code}');
            completer.complete({});
          } else {
            // 运营商预取号超时/失败（2005/2004）及其它明确错误码
            final msg = event.message ?? 'unknown error';
            final msgPrefix = msg.length > 30 ? '${msg.substring(0, 30)}...' : msg;
            debugPrint('[JVerifyService] Carrier error (${event.code}) - message: $msgPrefix...');
            // 抛出异常，由页面决定降级处理（提示并引导其他登录方式）
            completer.completeError(JVerifyCarrierException(event.code ?? -1, event.message));
          }
        },
      );
    } catch (e) {
      debugPrint('[JVerifyService] loginAuth error: $e');
      if (!completer.isCompleted) {
        completer.complete({}); // 返回空 map 而不是 null
      }
    }

    // 设置超时（20 秒，给运营商校验充分时间；弱网下运营商回调可能超过 8 秒，
    // 过短会误报失败——实测电信回调 8.4s 到达，8s 超时误触发）
    try {
      return await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          debugPrint('[JVerifyService] loginAuth timed out after 20s');
          // 超时说明运营商网络无响应，抛异常释放 UI 并引导降级
          throw JVerifyCarrierException(codePreLoginFailed, 'One-click auth timed out');
        },
      );
    } on JVerifyCarrierException catch (e) {
      debugPrint('[JVerifyService] Carrier exception: $e');
      rethrow;
    }
  }

  /// 配置自绘授权页 UI：品牌区（自定义控件）+ 脱敏号码 + 同意并登录 + 协议行
  ///
  /// 坐标单位均为 dp（插件内部按 dp2Pix 换算），参考机型 360dp 宽 × ~800dp 高
  /// （1080px @3x，底部含系统手势条）。布局采用官方推荐的"相对顶部偏移"
  /// 定位方式，显式指定号码/按钮/协议位置，避免 SDK 默认居中布局在异形屏上
  /// 把按钮挤到屏幕边缘；品牌控件与按钮无重叠，防止自定义 View 拦截点击。
  void _applyAuthPageUIConfig() {
    final uiConfig = JVUIConfig();

    // 导航栏：品牌名 + 白色背景 + 返回按钮
    uiConfig.navHidden = false;
    uiConfig.navColor = 0xFFFFFFFF;
    uiConfig.navText = '辰烁科技';
    uiConfig.navTextColor = 0xFF1F2937;
    uiConfig.navTextBold = true;
    uiConfig.navTransparent = false;
    uiConfig.statusBarDarkMode = true;

    // 背景：品牌浅蓝→白渐变（res/drawable/jverify_auth_bg.xml，Android 生效；
    // iOS 同名资源未配置时 imageNamed 返回 nil 安全降级为默认白底）
    uiConfig.authBackgroundImage = 'jverify_auth_bg';

    // Logo：品牌区由自定义控件实现（圆形渐变图标 + 文字），隐藏 SDK 默认 logo
    uiConfig.logoHidden = true;

    // 脱敏号码：居中大字加粗（号码内容由 SDK 注入，如 138****1234）
    uiConfig.numberColor = 0xFF1F2937;
    uiConfig.numberSize = 28;
    uiConfig.numberTextBold = true;
    uiConfig.numFieldOffsetY = 320; // 号码区距屏幕顶部（导航栏下方）

    // 副标语（SDK 默认文案，仅配置样式）
    uiConfig.sloganHidden = false;
    uiConfig.sloganTextColor = 0xFF9CA3AF;
    uiConfig.sloganTextSize = 14;
    uiConfig.sloganOffsetY = 388; // 号码区正下方

    // 登录按钮：大尺寸居中，避开底部手势条与品牌控件；背景为品牌蓝圆角
    // （res/drawable/jverify_login_btn_bg.xml，颜色与 AppColors.primary 对齐）；
    // iOS 端忽略 logBtnBackgroundPath，使用系统默认圆角按钮
    uiConfig.logBtnText = '同意并登录';
    uiConfig.logBtnTextColor = 0xFFFFFFFF;
    uiConfig.logBtnTextSize = 17;
    uiConfig.logBtnTextBold = true;
    uiConfig.logBtnWidth = 312; // 屏宽 360dp - 左右边距 24dp
    uiConfig.logBtnHeight = 50;
    uiConfig.logBtnOffsetY = 470; // 按钮顶部距屏幕顶部
    uiConfig.logBtnBackgroundPath = 'jverify_login_btn_bg';

    // 隐私协议：默认勾选（合规做法——极光要求隐私协议栏常显不可隐藏，默认勾选即可），
    // 贴近屏幕底部避开手势条；勾选框换自定义图标并调大，文字居中避免贴左缘。
    // 协议名/链接使用 privacyItem（jiguang_auth 3.0.3 双端生效）：Android 端
    // clauseName/clauseUrl 在插件中被注释不生效，必须走 privacyItem 才真正渲染链接。
    uiConfig.privacyState = true; // 默认勾选隐私协议（合规）
    uiConfig.privacyHintToast = true;
    // 自定义协议栏文案前缀/后缀：渲染为「登录即代表同意《用户协议》《隐私政策》并同意」
    uiConfig.privacyText = const ['登录即代表同意', '并同意'];
    uiConfig.privacyItem = [
      JVPrivacy('用户协议', 'https://www.csinv.com/terms'),
      JVPrivacy('隐私政策', 'https://www.csinv.com/privacy'),
    ];
    uiConfig.clauseColor = 0xFF1565C0;
    uiConfig.clauseBaseColor = 0xFF6B7280;
    uiConfig.privacyTextSize = 12;
    uiConfig.privacyOffsetY = 72; // 协议行距屏幕底部
    uiConfig.privacyCheckboxSize = 16; // 默认 9dp 过小，调大便于点击
    uiConfig.uncheckedImgPath = 'jverify_checkbox_unchecked'; // res/drawable-xxhdpi
    uiConfig.checkedImgPath = 'jverify_checkbox_checked';
    uiConfig.privacyTextCenterGravity = true; // 协议文字居中，避免贴左缘

    // 品牌区自定义控件：屏宽 360dp 内居中，完整显示不裁剪
    // logo：圆形品牌渐变图标（res/drawable-xxhdpi/jverify_brand_logo.png，
    // 圆角/阴影已预置在 PNG 中）；button 类型仅用于加载图片背景
    final logo = JVCustomWidget('brand_logo', JVCustomWidgetType.button)
      ..left = 148 // (360 - 64) / 2，水平居中
      ..top = 110 // 导航栏下方留白
      ..width = 64
      ..height = 64
      ..btnNormalImageName = 'jverify_brand_logo'
      ..btnPressedImageName = 'jverify_brand_logo'
      ..isClickEnable = false; // 仅展示，不响应点击

    final title = JVCustomWidget('brand_title', JVCustomWidgetType.textView)
      ..left = 70 // (360 - 220) / 2，水平居中
      ..top = 186 // logo 下方
      ..width = 220
      ..height = 44
      ..title = '辰烁科技'
      ..titleFont = 26
      ..titleColor = 0xFF1F2937
      ..textAlignment = JVTextAlignmentType.center;

    final subtitle = JVCustomWidget('brand_subtitle', JVCustomWidgetType.textView)
      ..left = 70
      ..top = 240
      ..width = 220
      ..height = 30
      ..title = '光伏逆变器智能监控平台'
      ..titleFont = 14
      ..titleColor = 0xFF6B7280
      ..textAlignment = JVTextAlignmentType.center;

    _jverify.setCustomAuthorizationView(
      false, // 仅竖屏
      uiConfig,
      widgets: [logo, title, subtitle],
    );
  }
}
