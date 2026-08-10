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
import 'package:inv_app/core/data/continents_data.dart';
import 'package:inv_app/core/data/regions_data.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/network/api_client.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/profile/data/avatar_upload_service.dart';
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
  late TextEditingController _bioController;
  late TextEditingController _phoneController;
  bool _isLoading = false;
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
    String bio = '';
    String phone = '';

    if (state is AuthAuthenticated) {
      nickname = state.nickname ?? '';
      email = state.email ?? '';
      country = state.country ?? '';
      region = state.regionName ?? '';
      bio = state.bio ?? '';
      phone = state.phone;
      _avatarUrl = state.avatar;
    }

    _nicknameController = TextEditingController(text: nickname);
    _emailController = TextEditingController(text: email);
    _countryController = TextEditingController(text: country);
    _regionController = TextEditingController(text: region);
    _bioController = TextEditingController(text: bio);
    _phoneController = TextEditingController(text: phone);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _countryController.dispose();
    _regionController.dispose();
    _bioController.dispose();
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
            hideBottomControls: false,
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

  Future<void> _saveProfile() async {
    if (!await _ensureAuthenticated()) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

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
              nickname: _nicknameController.text,
              email: _emailController.text,
              country: _countryController.text,
              regionName: _regionController.text,
              bio: _bioController.text,
              avatar: _avatarUrl,
            ),
          );

      // 等待 AuthBloc 处理完成
      await completer.future;
      await subscription.cancel();

      if (mounted) {
        final currentState = context.read<AuthBloc>().state;
        if (currentState is AuthAuthenticated) {
          // 更新成功
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.success),
            ),
          );
          Navigator.pop(context);
        } else if (currentState is AuthError) {
          // 更新失败
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(currentState.message),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
                      horizontal: 16.w, vertical: 14.h),
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
                        horizontal: 16.w, vertical: 14.h),
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
                              horizontal: 16.w, vertical: 14.h),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Container(
                      height: 52.h,
                      child: ElevatedButton(
                        onPressed: _phoneCountdown > 0
                            ? null
                            : () => _sendPhoneCodeForDialog(
                                newPhoneController.text, setDialogState),
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
                            newPhoneController.text, codeController.text),
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
        SnackBar(
          content: Text('登录已过期，请重新登录'),
        ),
      );
      context.go('/login');
    }
    return false;
  }

  /// 发送手机验证码（弹窗内使用）
  Future<void> _sendPhoneCodeForDialog(
      String phone, StateSetter setDialogState) async {
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
                        horizontal: 16.w, vertical: 14.h),
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
                              horizontal: 16.w, vertical: 14.h),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Container(
                      height: 52.h,
                      child: ElevatedButton(
                        onPressed: _emailCountdown > 0
                            ? null
                            : () => _sendEmailCodeForDialog(
                                newEmailController.text, setDialogState),
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
                            newEmailController.text, codeController.text),
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
      String email, StateSetter setDialogState) async {
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

  /// 显示地区选择器（两步选择流程：洲+国家 -> 省/市）
  Future<void> _showRegionPicker(AppLocalizations l10n) async {
    // 第一步：选择洲+国家
    final countryResult = await Navigator.push<Map<String, String>>(
      context,
      _ContinentCountryPickerRoute(),
    );
    if (countryResult == null || !mounted) return;

    final selectedCountry = countryResult['country'] ?? '中国';

    // 第二步：选择省/市（两级选择器，顶部有"不限"选项）
    final regionResult = await Navigator.push<Map<String, String>>(
      context,
      _ProfileRegionPickerRoute(
        country: selectedCountry,
      ),
    );

    if (regionResult != null) {
      setState(() {
        _countryController.text = selectedCountry;
        final regionParts = <String>[];
        if (regionResult['province'] != null && regionResult['province']!.isNotEmpty) {
          regionParts.add(regionResult['province']!);
        }
        if (regionResult['city'] != null && regionResult['city']!.isNotEmpty) {
          regionParts.add(regionResult['city']!);
        }
        _regionController.text = regionParts.join(' ');
      });
    } else {
      // 用户在第二步取消，只设置国家
      setState(() {
        _countryController.text = selectedCountry;
        _regionController.text = '';
      });
    }
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
            SizedBox(height: 32.h),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 24.w,
                      height: 24.w,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.w,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      l10n.save,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                      ),
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
                                AlwaysStoppedAnimation<Color>(Colors.white),
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
        ? (region.isNotEmpty ? '$country - $region' : country)
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
            Icon(Icons.location_on_outlined,
                size: 20.sp, color: AppColors.textSecondary),
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

class _ContinentCountryPickerRoute extends PageRouteBuilder<Map<String, String>> {
  _ContinentCountryPickerRoute()
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const _ContinentCountryPickerPage(),
          opaque: false,
          barrierColor: Colors.black54,
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                      .animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            );
          },
        );
}

