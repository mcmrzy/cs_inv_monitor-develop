import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  /// 加载超时兆底：超过 4s 仍无数据时展示失败态，提供手动重试入口
  Timer? _loadTimeoutTimer;
  bool _loadTimedOut = false;
  int _autoRetryCount = 0; // 自动重试计数，上限 2 次

  /// 将相对路径的头像URL转换为完整URL
  String? _getFullAvatarUrl(String? avatar) {
    if (avatar == null || avatar.isEmpty) return null;
    
    // 如果已经是完整URL，直接返回
    if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
      return avatar;
    }
    
    // 从 apiBaseUrl 提取服务器基础URL（去掉 /api/v1）
    const baseUrl = AppConfig.apiBaseUrl;
    final serverBase = baseUrl.replaceAll(RegExp(r'/api/v1$'), '');
    
    // 确保路径以 / 开头
    final path = avatar.startsWith('/') ? avatar : '/$avatar';
    
    return '$serverBase$path';
  }

  @override
  void initState() {
    super.initState();
    final state = context.read<AuthBloc>().state;
    if (state is! AuthLoading && state is! AuthInitial) {
      context.read<AuthBloc>().add(AuthCheckRequested());
    }
    _startLoadTimeout();
  }

  @override
  void dispose() {
    _loadTimeoutTimer?.cancel();
    super.dispose();
  }

  /// 启动加载超时计时：4s 后若仍处于加载态，自动重试最多 2 次，之后显示失败态
  void _startLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final state = context.read<AuthBloc>().state;
      if (state is AuthLoading ||
          state is AuthInitial ||
          (state is AuthAuthenticated && state.user == null)) {
        // 自动重试最多 2 次
        if (_autoRetryCount < 2) {
          _autoRetryCount++;
          _retryLoad();
        } else {
          setState(() => _loadTimedOut = true);
        }
      }
    });
  }

  /// 手动重试：重新走 AuthCheckRequested（本地缓存乐观进入 + 后台刷新资料）
  void _retryLoad() {
    _loadTimeoutTimer?.cancel();
    if (_loadTimedOut) setState(() => _loadTimedOut = false);
    context.read<AuthBloc>().add(AuthCheckRequested());
    _startLoadTimeout();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          l10n.myProfile,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: AppColor.textPrimary(context),
          ),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          // 离网/本地直连模式（含 guest 入口）下不强制跳登录页，
          // 未登录使用本地功能时以「离线用户」形态展示
          if (state is AuthUnauthenticated &&
              !getIt<ConnectionModeService>().isLocal) {
            context.go('/login');
          }
          // 资料加载成功：取消超时兆底，复位失败态和重试计数
          if (state is AuthAuthenticated && state.user != null) {
            _loadTimeoutTimer?.cancel();
            _autoRetryCount = 0;
            if (_loadTimedOut) setState(() => _loadTimedOut = false);
          }
        },
        builder: (context, state) {
          String displayName = '';
          bool isSystemAdmin = false;
          bool isGuestLocalMode = false;
          
          if (state is AuthAuthenticated) {
            // 优先显示昵称，如果没有昵称则显示手机号
            displayName = state.nickname ?? state.phone;
            isSystemAdmin = state.isSystemAdmin;
          } else {
            // 未登录状态检查是否处于 Guest Local Mode
            final connectionModeService = getIt<ConnectionModeService>();
            isGuestLocalMode = connectionModeService.isGuestLocalMode;
            if (isGuestLocalMode) {
              displayName = '离线用户';
            } else {
              displayName = '未登录';
            }
          }
          
          final isLoading = state is AuthLoading || state is AuthInitial;
          // 加载超时 / 出错（如缓存缺失且网络差）时展示失败态 + 手动重试
          final showLoadError = _loadTimedOut ||
              (state is AuthError && !state.isProfileUpdateTerminal);

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _buildHeader(
                displayName,
                isSystemAdmin,
                isLoading,
                showLoadError,
                l10n,
                state is AuthAuthenticated ? state : null,
              ),
              _buildMenuSection(context),
              _buildLogoutButton(context, l10n),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    String displayName,
    bool isSystemAdmin,
    bool isLoading,
    bool showLoadError,
    AppLocalizations l10n,
    AuthAuthenticated? authState,
  ) {
    final roleText = isSystemAdmin ? l10n.roleAdmin : l10n.roleUser;

    // 如果 displayName 为空或仅包含手机号（说明没有昵称），则显示"未设置昵称"
    final hasNickname = authState != null && authState.nickname != null && authState.nickname!.isNotEmpty;
    final connectionModeService = getIt<ConnectionModeService>();
    final isGuestLocalMode = connectionModeService.isGuestLocalMode;
    
    final displayNameToShow = (hasNickname && displayName.isNotEmpty) 
      ? displayName 
      : (isGuestLocalMode
        ? '离线用户'  // Guest Local Mode 显示固定文本
        : (authState != null ? l10n.nicknameNotSet : l10n.loggedIn));
    final avatarUrl = _getFullAvatarUrl(authState?.avatar);
    
    // 判断是否应该使用默认头像
    final shouldUseDefaultAvatar = authState == null || authState.user == null;

    return GestureDetector(
      onTap: () => context.push('/edit-profile'),
      child: Container(
        padding: EdgeInsets.all(20.w),
        margin: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: AppColor.surfaceContainer(context),
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Row(
          children: [
            // 头像：加载中时显示加载指示器，避免闪烁默认头像
            // 圆角矩形（微信风格），不再使用圆形
            Container(
              width: 56.w,
              height: 56.w,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: isLoading && avatarUrl == null
                  ? Center(
                      child: SizedBox(
                        width: 24.w,
                        height: 24.w,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : (shouldUseDefaultAvatar || showLoadError
                      ? Image.asset(
                          CsergyAssets.avatarDefault,
                          fit: BoxFit.cover,
                          cacheWidth: 256,
                        )
                      : (avatarUrl != null
                          ? Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Image.asset(
                                    CsergyAssets.avatarDefault,
                                    fit: BoxFit.cover,
                                    cacheWidth: 256,
                                  ),
                            )
                          : Image.asset(
                              CsergyAssets.avatarDefault,
                              fit: BoxFit.cover,
                              cacheWidth: 256,
                            ))),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showLoadError)
                    // 加载失败态：小图标 + 提示 + 点击重试
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 18.sp,
                              color: AppColors.errorLight,
                            ),
                            SizedBox(width: 6.w),
                            Expanded(
                              child: Text(
                                l10n.loadFailed,
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: AppColor.textSecondary(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4.h),
                        TextButton.icon(
                          onPressed: _retryLoad,
                          icon: Icon(
                            Icons.refresh_rounded,
                            size: 16.sp,
                            color: AppColors.primary,
                          ),
                          label: Text(
                            l10n.retry,
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 8.w),
                            minimumSize: Size(0, 28.h),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    )
                  else if (isLoading) ...[
                    Container(
                      width: 100.w,
                      height: 16.h,
                      decoration: BoxDecoration(
                        color: AppColor.surfaceHover(context),
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Container(
                      width: 60.w,
                      height: 12.h,
                      decoration: BoxDecoration(
                        color: AppColor.surfaceHover(context),
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                    ),
                  ] else ...[ // 正常显示状态
                    // 离网模式提示标签（统一警告色，暗色模式自适应）
                    if (isGuestLocalMode)
                      Container(
                        margin: EdgeInsets.only(bottom: 6.h),
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6.r),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.4),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.wifi_off_rounded,
                              size: 12.sp,
                              color: AppColors.warning,
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              l10n.localMode,
                              style: TextStyle(
                                fontSize: 10.sp,
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    Text(
                      displayNameToShow,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      l10n.roleLabel(roleText),
                      style:
                          TextStyle(fontSize: 13.sp, color: AppColor.textHint(context)),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20.sp,
              color: AppColor.textHint(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = [
      (
        Icons.system_update_alt_rounded,
        l10n.otaTitle,
        () => context.push('/ota')
      ),
      (
        Icons.notifications_outlined,
        l10n.messageNotifySettings,
        () => context.push('/notify-settings')
      ),
      (Icons.settings_outlined,
        l10n.systemSettings,
        () => context.push('/settings')
      ),
      (
        Icons.help_outline_rounded,
        l10n.helpCenter,
        () => context.push('/help-center')
      ),
      (
        Icons.history_rounded,
        l10n.operationHistory,
        () => context.push('/operation-history')
      ),
      (
        Icons.cloud_off_rounded,
        l10n.offlineModeSettings,
        () => context.push('/offline-mode-settings')
      ),
      (Icons.info_outline, l10n.aboutUs, () => context.push('/about')),
    ];

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      padding: EdgeInsets.symmetric(vertical: 4.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: items
              .map(
                (item) => ListTile(
                  leading: Icon(
                    item.$1,
                    size: 22.sp,
                    color: AppColor.textSecondary(context),
                  ),
                  title: Text(
                    item.$2,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    size: 18.sp,
                    color: AppColor.textHint(context),
                  ),
                  onTap: item.$3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: OutlinedButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.logout),
              content: Text(l10n.logoutConfirm),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.read<AuthBloc>().add(AuthLogoutRequested());
                    // 主动回登录页，不依赖 Bloc 状态流：guest 离网模式下登出前
                    // 状态本就是未登录，弱网时云端登出调用还可能长时间挂起；
                    // 本地清理在后台继续，跳转幂等（守卫见已在 /login 不重复跳）
                    context.go('/login');
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.errorLight,
                  ),
                  child: Text(l10n.confirm),
                ),
              ],
            ),
          );
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.errorLight,
          side: BorderSide(color: AppColors.errorLight.withValues(alpha: 0.2)),
          padding: EdgeInsets.symmetric(vertical: 14.h),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
        ),
        child: Text(l10n.logout),
      ),
    );
  }
}
