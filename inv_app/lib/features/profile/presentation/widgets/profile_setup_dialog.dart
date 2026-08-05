import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/network/api_client.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/profile/data/avatar_upload_service.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 完善个人信息弹窗
/// 一键登录自动注册的用户（昵称为空）首次进入 App 时弹出。
/// 昵称 / 邮箱 / 头像均为选填，可保存或跳过。
class ProfileSetupDialog extends StatefulWidget {
  const ProfileSetupDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ProfileSetupDialog(),
    );
  }

  @override
  State<ProfileSetupDialog> createState() => _ProfileSetupDialogState();
}

class _ProfileSetupDialogState extends State<ProfileSetupDialog> {
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String? _avatarUrl;
  bool _isUploadingAvatar = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AuthBloc>().state;
    if (state is AuthAuthenticated) {
      _nicknameController.text = state.nickname ?? '';
      _emailController.text = state.email ?? '';
      _avatarUrl = state.avatar;
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// 将相对路径的头像URL转换为完整URL
  String? _getFullAvatarUrl(String? avatar) {
    if (avatar == null || avatar.isEmpty) return null;
    if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
      return avatar;
    }
    // 从 apiBaseUrl 提取服务器基础URL（去掉 /api/v1）
    const baseUrl = AppConfig.apiBaseUrl;
    final serverBase = baseUrl.replaceAll(RegExp(r'/api/v1$'), '');
    final path = avatar.startsWith('/') ? avatar : '/$avatar';
    return '$serverBase$path';
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;

      setState(() => _isUploadingAvatar = true);

      final apiClient = getIt<ApiClient>();
      final avatarService = AvatarUploadService(apiClient);
      final url = await avatarService.uploadAvatar(File(image.path));

      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _isUploadingAvatar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final completer = Completer<void>();
      // 监听状态变化，等待更新完成或失败
      final subscription = context.read<AuthBloc>().stream.listen((state) {
        if (state is AuthAuthenticated || state is AuthError) {
          if (!completer.isCompleted) completer.complete();
        }
      });

      context.read<AuthBloc>().add(
            AuthUpdateProfileRequested(
              nickname: _nicknameController.text.trim(),
              email: _emailController.text.trim(),
              avatar: _avatarUrl,
            ),
          );

      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
      await subscription.cancel();

      if (!mounted) return;
      final currentState = context.read<AuthBloc>().state;
      if (currentState is AuthError) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.translateError(
                currentState.message,
              ),
            ),
          ),
        );
        return;
      }

      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.profileSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  void _skip() {
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l10n.completeProfileTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.completeProfileDesc,
                style: TextStyle(
                  fontSize: 13.sp,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 20.h),
              // 头像（选填）
              Center(
                child: GestureDetector(
                  onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                  child: Stack(
                    children: [
                      Container(
                        width: 76.w,
                        height: 76.w,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.1),
                          image: _getFullAvatarUrl(_avatarUrl) != null
                              ? DecorationImage(
                                  image: NetworkImage(
                                    _getFullAvatarUrl(_avatarUrl)!,
                                  ),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _getFullAvatarUrl(_avatarUrl) == null
                            ? Icon(
                                Icons.person_rounded,
                                size: 36.sp,
                                color: AppColors.primary,
                              )
                            : null,
                      ),
                      if (_isUploadingAvatar)
                        const Positioned.fill(
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              Center(
                child: TextButton.icon(
                  onPressed:
                      _isUploadingAvatar ? null : _pickAndUploadAvatar,
                  icon: const Icon(Icons.photo_camera_rounded, size: 16),
                  label: Text(l10n.changeAvatar),
                ),
              ),
              SizedBox(height: 8.h),
              // 昵称（选填）
              TextField(
                controller: _nicknameController,
                maxLength: 30,
                decoration: InputDecoration(
                  labelText: l10n.nickname,
                  hintText: l10n.clickToSetNickname,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                ),
              ),
              SizedBox(height: 12.h),
              // 邮箱（选填）
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: l10n.email,
                  hintText: l10n.clickToSetEmail,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _skip,
            child: Text(l10n.skip),
          ),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? SizedBox(
                    width: 18.w,
                    height: 18.w,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
