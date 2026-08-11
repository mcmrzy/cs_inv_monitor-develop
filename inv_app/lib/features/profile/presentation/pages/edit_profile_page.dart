import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/data/china_regions.dart';
import 'package:inv_app/core/data/country_name_mapping.dart';
import 'package:inv_app/core/data/province_name_mapping.dart';
import 'package:inv_app/core/data/regions_data.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/network/api_client.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/profile/data/avatar_upload_service.dart';
import 'package:inv_app/features/station/presentation/widgets/region_picker_routes.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nicknameController;
  late TextEditingController _emailController;
  late TextEditingController _countryController;
  late TextEditingController _regionController;
  late TextEditingController _phoneController;
  bool _isUploadingAvatar = false;
  String? _avatarUrl;
  final ImagePicker _picker = ImagePicker();

  // 邮箱验证码相关状态
  int _emailCountdown = 0;
  Timer? _emailTimer;

  // 手机验证码相关状态
  int _phoneCountdown = 0;
  Timer? _phoneTimer;

  /// 将相对路径的头像URL转换为完整URL
  String _getFullAvatarUrl(String? avatar) {
    if (avatar == null || avatar.isEmpty) return '';

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
    String nickname = '';
    String email = '';
    String country = '';
    String region = '';
    String phone = '';

    if (state is AuthAuthenticated) {
      nickname = state.nickname ?? '';
      email = state.email ?? '';
      country = state.country ?? '';
      region = state.regionName ?? '';
      phone = state.phone;
      _avatarUrl = state.avatar;
    }

    _nicknameController = TextEditingController(text: nickname);
    _emailController = TextEditingController(text: email);
    _countryController = TextEditingController(text: country);
    _regionController = TextEditingController(text: region);
    _phoneController = TextEditingController(text: phone);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _countryController.dispose();
    _regionController.dispose();
    _phoneController.dispose();
    _emailTimer?.cancel();
    _phoneTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    if (!await _ensureAuthenticated()) return;
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );

      if (image == null) return;

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

      if (cropped == null) return;

      setState(() {
        _isUploadingAvatar = true;
      });

      final apiClient = getIt<ApiClient>();
      final avatarService = AvatarUploadService(apiClient);
      final url = await avatarService.uploadAvatar(File(cropped.path));

      setState(() {
        _avatarUrl = url;
        _isUploadingAvatar = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.uploadSuccess)),
        );
      }

      // 单步保存：头像上传成功后立即提交 profile
      await _submitPartial(avatar: url);
    } catch (e) {
      setState(() {
        _isUploadingAvatar = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
        );
      }
    }
  }

  /// 单步保存：只提交非空字段（昵称/地区/头像任一修改后即时保存）。
  /// 成功返回 true（SnackBar 即时确认），失败返回 false——不关闭页面、不清空输入，可重试。
  Future<bool> _submitPartial({
    String? nickname,
    String? country,
    String? regionName,
    String? avatar,
  }) async {
    if (!await _ensureAuthenticated()) return false;
    if (!mounted) return false;
    final l10n = AppLocalizations.of(context)!;

    try {
      final completer = Completer<void>();

      // 创建一个临时的监听器来等待状态变化
      final subscription = context.read<AuthBloc>().stream.listen((state) {
        if (state is AuthAuthenticated || state is AuthError) {
          completer.complete();
        }
      });

      context.read<AuthBloc>().add(
            AuthUpdateProfileRequested(
              nickname: nickname,
              country: country,
              regionName: regionName,
              avatar: avatar,
            ),
          );

      // 等待 AuthBloc 处理完成
      await completer.future;
      await subscription.cancel();

      if (!mounted) return false;
      final currentState = context.read<AuthBloc>().state;
      if (currentState is AuthAuthenticated) {
        // 更新成功：即时确认（不关闭页面）
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.success)),
        );
        return true;
      }
      if (currentState is AuthError) {
        // 更新失败：提示原因，输入保留可重试
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(currentState.message)),
        );
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return false;
    }
  }

  /// 显示编辑昵称弹窗
  void _showEditNicknameDialog(AppLocalizations l10n) {
    final nicknameController = TextEditingController(text: _nicknameController.text);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标
              Container(
                width: 64.w,
                height: 64.w,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_outline,
                  size: 32.sp,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                l10n.nickname,
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 24.h),
              // 昵称输入
              TextField(
                controller: nicknameController,
                decoration: InputDecoration(
                  labelText: l10n.nickname,
                  hintText: l10n.nickname,
                  prefixIcon: Icon(Icons.person, size: 20.sp),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 14.h,
                  ),
                ),
              ),
              SizedBox(height: 24.h),
              // 按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _nicknameController.text = nicknameController.text;
                        });
                        Navigator.pop(context);
                        // 单步保存：昵称修改后立即提交
                        _submitPartial(nickname: nicknameController.text);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text(l10n.confirm),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示修改手机号弹窗（现代化UI）
  Future<void> _showChangePhoneDialog(AppLocalizations l10n) async {
    final newPhoneController = TextEditingController();
    final codeController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Container(
            padding: EdgeInsets.all(24.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 图标
                Container(
                  width: 64.w,
                  height: 64.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.phone_android,
                    size: 32.sp,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  l10n.changePhone,
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  '请输入新的手机号码',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 24.h),
                // 手机号输入
                TextField(
                  controller: newPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: l10n.newPhone,
                    hintText: l10n.phoneHint,
                    prefixIcon: Icon(Icons.phone, size: 20.sp),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 14.h,
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                // 验证码输入
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: codeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.verificationCode,
                          hintText: l10n.codeHint,
                          prefixIcon: Icon(Icons.lock_outline, size: 20.sp),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16.w,
                            vertical: 14.h,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    SizedBox(
                      height: 52.h,
                      child: ElevatedButton(
                        onPressed: _phoneCountdown > 0
                            ? null
                            : () => _sendPhoneCodeForDialog(
                                  newPhoneController.text,
                                  setDialogState,
                                ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _phoneCountdown > 0
                              ? AppColors.offline
                              : AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                        ),
                        child: Text(
                          _phoneCountdown > 0
                              ? '${_phoneCountdown}s'
                              : l10n.sendCode,
                          style: TextStyle(fontSize: 13.sp),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24.h),
                // 按钮
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _verifyPhoneCode(
                              newPhoneController.text,
                              codeController.text,
                            ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        child: Text(l10n.confirm),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // 弹窗关闭（确认/取消/返回键/遮罩）后取消倒计时，避免定时器对已销毁弹窗调用 setState
    _phoneTimer?.cancel();
    _phoneCountdown = 0;
  }

  /// 检查登录态；未登录时提示并跳转登录页，返回 false 阻止操作
  Future<bool> _ensureAuthenticated() async {
    final token = await getIt<StorageService>().getToken();
    if (token != null && token.isNotEmpty) return true;

    if (mounted) {
      // 关闭可能残留的弹窗，避免跳转后被遮挡
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('登录已过期，请重新登录'),
        ),
      );
      context.go('/login');
    }
    return false;
  }

  /// 发送手机验证码（弹窗内使用）
  Future<void> _sendPhoneCodeForDialog(
    String phone,
    StateSetter setDialogState,
  ) async {
    if (!await _ensureAuthenticated()) return;
    if (!mounted) return;
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.phoneRequired),
        ),
      );
      return;
    }

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.post(
        '/auth/send-phone-code',
        data: {'phone': phone},
      );

      if (response.statusCode == 200 && response.data['code'] == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.codeSent),
            ),
          );
        }

        // 开始倒计时
        setDialogState(() {
          _phoneCountdown = 60;
        });
        _phoneTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_phoneCountdown > 0) {
            setDialogState(() {
              _phoneCountdown--;
            });
          } else {
            timer.cancel();
          }
        });
      } else {
        throw Exception(response.data['message'] ?? '发送失败');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
        );
      }
    }
  }

  /// 验证手机验证码
  Future<void> _verifyPhoneCode(String newPhone, String code) async {
    if (!await _ensureAuthenticated()) return;
    if (!mounted) return;
    if (newPhone.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.fillAllFields),
        ),
      );
      return;
    }

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.put(
        '/auth/change-phone',
        data: {
          'new_phone': newPhone,
          'code': code,
        },
      );

      if (response.statusCode == 200 && response.data['code'] == 0) {
        // 关闭弹窗并取消倒计时，避免弹窗销毁后定时器回调报错
        _phoneTimer?.cancel();
        _phoneCountdown = 0;

        if (mounted) {
          Navigator.pop(context);
          setState(() {
            _phoneController.text = newPhone;
          });
          // 同步 AuthBloc 状态与本地缓存，重新打开设置页显示新手机号
          context.read<AuthBloc>().add(AuthContactChanged(newPhone: newPhone));
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.phoneChanged),
            ),
          );
        }
      } else {
        throw Exception(response.data['message'] ?? '验证失败');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
        );
      }
    }
  }

  /// 显示修改邮箱弹窗（现代化UI）
  Future<void> _showChangeEmailDialog(AppLocalizations l10n) async {
    final newEmailController = TextEditingController();
    final codeController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Container(
            padding: EdgeInsets.all(24.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 图标
                Container(
                  width: 64.w,
                  height: 64.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.email_outlined,
                    size: 32.sp,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  l10n.changeEmail,
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  '请输入新的邮箱地址',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 24.h),
                // 邮箱输入
                TextField(
                  controller: newEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l10n.newEmail,
                    hintText: l10n.emailHint,
                    prefixIcon: Icon(Icons.email, size: 20.sp),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 14.h,
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                // 验证码输入
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: codeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.verificationCode,
                          hintText: l10n.codeHint,
                          prefixIcon: Icon(Icons.lock_outline, size: 20.sp),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16.w,
                            vertical: 14.h,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    SizedBox(
                      height: 52.h,
                      child: ElevatedButton(
                        onPressed: _emailCountdown > 0
                            ? null
                            : () => _sendEmailCodeForDialog(
                                  newEmailController.text,
                                  setDialogState,
                                ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _emailCountdown > 0
                              ? AppColors.offline
                              : AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                        ),
                        child: Text(
                          _emailCountdown > 0
                              ? '${_emailCountdown}s'
                              : l10n.sendCode,
                          style: TextStyle(fontSize: 13.sp),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24.h),
                // 按钮
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _verifyEmailCode(
                              newEmailController.text,
                              codeController.text,
                            ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        child: Text(l10n.confirm),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // 弹窗关闭（确认/取消/返回键/遮罩）后取消倒计时，避免定时器对已销毁弹窗调用 setState
    _emailTimer?.cancel();
    _emailCountdown = 0;
  }

  /// 发送邮箱验证码（弹窗内使用）
  Future<void> _sendEmailCodeForDialog(
    String email,
    StateSetter setDialogState,
  ) async {
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.emailRequired),
        ),
      );
      return;
    }

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.post(
        '/auth/send-email-change-code',
        data: {'email': email},
      );

      if (response.statusCode == 200 && response.data['code'] == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.codeSent),
            ),
          );
        }

        // 开始倒计时
        setDialogState(() {
          _emailCountdown = 60;
        });
        _emailTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_emailCountdown > 0) {
            setDialogState(() {
              _emailCountdown--;
            });
          } else {
            timer.cancel();
          }
        });
      } else {
        throw Exception(response.data['message'] ?? '发送失败');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
        );
      }
    }
  }

  /// 验证邮箱验证码
  Future<void> _verifyEmailCode(String newEmail, String code) async {
    if (newEmail.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.fillAllFields),
        ),
      );
      return;
    }

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.put(
        '/auth/change-email',
        data: {
          'new_email': newEmail,
          'code': code,
        },
      );

      if (response.statusCode == 200 && response.data['code'] == 0) {
        // 关闭弹窗并取消倒计时，避免弹窗销毁后定时器回调报错
        _emailTimer?.cancel();
        _emailCountdown = 0;

        if (mounted) {
          Navigator.pop(context);
          setState(() {
            _emailController.text = newEmail;
          });
          // 同步 AuthBloc 状态与本地缓存，重新打开设置页显示新邮箱
          context.read<AuthBloc>().add(AuthContactChanged(newEmail: newEmail));
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.emailChanged),
            ),
          );
        }
      } else {
        throw Exception(response.data['message'] ?? '验证失败');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
        );
      }
    }
  }

  /// 显示地区选择器（两步流程：洲+国家 -> 省/市/区，与电站地址选择共用组件）
  Future<void> _showRegionPicker(AppLocalizations l10n) async {
    // 第一步：选择洲+国家
    final countryResult = await Navigator.push<Map<String, String>>(
      context,
      ContinentCountryPickerRoute(),
    );
    if (countryResult == null || !mounted) return;

    final selectedCountry = countryResult['country'] ?? '中国';

    // 第二步：选择省/市/区（三级选择器，与电站地址选择一致）
    final regionResult = await Navigator.push<Map<String, String>>(
      context,
      RegionPickerRoute(
        provinces: _provincesFor(selectedCountry),
        citiesFn: (p) {
          if (selectedCountry != '中国') return [];
          final m = chinaRegions[p];
          if (m == null) return [];
          return m.keys.toList();
        },
        districtsFn: (p, c) {
          if (selectedCountry != '中国') return [];
          return chinaRegions[p]?[c] ?? [];
        },
      ),
    );

    if (regionResult != null) {
      setState(() {
        _countryController.text = selectedCountry;
        final regionParts = <String>[];
        if (regionResult['province']?.isNotEmpty == true) {
          regionParts.add(regionResult['province']!);
        }
        if (regionResult['city']?.isNotEmpty == true) {
          regionParts.add(regionResult['city']!);
        }
        if (regionResult['district']?.isNotEmpty == true) {
          regionParts.add(regionResult['district']!);
        }
        _regionController.text = regionParts.join(' ');
      });
      // 单步保存：地区修改后立即提交
      await _submitPartial(
        country: selectedCountry,
        regionName: _regionController.text,
      );
    } else {
      // 用户在第二步取消，只设置国家
      setState(() {
        _countryController.text = selectedCountry;
        _regionController.text = '';
      });
      // 单步保存：仅国家变更，立即提交
      await _submitPartial(country: selectedCountry, regionName: '');
    }
  }

  /// 按国家返回省份列表：中国取内置三级数据，其他国家映射英文名后取全球数据
  List<String> _provincesFor(String country) {
    if (country == '中国') {
      return chinaRegions.keys.toList();
    }
    // 将中文国家名映射到英文名，然后从 globalRegions 获取省份数据
    final englishName = getEnglishCountryName(country);
    final provincesList = globalRegions[englishName] ?? [];
    // 将英文省份名翻译为中文
    return provincesList
        .map((p) => getLocalizedProvinceName(englishName, p))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          l10n.editProfile,
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16.w),
          children: [
            // 即时保存提示
            Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: Text(
                l10n.str('profile_auto_save_hint'),
                style: TextStyle(
                  fontSize: 13.sp,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            _buildAvatarSection(l10n),
            SizedBox(height: 16.h),
            // 所有字段放在一个卡片中
            Container(
              decoration: BoxDecoration(
                color: AppColor.surfaceContainer(context),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Column(
                children: [
                  _buildReadOnlyField(
                    label: l10n.nickname,
                    value: _nicknameController.text,
                    icon: Icons.person_outline,
                    onEdit: () => _showEditNicknameDialog(l10n),
                    l10n: l10n,
                  ),
                  Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                  _buildReadOnlyField(
                    label: l10n.phone,
                    value: _phoneController.text,
                    icon: Icons.phone_outlined,
                    onEdit: () => _showChangePhoneDialog(l10n),
                    l10n: l10n,
                  ),
                  Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                  _buildReadOnlyField(
                    label: l10n.email,
                    value: _emailController.text,
                    icon: Icons.email_outlined,
                    onEdit: () => _showChangeEmailDialog(l10n),
                    l10n: l10n,
                  ),
                  Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                  _buildRegionSelector(l10n),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarSection(AppLocalizations l10n) {
    final state = context.read<AuthBloc>().state;
    final avatarUrl = _getFullAvatarUrl(
      _avatarUrl ?? (state is AuthAuthenticated ? state.avatar : null),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(16.r),
      ),
      padding: EdgeInsets.all(20.w),
      child: Column(
        children: [
          GestureDetector(
            onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
            child: Stack(
              children: [
                Container(
                  width: 80.w,
                  height: 80.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    image: avatarUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(avatarUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: avatarUrl.isEmpty
                      ? Icon(
                          Icons.person_rounded,
                          size: 40.sp,
                          color: AppColors.primary,
                        )
                      : null,
                ),
                if (_isUploadingAvatar)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 24.w,
                          height: 24.w,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.w,
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 24.w,
                    height: 24.w,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.w),
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      size: 14.w,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            l10n.changeAvatar,
            style: TextStyle(
              fontSize: 13.sp,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onEdit,
    required AppLocalizations l10n,
  }) {
    // 如果值为空，显示"点击设置..."的提示
    final displayValue = value.isNotEmpty 
      ? value 
      : _getPlaceholderText(label, l10n);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.w),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20.sp, color: AppColors.textSecondary),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    displayValue,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: value.isNotEmpty ? AppColors.textPrimary : AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onEdit,
              icon: Icon(
                Icons.edit_outlined,
                size: 20.sp,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 根据字段标签获取占位符文本
  String _getPlaceholderText(String label, AppLocalizations l10n) {
    switch (label) {
      case '昵称':
        return l10n.clickToSetNickname;
      case '邮箱':
        return l10n.clickToSetEmail;
      case '手机':
        return l10n.clickToSetPhone;
      case '地区':
        return l10n.clickToSetRegion;
      default:
        return '-';
    }
  }
  
  Widget _buildRegionSelector(AppLocalizations l10n) {
    final country = _countryController.text;
    final region = _regionController.text;
    final displayText = country.isNotEmpty
        ? (region.isNotEmpty ? '$country $region' : country)
        : l10n.selectRegion;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.w),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 20.sp,
              color: AppColors.textSecondary,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.locationInfo,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    displayText,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: country.isNotEmpty
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _showRegionPicker(l10n),
              icon: Icon(
                Icons.edit_outlined,
                size: 20.sp,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
