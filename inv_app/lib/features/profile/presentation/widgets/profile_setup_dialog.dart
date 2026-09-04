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
  final Future<String?> Function()? pickAvatarPath;
  final Future<String?> Function(String sourcePath)? cropAvatarPath;
  final Future<String> Function(String filePath)? uploadAvatarPath;

  const ProfileSetupDialog({
    super.key,
    this.pickAvatarPath,
    this.cropAvatarPath,
    this.uploadAvatarPath,
  });

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
  bool _isSendingEmailCode = false;
  bool _isSaving = false;

  // 邮箱验证码倒计时
  int _emailCountdown = 0;
  Timer? _emailTimer;
  StreamSubscription<AuthState>? _saveSubscription;
  Completer<AuthState>? _saveCompleter;

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
    unawaited(_saveSubscription?.cancel());
    final saveCompleter = _saveCompleter;
    if (saveCompleter != null && !saveCompleter.isCompleted) {
      saveCompleter.complete(const AuthError(message: 'dialog disposed'));
    }
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

  Future<String?> _selectAvatarPath() async {
    final injectedPicker = widget.pickAvatarPath;
    if (injectedPicker != null) return injectedPicker();

    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    return image?.path;
  }

  Future<String?> _cropAvatarPath(String sourcePath) async {
    final injectedCropper = widget.cropAvatarPath;
    if (injectedCropper != null) return injectedCropper(sourcePath);

    // 圆角矩形裁剪后再上传
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      maxWidth: 512,
      maxHeight: 512,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          cropStyle: CropStyle.rectangle,
          lockAspectRatio: true,
          initAspectRatio: CropAspectRatioPreset.square,
          // 隐藏比例工具栏：固定方形裁剪，避免用户改比例破坏头像形状
          hideBottomControls: true,
        ),
        IOSUiSettings(
          cropStyle: CropStyle.rectangle,
          aspectRatioLockEnabled: true,
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
      ],
    );
    return cropped?.path;
  }

  Future<String> _uploadAvatarPath(String filePath) {
    final injectedUploader = widget.uploadAvatarPath;
    if (injectedUploader != null) return injectedUploader(filePath);

    final apiClient = getIt<ApiClient>();
    final avatarService = AvatarUploadService(apiClient);
    return avatarService.uploadAvatar(File(filePath));
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_isUploadingAvatar || _isSaving) return;
    setState(() => _isUploadingAvatar = true);

    try {
      final sourcePath = await _selectAvatarPath();
      if (sourcePath == null || !mounted) return;

      final croppedPath = await _cropAvatarPath(sourcePath);
      if (croppedPath == null || !mounted) return;

      final url = await _uploadAvatarPath(croppedPath);

      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  /// 发送邮箱变更验证码
  Future<void> _sendEmailCode() async {
    if (_isSendingEmailCode ||
        _emailCountdown > 0 ||
        _isSaving ||
        _isUploadingAvatar) {
      return;
    }

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

    setState(() => _isSendingEmailCode = true);
    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.post(
        '/auth/send-email-change-code',
        data: {'email': email},
      );
      final data = response.data is Map ? response.data as Map : null;
      if (response.statusCode == 200 && data != null && data['code'] == 0) {
        if (!mounted) return;
        _startEmailCountdown();
        _showSnack(l10n.codeSent);
      } else {
        throw Exception(data?['message'] ?? '发送失败');
      }
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isSendingEmailCode = false);
      }
    }
  }

  void _startEmailCountdown() {
    _emailTimer?.cancel();
    setState(() => _emailCountdown = 60);
    _emailTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_emailCountdown <= 1) {
        timer.cancel();
        setState(() => _emailCountdown = 0);
        return;
      }
      setState(() => _emailCountdown--);
    });
  }

  Future<void> _handleLateSaveResult(
    Completer<AuthState> completer,
    StreamSubscription<AuthState>? subscription,
    AppLocalizations l10n,
  ) async {
    try {
      final state = await completer.future;
      if (!mounted) return;
      if (state is AuthProfileUpdateSuccess) {
        Navigator.of(context).pop(true);
        _showSnack(l10n.profileSaved);
      } else if (state is AuthProfileUpdateError) {
        _showSnack(l10n.translateError(state.message));
      }
    } finally {
      await subscription?.cancel();
      if (identical(_saveSubscription, subscription)) {
        _saveSubscription = null;
      }
      if (identical(_saveCompleter, completer)) {
        _saveCompleter = null;
      }
    }
  }

  Future<void> _save() async {
    if (_isSaving || _isUploadingAvatar) return;

    final l10n = AppLocalizations.of(context)!;
    final nickname = _nicknameController.text.trim();
    final email = _emailController.text.trim();
    final currentState = context.read<AuthBloc>().state;
    // UI 超时不等于底层请求已取消；Bloc 仍在处理时禁止重复派发更新。
    if (currentState is AuthLoading) {
      _showSnack(l10n.errRequestTimeout);
      return;
    }
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
    }

    setState(() => _isSaving = true);

    if (emailChanged) {
      final code = _emailCodeController.text.trim();
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

    StreamSubscription<AuthState>? subscription;
    Completer<AuthState>? completer;
    try {
      final requestId = AuthProfileRequestId.next();
      final saveCompleter = Completer<AuthState>();
      completer = saveCompleter;
      _saveCompleter = saveCompleter;
      // 监听状态变化，等待更新完成或失败
      subscription = context.read<AuthBloc>().stream.listen((state) {
        final isOwnSuccess = state is AuthProfileUpdateSuccess &&
            state.requestId == requestId;
        final isOwnError = state is AuthProfileUpdateError &&
            state.requestId == requestId;
        if ((isOwnSuccess || isOwnError) && !saveCompleter.isCompleted) {
          saveCompleter.complete(state);
        }
      });
      _saveSubscription = subscription;

      context.read<AuthBloc>().add(
        AuthUpdateProfileRequested(
          requestId: requestId,
          nickname: nickname,
          avatar: _avatarUrl,
        ),
      );

      final updatedState = await saveCompleter.future.timeout(
        const Duration(seconds: 10),
      );

      if (!mounted) return;
      if (updatedState is AuthProfileUpdateError) {
        setState(() => _isSaving = false);
        _showSnack(l10n.translateError(updatedState.message));
        return;
      }

      Navigator.of(context).pop(true);
      _showSnack(l10n.profileSaved);
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnack(l10n.errRequestTimeout);
      final lateCompleter = completer;
      final lateSubscription = subscription;
      if (lateCompleter != null) {
        subscription = null;
        completer = null;
        unawaited(
          _handleLateSaveResult(
            lateCompleter,
            lateSubscription,
            l10n,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnack(e.toString());
    } finally {
      await subscription?.cancel();
      if (identical(_saveSubscription, subscription)) {
        _saveSubscription = null;
      }
      if (identical(_saveCompleter, completer)) {
        _saveCompleter = null;
      }
    }
  }

  void _skip() {
    if (_isSaving || _isUploadingAvatar) return;
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
                  color: AppColor.textSecondary(context),
                  height: 1.5,
                ),
              ),
              SizedBox(height: 20.h),
              // 头像（选填）
              Center(
                child: GestureDetector(
                  onTap: _isUploadingAvatar || _isSaving
                      ? null
                      : _pickAndUploadAvatar,
                  child: Stack(
                    children: [
                      Container(
                        width: 76.w,
                        height: 76.w,
                        decoration: BoxDecoration(
                          // 圆角矩形头像（微信风格）
                          borderRadius: BorderRadius.circular(12.r),
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
                      _isUploadingAvatar || _isSaving
                          ? null
                          : _pickAndUploadAvatar,
                  icon: const Icon(Icons.photo_camera_rounded, size: 16),
                  label: Text(l10n.changeAvatar),
                ),
              ),
              SizedBox(height: 8.h),
              // 昵称（选填）
              TextField(
                controller: _nicknameController,
                enabled: !_isSaving,
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
                enabled: !_isSaving,
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
                      enabled: !_isSaving,
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
                      onPressed: _isSendingEmailCode ||
                              _emailCountdown > 0 ||
                              _isSaving ||
                              _isUploadingAvatar
                          ? null
                          : _sendEmailCode,
                      child: _isSendingEmailCode
                          ? SizedBox(
                              width: 18.w,
                              height: 18.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
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
            onPressed: _isSaving || _isUploadingAvatar ? null : _skip,
            child: Text(l10n.skip),
          ),
          FilledButton(
            onPressed: _isSaving || _isUploadingAvatar ? null : _save,
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
