import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/config/app_config.dart';
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
    if (state is! AuthAuthenticated && state is! AuthLoading) {
      context.read<AuthBloc>().add(AuthCheckRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          l10n.myProfile,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthUnauthenticated) context.go('/login');
        },
        builder: (context, state) {
          String displayName = '';
          bool isSystemAdmin = false;
          if (state is AuthAuthenticated) {
            // 优先显示昵称，如果没有昵称则显示手机号
            displayName = state.nickname ?? state.phone;
            isSystemAdmin = state.isSystemAdmin;
          }
          final isLoading = state is AuthLoading || state is AuthInitial;

          return ListView(
            children: [
              _buildHeader(displayName, isSystemAdmin, isLoading, l10n, state is AuthAuthenticated ? state : null),
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
    AppLocalizations l10n,
    AuthAuthenticated? authState,
  ) {
    final roleText = isSystemAdmin ? l10n.roleAdmin : l10n.roleUser;

    // 如果 displayName 为空或仅包含手机号（说明没有昵称），则显示"未设置昵称"
    final hasNickname = authState != null && authState.nickname != null && authState.nickname!.isNotEmpty;
    final displayNameToShow = hasNickname && displayName.isNotEmpty 
      ? displayName 
      : (authState != null ? l10n.nicknameNotSet : l10n.loggedIn);
    final avatarUrl = _getFullAvatarUrl(authState?.avatar);

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
            Container(
              width: 56.w,
              height: 56.w,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16.r),
                image: avatarUrl != null
                    ? DecorationImage(
                        image: NetworkImage(avatarUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: avatarUrl == null
                  // 默认头像插画：未设置头像时的品牌兜底（美术路由 avatar-default）
                  ? Image.asset(
                      CsergyAssets.avatarDefault,
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isLoading)
                    Container(
                      width: 100.w,
                      height: 16.h,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHover,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                    )
                  else
                    Text(
                      displayNameToShow,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  SizedBox(height: 4.h),
                  if (isLoading)
                    Container(
                      width: 60.w,
                      height: 12.h,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHover,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                    )
                  else
                    Text(
                      l10n.roleLabel(roleText),
                      style:
                          TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20.sp,
              color: AppColors.textHint,
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
        Icons.lock_outlined,
        l10n.changePassword,
        () => context.push('/change-password')
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
                    color: AppColors.textSecondary,
                  ),
                  title: Text(
                    item.$2,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    size: 18.sp,
                    color: AppColors.textHint,
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
