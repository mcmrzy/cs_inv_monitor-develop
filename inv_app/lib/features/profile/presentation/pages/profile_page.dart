import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/network/api_client.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/profile/data/avatar_upload_service.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ImagePicker _picker = ImagePicker();
  bool _isUploadingAvatar = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    final state = context.read<AuthBloc>().state;
    if (state is! AuthAuthenticated && state is! AuthLoading) {
      context.read<AuthBloc>().add(AuthCheckRequested());
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _isUploadingAvatar = true;
      });

      final apiClient = context.read<ApiClient>();
      final avatarService = AvatarUploadService(apiClient);
      final url = await avatarService.uploadAvatar(File(image.path));

      setState(() {
        _avatarUrl = url;
        _isUploadingAvatar = false;
      });

      // 更新用户信息
      if (mounted) {
        context.read<AuthBloc>().add(AuthUpdateProfileRequested(
          avatar: url,
        ));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.uploadSuccess)),
        );
      }
    } catch (e) {
      setState(() {
        _isUploadingAvatar = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.errorLight,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
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
        backgroundColor: Colors.white,
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthUnauthenticated) context.go('/login');
        },
        builder: (context, state) {
          String phone = '';
          bool isSystemAdmin = false;
          if (state is AuthAuthenticated) {
            phone = state.phone;
            isSystemAdmin = state.isSystemAdmin;
          }
          final isLoading = state is AuthLoading || state is AuthInitial;

          return ListView(
            children: [
              _buildHeader(phone, isSystemAdmin, isLoading, l10n),
              _buildMenuSection(context),
              _buildLogoutButton(context, l10n),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    String phone,
    bool isSystemAdmin,
    bool isLoading,
    AppLocalizations l10n,
  ) {
    final roleText = isSystemAdmin ? l10n.roleAdmin : l10n.roleUser;

    final displayName = phone.isNotEmpty ? phone : l10n.loggedIn;

    return Container(
      padding: EdgeInsets.all(20.w),
      margin: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
            child: Stack(
              children: [
                Container(
                  width: 56.w,
                  height: 56.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16.r),
                    image: _avatarUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_avatarUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _avatarUrl == null
                      ? Icon(
                          Icons.person_rounded,
                          size: 28.sp,
                          color: AppColors.primary,
                        )
                      : null,
                ),
                if (_isUploadingAvatar)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 24.w,
                          height: 24.w,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.w,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 20.w,
                    height: 20.w,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.w),
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      size: 12.w,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
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
                    displayName,
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
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = [
      (Icons.solar_power_rounded, l10n.myStations, () => context.go('/home')),
      (Icons.devices_rounded, l10n.myDevices, () => context.go('/devices')),
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
      (
        Icons.person_outline,
        l10n.editProfile,
        () => context.push('/edit-profile')
      ),
      (
        Icons.settings_outlined,
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
        color: Colors.white,
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.r),
              ),
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