class _ContinentCountryPickerPage extends StatefulWidget {
  const _ContinentCountryPickerPage();

  @override
  State<_ContinentCountryPickerPage> createState() =>
      _ContinentCountryPickerPageState();
}

class _ContinentCountryPickerPageState
    extends State<_ContinentCountryPickerPage> {
  late FixedExtentScrollController _continentCtrl;
  late FixedExtentScrollController _countryCtrl;
  int _continentIdx = 0;
  int _countryIdx = 0;

  static const _itemH = 44.0;

  @override
  void initState() {
    super.initState();
    _continentCtrl = FixedExtentScrollController();
    _countryCtrl = FixedExtentScrollController();
  }

  @override
  void dispose() {
    _continentCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _currentCountries {
    if (continents.isEmpty) return [];
    return List<Map<String, String>>.from(
        continents[_continentIdx]['countries'] as List,
    );
  }

  void _onContinentChanged(int idx) {
    if (idx == _continentIdx) return;
    setState(() {
      _continentIdx = idx;
      _countryIdx = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _countryCtrl.jumpToItem(0);
    });
  }

  void _onCountryChanged(int idx) {
    setState(() => _countryIdx = idx);
  }

  void _confirm() {
    final countries = _currentCountries;
    if (countries.isEmpty) return;
    final country = countries[_countryIdx];
    Navigator.of(context).pop({'country': country['name']!});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: AppColor.surfaceContainer(context),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            ),
            child: Column(
              children: [
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerTheme.color ??
                            AppColors.divider,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          AppLocalizations.of(context)!.cancel,
                          style: TextStyle(
                            fontSize: 15.sp,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)!.selectRegion,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      TextButton(
                        onPressed: _confirm,
                        child: Text(
                          AppLocalizations.of(context)!.confirm,
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: _itemH * 7,
                  child: Row(
                    children: [
                      // 左列：洲列表
                      Expanded(
                        flex: 3,
                        child: _buildColumn(
                          continents.map((c) => c['name'] as String).toList(),
                          _continentCtrl,
                          _continentIdx,
                          _onContinentChanged,
                          colLabel: '洲',
                        ),
                      ),
                      Container(width: 1, color: AppColors.surfaceHover),
                      // 右列：国家列表
                      Expanded(
                        flex: 4,
                        child: _buildColumn(
                          _currentCountries
                              .map((c) => c['name']!)
                              .toList(),
                          _countryCtrl,
                          _countryIdx,
                          _onCountryChanged,
                          colLabel: AppLocalizations.of(context)!.country,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumn(
    List<String> items,
    FixedExtentScrollController ctrl,
    int idx,
    ValueChanged<int> onChange, {
    String colLabel = '',
  }) {
    return Column(
      children: [
        Container(
          height: _itemH,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Text(
            colLabel,
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColors.textHint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    '—',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.textHint,
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        children: [
                          const Spacer(),
                          Container(
                            height: _itemH,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              border: Border.symmetric(
                                horizontal: BorderSide(
                                  color: Theme.of(context).dividerTheme.color ??
                                      AppColors.divider,
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    ListWheelScrollView.useDelegate(
                      controller: ctrl,
                      itemExtent: _itemH,
                      diameterRatio: 1.2,
                      overAndUnderCenterOpacity: 0.4,
                      onSelectedItemChanged: onChange,
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (_, i) {
                          if (i < 0 || i >= items.length) {
                            return const SizedBox();
                          }
                          final selected = i == idx;
                          return Center(
                            child: Text(
                              items[i],
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: selected
                                    ? AppColors.textPrimary
                                    : AppColors.textHint,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                        childCount: items.length,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ProfileRegionPickerRoute extends PageRouteBuilder<Map<String, String>> {
  final String country;

  _ProfileRegionPickerRoute({
    required this.country,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              _ProfileRegionPickerPage(
            country: country,
          ),
          opaque: false,
          barrierColor: Colors.black54,
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                      .animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            );
          },
        );
}

class _ProfileRegionPickerPage extends StatefulWidget {
  final String country;

  const _ProfileRegionPickerPage({
    required this.country,
  });

  @override
  State<_ProfileRegionPickerPage> createState() => _ProfileRegionPickerPageState();
}

class _ProfileRegionPickerPageState extends State<_ProfileRegionPickerPage> {
  late FixedExtentScrollController _provCtrl;
  late FixedExtentScrollController _cityCtrl;

  int _provIdx = 0;
  int _cityIdx = 0;

  bool _isNavigating = false;

  late List<String> _provinces;
  late List<String> _cities;

  static const _itemH = 44.0;

  @override
  void initState() {
    super.initState();
    
    // 初始化省份列表
    if (widget.country == '中国') {
      _provinces = ['不限', ...chinaRegions.keys.toList()..sort()];
    } else {
      _provinces = ['不限', ...(globalRegions[widget.country] ?? [])];
    }
    
    // 初始化城市/区列表
    _cities = _getDistrictsForProvince(
        widget.country, _provinces.length > 1 ? _provinces[1] : null);
    
    _provCtrl = FixedExtentScrollController(initialItem: _provIdx);
    _cityCtrl = FixedExtentScrollController(initialItem: _cityIdx);
  }

  @override
  void dispose() {
    _provCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  void _onProvChanged(int idx) {
    if (idx == _provIdx) return;
    setState(() {
      _provIdx = idx;
      if (idx == 0) {
        // 选择"不限"，清空城市列表
        _cities = [];
        _cityIdx = 0;
      } else {
        _cities = _getDistrictsForProvince(widget.country, _provinces[idx]);
        _cityIdx = 0;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cityCtrl.jumpToItem(0);
    });
  }

  void _onCityChanged(int idx) {
    setState(() => _cityIdx = idx);
  }

  List<String> _getDistrictsForProvince(String? countryName, String? province) {
    if (province == null || countryName == null || province == '不限') return [];
    if (countryName == '中国') {
      final cityMap = chinaRegions[province];
      if (cityMap == null) return [];
      // 直辖市：只有一个子键（如"市辖区"），展开其区县列表
      if (cityMap.length == 1) {
        return cityMap.values.first;
      }
      // 普通省份：返回城市列表
      return cityMap.keys.toList()..sort();
    }
    return [];
  }

  void _confirm() {
    if (_isNavigating) return;
    _isNavigating = true;
    
    String? province;
    String? city;
    
    // 如果选择"不限"，返回空字符串
    if (_provIdx == 0) {
      province = '';
      city = '';
    } else {
      if (_provinces.isNotEmpty && _provIdx < _provinces.length) {
        province = _provinces[_provIdx];
      }
      if (_cities.isNotEmpty && _cityIdx < _cities.length) {
        city = _cities[_cityIdx];
      }
    }
    
    Navigator.of(context).pop({
      'province': province ?? '',
      'city': city ?? '',
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: AppColor.surfaceContainer(context),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            ),
            child: Column(
              children: [
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerTheme.color ??
                            AppColors.divider,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _isNavigating
                            ? null
                            : () {
                                _isNavigating = true;
                                Navigator.of(context).pop();
                              },
                        child: Text(
                          l10n.cancel,
                          style: TextStyle(
                            fontSize: 15.sp,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                      Text(
                        l10n.selectRegion,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      TextButton(
                        onPressed: _confirm,
                        child: Text(
                          l10n.confirm,
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: _itemH * 7,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildColumn(
                          _provinces,
                          _provCtrl,
                          _provIdx,
                          _onProvChanged,
                          colLabel: '省份/州',
                        ),
                      ),
                      Container(width: 1, color: AppColors.surfaceHover),
                      Expanded(
                        flex: 3,
                        child: _buildColumn(
                          _cities,
                          _cityCtrl,
                          _cityIdx,
                          _onCityChanged,
                          colLabel: '区/市',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumn(
    List<String> items,
    FixedExtentScrollController ctrl,
    int idx,
    ValueChanged<int> onChange, {
    String colLabel = '',
  }) {
    return Column(
      children: [
        Container(
          height: _itemH,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Text(
            colLabel,
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColors.textHint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    '—',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.textHint,
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        children: [
                          const Spacer(),
                          Container(
                            height: _itemH,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              border: Border.symmetric(
                                horizontal: BorderSide(
                                  color: Theme.of(context).dividerTheme.color ??
                                      AppColors.divider,
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    ListWheelScrollView.useDelegate(
                      controller: ctrl,
                      itemExtent: _itemH,
                      diameterRatio: 1.2,
                      overAndUnderCenterOpacity: 0.4,
                      onSelectedItemChanged: onChange,
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (_, i) {
                          if (i < 0 || i >= items.length) {
                            return const SizedBox();
                          }
                          final selected = i == idx;
                          return Center(
                            child: Text(
                              items[i],
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: selected
                                    ? AppColors.textPrimary
                                    : AppColors.textHint,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                        childCount: items.length,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
