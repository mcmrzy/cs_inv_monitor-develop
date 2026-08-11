import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_cropper/image_cropper.dart';
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
  final _emailCodeController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String? _avatarUrl;
  bool _isUploadingAvatar = false;
  bool _isSaving = false;

  // 邮箱验证码倒计时
  int _emailCountdown = 0;
  Timer? _emailTimer;

  static final RegExp _emailRegExp =
      RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');

  bool _isValidEmail(String email) => _emailRegExp.hasMatch(email);

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

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
    _emailCodeController.dispose();
    _emailTimer?.cancel();
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
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (image == null || !mounted) return;

      // 圆形裁剪后再上传
      final CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: image.path,
        maxWidth: 512,
        maxHeight: 512,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            cropStyle: CropStyle.circle,
            lockAspectRatio: true,
            initAspectRatio: CropAspectRatioPreset.square,
            // 隐藏比例工具栏：固定方形裁剪，避免用户改比例破坏圆形头像
            hideBottomControls: true,
          ),
          IOSUiSettings(
            cropStyle: CropStyle.circle,
            aspectRatioLockEnabled: true,
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
        ],
      );
      if (cropped == null || !mounted) return;

      setState(() => _isUploadingAvatar = true);

      final apiClient = getIt<ApiClient>();
      final avatarService = AvatarUploadService(apiClient);
      final url = await avatarService.uploadAvatar(File(cropped.path));

      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _isUploadingAvatar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingAvatar = false);
      _showSnack(e.toString());
    }
  }

  /// 发送邮箱变更验证码
  Future<void> _sendEmailCode() async {
    final email = _emailController.text.trim();
    final l10n = AppLocalizations.of(context)!;
    if (email.isEmpty) {
      _showSnack(l10n.emailRequired);
      return;
    }
    if (!_isValidEmail(email)) {
      _showSnack(l10n.errInvalidEmail);
      return;
    }

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.post(
        '/auth/send-email-change-code',
        data: {'email': email},
      );
      final data = response.data is Map ? response.data as Map : null;
      if (response.statusCode == 200 && data != null && data['code'] == 0) {
        if (!mounted) return;
        setState(() => _emailCountdown = 60);
        _emailTimer?.cancel();
        _emailTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_emailCountdown > 0) {
            setState(() => _emailCountdown--);
          } else {
            timer.cancel();
          }
        });
        _showSnack(l10n.codeSent);
      } else {
        throw Exception(data?['message'] ?? '发送失败');
      }
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final l10n = AppLocalizations.of(context)!;
    final nickname = _nicknameController.text.trim();
    final email = _emailController.text.trim();
    final currentState = context.read<AuthBloc>().state;
    final previousEmail =
        currentState is AuthAuthenticated ? (currentState.email ?? '') : '';

    // 邮箱格式校验（填写时）
    if (email.isNotEmpty && !_isValidEmail(email)) {
      _showSnack(l10n.errInvalidEmail);
      return;
    }

    // 邮箱变更时需通过验证码校验：/auth/profile 不接收邮箱字段，
    // 必须走独立的 change-email 接口（带验证码）
    final emailChanged = email.isNotEmpty && email != previousEmail;
    if (emailChanged) {
      final code = _emailCodeController.text.trim();
      if (code.isEmpty) {
        _showSnack(l10n.fillAllFields);
        return;
      }
      setState(() => _isSaving = true);
      try {
        final apiClient = getIt<ApiClient>();
        final resp = await apiClient.put(
          '/auth/change-email',
          data: {'new_email': email, 'code': code},
        );
        final data = resp.data is Map ? resp.data as Map : null;
        if (resp.statusCode != 200 || data == null || data['code'] != 0) {
          throw Exception(data?['message'] ?? '验证失败');
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        _showSnack(e.toString());
        return;
      }
    }

    if (!mounted) return;
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
              nickname: nickname,
              avatar: _avatarUrl,
            ),
          );

      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
      await subscription.cancel();

      if (!mounted) return;
      final updatedState = context.read<AuthBloc>().state;
      if (updatedState is AuthError) {
        setState(() => _isSaving = false);
        _showSnack(l10n.translateError(updatedState.message));
        return;
      }

      Navigator.of(context).pop(true);
      _showSnack(l10n.profileSaved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnack(e.toString());
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
              SizedBox(height: 12.h),
              // 邮箱验证码（修改邮箱时需验证）
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _emailCodeController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.verificationCode,
                        hintText: l10n.codeHint,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        prefixIcon:
                            const Icon(Icons.lock_outline_rounded, size: 20),
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  SizedBox(
                    height: 50.h,
                    child: FilledButton.tonal(
                      onPressed:
                          _emailCountdown > 0 ? null : _sendEmailCode,
                      child: Text(
                        _emailCountdown > 0
                            ? '${_emailCountdown}s'
                            : l10n.sendCode,
                      ),
                    ),
                  ),
                ],
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
