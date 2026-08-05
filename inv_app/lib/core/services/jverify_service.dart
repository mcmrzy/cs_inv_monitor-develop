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
  static final JVerifyService _instance = JVerifyService._internal();
  factory JVerifyService() => _instance;
  JVerifyService._internal();

  final Jverify _jverify = Jverify();
  bool _initialized = false;
  int _loginAttemptCounter = 0; // 记录登录尝试次数，防止重复初始化

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
  Future<bool> preLogin({int timeoutMs = 5000}) async {
    if (!isSupported || !_initialized) return false;
    try {
      final map = await _jverify.preLogin(timeOut: timeoutMs);
      return map['code'] == 7000;
    } catch (e) {
      debugPrint('[JVerifyService] preLogin error: $e');
      return false;
    }
  }

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
      throw JVerifyCarrierException(6012, 'SDK init not ready');
    }

    // 配置自绘授权页 UI（品牌区 + 脱敏号码 + 同意并登录 + 协议）
    _applyAuthPageUIConfig();

    final completer = Completer<Map<String, String?>>();

    try {
      // 使用同步接口 (loginAuthSyncApi2)
      _jverify.loginAuthSyncApi2(
        autoDismiss: false, // 登录成功后手动关闭，避免授权页残留
        // 关闭 SDK 原生短信页跳转：其结果 Dart 侧无法获取，会导致 UI 卡死；
        // 失败统一由 App 页面降级到账号密码/其他登录方式
        enableSms: false,
        loginAuthCallback: (JVListenerEvent event) {
          debugPrint('[JVerifyService] loginAuth callback: ${event.code} - ${event.message}');

          if (completer.isCompleted) return;

          if (event.code == 6000 && event.message != null) {
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
          } else if (event.code == 8001 || event.code == 9000) {
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
          throw JVerifyCarrierException(2005, 'One-click auth timed out');
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

    // Logo：品牌区由自定义控件实现，隐藏 SDK 默认 logo
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

    // 登录按钮：大尺寸居中，避开底部手势条与品牌控件
    uiConfig.logBtnText = '同意并登录';
    uiConfig.logBtnTextColor = 0xFFFFFFFF;
    uiConfig.logBtnTextSize = 17;
    uiConfig.logBtnTextBold = true;
    uiConfig.logBtnWidth = 312; // 屏宽 360dp - 左右边距 24dp
    uiConfig.logBtnHeight = 50;
    uiConfig.logBtnOffsetY = 470; // 按钮顶部距屏幕顶部

    // 隐私协议：贴近屏幕底部，避开系统手势条；勾选框换自定义图标并调大，
    // 文字居中避免贴屏幕左缘
    uiConfig.privacyState = false;
    uiConfig.privacyHintToast = true;
    uiConfig.clauseName = '用户协议';
    uiConfig.clauseUrl = 'https://www.csinv.com/terms';
    uiConfig.clauseNameTwo = '隐私政策';
    uiConfig.clauseUrlTwo = 'https://www.csinv.com/privacy';
    uiConfig.clauseColor = 0xFF1565C0;
    uiConfig.clauseBaseColor = 0xFF6B7280;
    uiConfig.privacyTextSize = 12;
    uiConfig.privacyOffsetY = 72; // 协议行距屏幕底部
    uiConfig.privacyCheckboxSize = 16; // 默认 9dp 过小，调大便于点击
    uiConfig.uncheckedImgPath = 'jverify_checkbox_unchecked'; // res/drawable-xxhdpi
    uiConfig.checkedImgPath = 'jverify_checkbox_checked';
    uiConfig.privacyTextCenterGravity = true; // 协议文字居中，避免贴左缘

    // 品牌区自定义控件：屏宽 360dp 内居中，完整显示不裁剪
    final title = JVCustomWidget('brand_title', JVCustomWidgetType.textView)
      ..left = 70 // (360 - 220) / 2，水平居中
      ..top = 150 // 导航栏下方留白
      ..width = 220
      ..height = 44
      ..title = '辰烁科技'
      ..titleFont = 26
      ..titleColor = 0xFF1F2937
      ..textAlignment = JVTextAlignmentType.center;

    final subtitle = JVCustomWidget('brand_subtitle', JVCustomWidgetType.textView)
      ..left = 70
      ..top = 204
      ..width = 220
      ..height = 30
      ..title = '光伏逆变器智能监控平台'
      ..titleFont = 14
      ..titleColor = 0xFF6B7280
      ..textAlignment = JVTextAlignmentType.center;

    _jverify.setCustomAuthorizationView(
      false, // 仅竖屏
      uiConfig,
      widgets: [title, subtitle],
    );
  }
}
