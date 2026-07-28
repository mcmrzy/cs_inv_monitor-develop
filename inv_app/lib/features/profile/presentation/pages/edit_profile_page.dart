import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/data/china_regions.dart';
import 'package:inv_app/core/data/regions_data.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/network/api_client.dart';
import 'package:inv_app/core/services/service_locator.dart';
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
  bool _isSendingEmailCode = false;
  int _emailCountdown = 0;
  Timer? _emailTimer;

  // 手机验证码相关状态
  bool _isSendingPhoneCode = false;
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
    final baseUrl = AppConfig.apiBaseUrl;
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

      final apiClient = getIt<ApiClient>();
      final avatarService = AvatarUploadService(apiClient);
      final url = await avatarService.uploadAvatar(File(image.path));

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
            backgroundColor: AppColors.errorLight,
          ),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.success),
            backgroundColor: AppColors.successLight,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.errorLight,
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

  /// 发送邮箱验证码
  Future<void> _sendEmailCode(String email) async {
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.emailRequired),
          backgroundColor: AppColors.errorLight,
        ),
      );
      return;
    }

    setState(() {
      _isSendingEmailCode = true;
    });

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.post(
        '/auth/send-email-code',
        data: {'email': email},
      );

      if (response.statusCode == 200 && response.data['code'] == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.codeSent),
              backgroundColor: AppColors.successLight,
            ),
          );
        }

        // 开始倒计时
        setState(() {
          _emailCountdown = 60;
        });
        _emailTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_emailCountdown > 0) {
            setState(() {
              _emailCountdown--;
            });
          } else {
            timer.cancel();
            setState(() {
              _isSendingEmailCode = false;
            });
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
            backgroundColor: AppColors.errorLight,
          ),
        );
      }
      setState(() {
        _isSendingEmailCode = false;
      });
    }
  }

  /// 发送手机验证码
  Future<void> _sendPhoneCode(String phone) async {
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.phoneRequired),
          backgroundColor: AppColors.errorLight,
        ),
      );
      return;
    }

    setState(() {
      _isSendingPhoneCode = true;
    });

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.post(
        '/auth/send-sms-code',
        data: {'phone': phone},
      );

      if (response.statusCode == 200 && response.data['code'] == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.codeSent),
              backgroundColor: AppColors.successLight,
            ),
          );
        }

        // 开始倒计时
        setState(() {
          _phoneCountdown = 60;
        });
        _phoneTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_phoneCountdown > 0) {
            setState(() {
              _phoneCountdown--;
            });
          } else {
            timer.cancel();
            setState(() {
              _isSendingPhoneCode = false;
            });
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
            backgroundColor: AppColors.errorLight,
          ),
        );
      }
      setState(() {
        _isSendingPhoneCode = false;
      });
    }
  }

  /// 显示编辑昵称弹窗
  void _showEditNicknameDialog(AppLocalizations l10n) {
    final nicknameController = TextEditingController(text: _nicknameController.text);

    showDialog(
      context: context,
      builder: (context) => Dialog(
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
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: TextField(
                  controller: nicknameController,
                  decoration: InputDecoration(
                    labelText: l10n.nickname,
                    hintText: l10n.nickname,
                    prefixIcon: Icon(Icons.person, size: 20.sp),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16.w, vertical: 14.h),
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
  void _showChangePhoneDialog(AppLocalizations l10n) {
    final newPhoneController = TextEditingController();
    final codeController = TextEditingController();

    showDialog(
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
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: TextField(
                    controller: newPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: l10n.newPhone,
                      hintText: l10n.phoneHint,
                      prefixIcon: Icon(Icons.phone, size: 20.sp),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16.w, vertical: 14.h),
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                // 验证码输入
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: TextField(
                          controller: codeController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.verificationCode,
                            hintText: l10n.codeHint,
                            prefixIcon: Icon(Icons.lock_outline, size: 20.sp),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16.w, vertical: 14.h),
                          ),
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
                              ? Colors.grey
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
  }

  /// 发送手机验证码（弹窗内使用）
  Future<void> _sendPhoneCodeForDialog(
      String phone, StateSetter setDialogState) async {
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.phoneRequired),
          backgroundColor: AppColors.errorLight,
        ),
      );
      return;
    }

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.post(
        '/auth/send-sms-code',
        data: {'phone': phone},
      );

      if (response.statusCode == 200 && response.data['code'] == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.codeSent),
              backgroundColor: AppColors.successLight,
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
            setDialogState(() {
              _isSendingPhoneCode = false;
            });
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
            backgroundColor: AppColors.errorLight,
          ),
        );
      }
    }
  }

  /// 验证手机验证码
  Future<void> _verifyPhoneCode(String newPhone, String code) async {
    if (newPhone.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.fillAllFields),
          backgroundColor: AppColors.errorLight,
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
        if (mounted) {
          Navigator.pop(context);
          setState(() {
            _phoneController.text = newPhone;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.phoneChanged),
              backgroundColor: AppColors.successLight,
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
            backgroundColor: AppColors.errorLight,
          ),
        );
      }
    }
  }

  /// 显示修改邮箱弹窗（现代化UI）
  void _showChangeEmailDialog(AppLocalizations l10n) {
    final newEmailController = TextEditingController();
    final codeController = TextEditingController();

    showDialog(
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
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: TextField(
                    controller: newEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: l10n.newEmail,
                      hintText: l10n.emailHint,
                      prefixIcon: Icon(Icons.email, size: 20.sp),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16.w, vertical: 14.h),
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                // 验证码输入
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: TextField(
                          controller: codeController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.verificationCode,
                            hintText: l10n.codeHint,
                            prefixIcon: Icon(Icons.lock_outline, size: 20.sp),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16.w, vertical: 14.h),
                          ),
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
                              ? Colors.grey
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
  }

  /// 发送邮箱验证码（弹窗内使用）
  Future<void> _sendEmailCodeForDialog(
      String email, StateSetter setDialogState) async {
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.emailRequired),
          backgroundColor: AppColors.errorLight,
        ),
      );
      return;
    }

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.post(
        '/auth/send-email-code',
        data: {'email': email},
      );

      if (response.statusCode == 200 && response.data['code'] == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.codeSent),
              backgroundColor: AppColors.successLight,
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
            setDialogState(() {
              _isSendingEmailCode = false;
            });
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
            backgroundColor: AppColors.errorLight,
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
          backgroundColor: AppColors.errorLight,
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
        if (mounted) {
          Navigator.pop(context);
          setState(() {
            _emailController.text = newEmail;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.emailChanged),
              backgroundColor: AppColors.successLight,
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
            backgroundColor: AppColors.errorLight,
          ),
        );
      }
    }
  }

  /// 显示地区选择器（参考创建电站页面的UI风格）
  void _showRegionPicker(AppLocalizations l10n) {
    // 解析已有的数据
    String? existingCountry = _countryController.text.isNotEmpty ? _countryController.text : null;
    String? existingProvince;
    String? existingCity;

    final existingRegion = _regionController.text;
    if (existingRegion.isNotEmpty) {
      final parts = existingRegion.split(' ');
      if (parts.isNotEmpty) existingProvince = parts[0];
      if (parts.length > 1) existingCity = parts[1];
    }

    Navigator.push<Map<String, String>>(
      context,
      _ProfileRegionPickerRoute(
        initialCountry: existingCountry,
        initialProvince: existingProvince,
        initialCity: existingCity,
      ),
    ).then((result) {
      if (result != null) {
        setState(() {
          _countryController.text = result['country'] ?? '';
          final regionParts = <String>[];
          if (result['province'] != null && result['province']!.isNotEmpty) {
            regionParts.add(result['province']!);
          }
          if (result['city'] != null && result['city']!.isNotEmpty) {
            regionParts.add(result['city']!);
          }
          _regionController.text = regionParts.join(' ');
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
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
        backgroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: _isLoading
                ? SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.w,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  )
                : Text(
                    l10n.save,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Column(
                children: [
                  _buildReadOnlyField(
                    label: l10n.nickname,
                    value: _nicknameController.text,
                    icon: Icons.person_outline,
                    onEdit: () => _showEditNicknameDialog(l10n),
                  ),
                  Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                  _buildReadOnlyField(
                    label: l10n.phone,
                    value: _phoneController.text,
                    icon: Icons.phone_outlined,
                    onEdit: () => _showChangePhoneDialog(l10n),
                  ),
                  Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                  _buildReadOnlyField(
                    label: l10n.email,
                    value: _emailController.text,
                    icon: Icons.email_outlined,
                    onEdit: () => _showChangeEmailDialog(l10n),
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
        color: Colors.white,
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



  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.w),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20.sp),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        ),
      ),
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onEdit,
  }) {
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
                    value.isNotEmpty ? value : '-',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.textPrimary,
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

class _ProfileRegionPickerRoute extends PageRouteBuilder<Map<String, String>> {
  final String? initialCountry;
  final String? initialProvince;
  final String? initialCity;

  _ProfileRegionPickerRoute({
    this.initialCountry,
    this.initialProvince,
    this.initialCity,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              _ProfileRegionPickerPage(
            initialCountry: initialCountry,
            initialProvince: initialProvince,
            initialCity: initialCity,
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
  final String? initialCountry;
  final String? initialProvince;
  final String? initialCity;

  const _ProfileRegionPickerPage({
    this.initialCountry,
    this.initialProvince,
    this.initialCity,
  });

  @override
  State<_ProfileRegionPickerPage> createState() => _ProfileRegionPickerPageState();
}

class _ProfileRegionPickerPageState extends State<_ProfileRegionPickerPage> {
  late FixedExtentScrollController _countryCtrl;
  late FixedExtentScrollController _provCtrl;
  late FixedExtentScrollController _cityCtrl;

  int _countryIdx = 0;
  int _provIdx = 0;
  int _cityIdx = 0;

  bool _isNavigating = false;

  late List<String> _provinces;
  late List<String> _cities;

  static const _itemH = 44.0;

  @override
  void initState() {
    super.initState();
    
    // 初始化国家索引
    if (widget.initialCountry != null) {
      final idx = countries.indexWhere((c) => c['name'] == widget.initialCountry);
      _countryIdx = idx >= 0 ? idx : 0;
    }
    
    // 初始化省份列表
    final countryName = countries[_countryIdx]['name'];
    if (countryName == '中国') {
      _provinces = chinaRegions.keys.toList()..sort();
    } else {
      _provinces = (countryName != null ? globalRegions[countryName] : null) ?? [];
    }
    
    // 初始化省份索引
    if (widget.initialProvince != null && _provinces.isNotEmpty) {
      final idx = _provinces.indexOf(widget.initialProvince!);
      _provIdx = idx >= 0 ? idx : 0;
    }
    
    // 初始化城市/区列表
    _cities = _getDistrictsForProvince(
        countryName, _provinces.isNotEmpty ? _provinces[_provIdx] : null);
    
    // 初始化城市索引
    if (widget.initialCity != null && _cities.isNotEmpty) {
      final idx = _cities.indexOf(widget.initialCity!);
      _cityIdx = idx >= 0 ? idx : 0;
    }
    
    _countryCtrl = FixedExtentScrollController(initialItem: _countryIdx);
    _provCtrl = FixedExtentScrollController(initialItem: _provIdx);
    _cityCtrl = FixedExtentScrollController(initialItem: _cityIdx);
  }

  @override
  void dispose() {
    _countryCtrl.dispose();
    _provCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  void _onCountryChanged(int idx) {
    if (idx == _countryIdx) return;
    setState(() {
      _countryIdx = idx;
      final countryName = countries[idx]['name'];
      if (countryName == '中国') {
        _provinces = chinaRegions.keys.toList()..sort();
      } else {
        _provinces = (countryName != null ? globalRegions[countryName] : null) ?? [];
      }
      _provIdx = 0;
      _cities = _getDistrictsForProvince(
          countryName, _provinces.isNotEmpty ? _provinces[0] : null);
      _cityIdx = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provCtrl.jumpToItem(0);
      _cityCtrl.jumpToItem(0);
    });
  }

  void _onProvChanged(int idx) {
    if (idx == _provIdx) return;
    setState(() {
      _provIdx = idx;
      final countryName = countries[_countryIdx]['name'];
      _cities = _getDistrictsForProvince(countryName, _provinces[idx]);
      _cityIdx = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cityCtrl.jumpToItem(0);
    });
  }

  void _onCityChanged(int idx) {
    setState(() => _cityIdx = idx);
  }

  List<String> _getDistrictsForProvince(String? countryName, String? province) {
    if (province == null || countryName == null) return [];
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
    final countryName = countries[_countryIdx]['name'];
    String? province;
    String? city;
    if (_provinces.isNotEmpty && _provIdx < _provinces.length) {
      province = _provinces[_provIdx];
    }
    if (_cities.isNotEmpty && _cityIdx < _cities.length) {
      city = _cities[_cityIdx];
    }
    Navigator.of(context).pop({
      'country': countryName,
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
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.surfaceHover),
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
                          countries.map((c) => c['name']!).toList(),
                          _countryCtrl,
                          _countryIdx,
                          _onCountryChanged,
                          colLabel: '国家',
                        ),
                      ),
                      Container(width: 1, color: AppColors.surfaceHover),
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
          color: const Color(0xFFF8FAFB),
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
                              border: const Border.symmetric(
                                horizontal:
                                    BorderSide(color: Color(0xFFE5E7EB)),
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
