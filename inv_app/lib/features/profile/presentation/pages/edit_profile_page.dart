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
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/network/api_client.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/profile/data/avatar_upload_service.dart';
import 'package:inv_app/features/profile/presentation/widgets/change_password_dialog.dart';
import 'package:inv_app/features/profile/presentation/widgets/contact_change_dialog.dart';
import 'package:inv_app/features/profile/presentation/widgets/nickname_edit_dialog.dart';
import 'package:inv_app/features/station/presentation/widgets/region_picker_routes.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({
    super.key,
    this.pickAvatarPath,
    this.cropAvatarPath,
    this.uploadAvatarPath,
    this.avatarImageProvider,
  });

  final Future<String?> Function()? pickAvatarPath;
  final Future<String?> Function(String sourcePath)? cropAvatarPath;
  final Future<String> Function(String filePath)? uploadAvatarPath;
  final ImageProvider Function(String url)? avatarImageProvider;

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
  bool _isSavingProfile = false;
  String? _avatarUrl;
  final ImagePicker _picker = ImagePicker();
  StreamSubscription<AuthState>? _lateProfileSubscription;
  Completer<AuthState?>? _lateProfileCompleter;

  bool get _hasLateProfileRequest => _lateProfileCompleter != null;

  bool get _isProfileBusy =>
      _isUploadingAvatar || _isSavingProfile || _hasLateProfileRequest;

  bool get _isNavigationBlocked => _isUploadingAvatar || _isSavingProfile;

  /// 是否为首次设置密码模式（无密码账号）
  bool _isSetPasswordMode = false;

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
      // 判断是否为无密码账号（需要设置密码）
      _isSetPasswordMode = !(state.user?.hasPassword ?? true);
    }

    _nicknameController = TextEditingController(text: nickname);
    _emailController = TextEditingController(text: email);
    _countryController = TextEditingController(text: country);
    _regionController = TextEditingController(text: region);
    _phoneController = TextEditingController(text: phone);
  }

  @override
  void dispose() {
    unawaited(_lateProfileSubscription?.cancel());
    final lateCompleter = _lateProfileCompleter;
    if (lateCompleter != null && !lateCompleter.isCompleted) {
      lateCompleter.complete(null);
    }
    _nicknameController.dispose();
    _emailController.dispose();
    _countryController.dispose();
    _regionController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleLateProfileResult(
    Completer<AuthState?> completer,
    StreamSubscription<AuthState>? subscription, {
    String? submittedAvatar,
  }) async {
    try {
      final state = await completer.future;
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      if (state is AuthProfileUpdateSuccess) {
        if (submittedAvatar != null) {
          setState(() => _avatarUrl = submittedAvatar);
        }
        AppToast.show(context, l10n.success, type: ToastType.success);
      } else if (state is AuthProfileUpdateError) {
        AppToast.show(context, state.message, type: ToastType.error);
      }
    } finally {
      await subscription?.cancel();
      if (identical(_lateProfileSubscription, subscription)) {
        _lateProfileSubscription = null;
      }
      if (identical(_lateProfileCompleter, completer)) {
        _lateProfileCompleter = null;
      }
      if (mounted) setState(() => _isSavingProfile = false);
    }
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

    final avatarService = AvatarUploadService(getIt<ApiClient>());
    return avatarService.uploadAvatar(File(filePath));
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_isProfileBusy) return;
    setState(() => _isUploadingAvatar = true);

    try {
      if (!await _ensureAuthenticated() || !mounted) return;

      final sourcePath = await _selectAvatarPath();
      if (sourcePath == null || !mounted) return;

      final croppedPath = await _cropAvatarPath(sourcePath);
      if (croppedPath == null || !mounted) return;

      final url = await _uploadAvatarPath(croppedPath);
      if (!mounted) return;

      // 单步保存：头像上传成功后立即提交 profile
      final saved = await _submitPartial(avatar: url);
      if (saved && mounted) setState(() => _avatarUrl = url);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString(), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  /// 单步保存：只提交本次变更字段（昵称/地区/头像任一修改后即时保存）。
  /// 成功返回 true（SnackBar 即时确认），失败返回 false——不关闭页面、不清空输入，可重试。
  Future<bool> _submitPartial({
    String? nickname,
    String? country,
    String? regionName,
    String? avatar,
  }) async {
    if (!mounted || _isSavingProfile || _hasLateProfileRequest) return false;
    setState(() => _isSavingProfile = true);
    StreamSubscription<AuthState>? subscription;

    try {
      if (!await _ensureAuthenticated() || !mounted) return false;
      final l10n = AppLocalizations.of(context)!;
      final authBloc = context.read<AuthBloc>();
      // UI 超时不代表底层请求已取消；旧请求仍在执行时不要并发派发。
      if (authBloc.state is AuthLoading) {
        AppToast.show(
          context,
          l10n.errRequestTimeout,
          type: ToastType.error,
        );
        return false;
      }

      final requestId = AuthProfileRequestId.next();
      final requestCompleter = Completer<AuthState?>();

      // 只接收本次资料更新的终态，忽略验证码、登录及旧资料请求状态。
      subscription = authBloc.stream.listen((state) {
        final isOwnSuccess = state is AuthProfileUpdateSuccess &&
            state.requestId == requestId;
        final isOwnError = state is AuthProfileUpdateError &&
            state.requestId == requestId;
        if ((isOwnSuccess || isOwnError) && !requestCompleter.isCompleted) {
          requestCompleter.complete(state);
        }
      });

      authBloc.add(
        AuthUpdateProfileRequested(
          requestId: requestId,
          nickname: nickname,
          country: country,
          regionName: regionName,
          avatar: avatar,
        ),
      );

      // 等待 AuthBloc 处理完成；15s 超时兜底，避免永久等待
      final result = await requestCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );

      if (!mounted) return false;
      if (result is AuthProfileUpdateSuccess) {
        // 更新成功：即时确认（不关闭页面）
        AppToast.show(context, l10n.success, type: ToastType.success);
        return true;
      }
      if (result is AuthProfileUpdateError) {
        // 更新失败：提示原因，输入保留可重试
        AppToast.show(
          context,
          result.message,
          type: ToastType.error,
        );
      } else {
        AppToast.show(
          context,
          l10n.errRequestTimeout,
          type: ToastType.error,
        );
        // 底层请求不会随 UI 超时取消；继续等待同 requestId 的迟到终态。
        final lateSubscription = subscription;
        subscription = null;
        _lateProfileSubscription = lateSubscription;
        _lateProfileCompleter = requestCompleter;
        unawaited(
          _handleLateProfileResult(
            requestCompleter,
            lateSubscription,
            submittedAvatar: avatar,
          ),
        );
      }
      return false;
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString(), type: ToastType.error);
      }
      return false;
    } finally {
      await subscription?.cancel();
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  /// 显示编辑昵称弹窗
  Future<void> _showEditNicknameDialog(AppLocalizations l10n) async {
    await showDialog<void>(
      context: context,
      builder: (_) => NicknameEditDialog(
        initialValue: _nicknameController.text,
        title: l10n.nickname,
        label: l10n.nickname,
        hint: l10n.nickname,
        cancelLabel: l10n.cancel,
        confirmLabel: l10n.confirm,
        onConfirm: _updateNickname,
      ),
    );
  }

  Future<void> _updateNickname(String nickname) async {
    if (!mounted) return;
    setState(() => _nicknameController.text = nickname);
    // 单步保存：昵称修改后立即提交
    await _submitPartial(nickname: nickname);
  }

  /// 显示修改手机号弹窗（现代化UI）
  Future<void> _showChangePhoneDialog(AppLocalizations l10n) async {
    await showDialog(
      context: context,
      builder: (_) => ContactChangeDialog(
        icon: Icons.phone_android,
        title: l10n.changePhone,
        description: '请输入新的手机号码',
        valueLabel: l10n.newPhone,
        valueHint: l10n.phoneHint,
        valueKeyboardType: TextInputType.phone,
        valuePrefixIcon: Icons.phone,
        codeLabel: l10n.verificationCode,
        codeHint: l10n.codeHint,
        sendCodeLabel: l10n.sendCode,
        cancelLabel: l10n.cancel,
        confirmLabel: l10n.confirm,
        onSendCode: _sendPhoneCodeForDialog,
        onConfirm: _verifyPhoneCode,
        onConfirmed: _completePhoneChange,
      ),
    );
  }

  /// 检查登录态；未登录时提示并跳转登录页，返回 false 阻止操作
  Future<bool> _ensureAuthenticated() async {
    final token = await getIt<StorageService>().getToken();
    if (token != null && token.isNotEmpty) return true;

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      // 关闭可能残留的弹窗，避免跳转后被遮挡
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
      AppToast.show(context, l10n.unauthorized, type: ToastType.error);
      context.go('/login');
    }
    return false;
  }

  /// 发送手机验证码（弹窗内使用）
  Future<bool> _sendPhoneCodeForDialog(String phone) async {
    if (!await _ensureAuthenticated()) return false;
    if (!mounted) return false;
    if (phone.isEmpty) {
      AppToast.show(
        context,
        AppLocalizations.of(context)!.phoneRequired,
        type: ToastType.info,
      );
      return false;
    }

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.post(
        '/auth/send-phone-code',
        data: {'phone': phone},
      );

      if (response.statusCode == 200 && response.data['code'] == 0) {
        if (mounted) {
          AppToast.show(
            context,
            AppLocalizations.of(context)!.codeSent,
            type: ToastType.success,
          );
        }
        return true;
      } else {
        throw Exception(response.data['message'] ?? '发送失败');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString(), type: ToastType.error);
      }
      return false;
    }
  }

  /// 验证手机验证码
  Future<bool> _verifyPhoneCode(String newPhone, String code) async {
    if (!await _ensureAuthenticated()) return false;
    if (!mounted) return false;
    if (newPhone.isEmpty || code.isEmpty) {
      AppToast.show(
        context,
        AppLocalizations.of(context)!.fillAllFields,
        type: ToastType.info,
      );
      return false;
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
        return true;
      } else {
        throw Exception(response.data['message'] ?? '验证失败');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString(), type: ToastType.error);
      }
      return false;
    }
  }

  void _completePhoneChange(String newPhone) {
    if (!mounted) return;
    setState(() => _phoneController.text = newPhone);
    // 同步 AuthBloc 状态与本地缓存，重新打开设置页显示新手机号
    context.read<AuthBloc>().add(AuthContactChanged(newPhone: newPhone));
    AppToast.show(
      context,
      AppLocalizations.of(context)!.phoneChanged,
      type: ToastType.success,
    );
  }

  /// 显示修改邮箱弹窗（现代化UI）
  Future<void> _showChangeEmailDialog(AppLocalizations l10n) async {
    await showDialog(
      context: context,
      builder: (_) => ContactChangeDialog(
        icon: Icons.email_outlined,
        title: l10n.changeEmail,
        description: '请输入新的邮箱地址',
        valueLabel: l10n.newEmail,
        valueHint: l10n.emailHint,
        valueKeyboardType: TextInputType.emailAddress,
        valuePrefixIcon: Icons.email,
        codeLabel: l10n.verificationCode,
        codeHint: l10n.codeHint,
        sendCodeLabel: l10n.sendCode,
        cancelLabel: l10n.cancel,
        confirmLabel: l10n.confirm,
        onSendCode: _sendEmailCodeForDialog,
        onConfirm: _verifyEmailCode,
        onConfirmed: _completeEmailChange,
      ),
    );
  }

  /// 发送邮箱验证码（弹窗内使用）
  Future<bool> _sendEmailCodeForDialog(String email) async {
    if (email.isEmpty) {
      AppToast.show(
        context,
        AppLocalizations.of(context)!.emailRequired,
        type: ToastType.info,
      );
      return false;
    }

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.post(
        '/auth/send-email-change-code',
        data: {'email': email},
      );

      if (response.statusCode == 200 && response.data['code'] == 0) {
        if (mounted) {
          AppToast.show(
            context,
            AppLocalizations.of(context)!.codeSent,
            type: ToastType.success,
          );
        }
        return true;
      } else {
        throw Exception(response.data['message'] ?? '发送失败');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString(), type: ToastType.error);
      }
      return false;
    }
  }

  /// 验证邮箱验证码
  Future<bool> _verifyEmailCode(String newEmail, String code) async {
    if (newEmail.isEmpty || code.isEmpty) {
      AppToast.show(
        context,
        AppLocalizations.of(context)!.fillAllFields,
        type: ToastType.info,
      );
      return false;
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
        return true;
      } else {
        throw Exception(response.data['message'] ?? '验证失败');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString(), type: ToastType.error);
      }
      return false;
    }
  }

  void _completeEmailChange(String newEmail) {
    if (!mounted) return;
    setState(() => _emailController.text = newEmail);
    // 同步 AuthBloc 状态与本地缓存，重新打开设置页显示新邮箱
    context.read<AuthBloc>().add(AuthContactChanged(newEmail: newEmail));
    AppToast.show(
      context,
      AppLocalizations.of(context)!.emailChanged,
      type: ToastType.success,
    );
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

    // 第二步：选择省份（个人信息页地址到省即可；电站页保持省/市/区三级）
    final regionResult = await Navigator.push<Map<String, String>>(
      context,
      RegionPickerRoute(
        provinces: _provincesFor(selectedCountry),
        provinceOnly: true,
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

  /// 显示设置/修改密码弹窗：无密码账号进入设置密码模式，有密码账号进入修改密码模式
  void _showChangePasswordDialog(AppLocalizations l10n) {
    ChangePasswordDialog.show(context, isSetPassword: _isSetPasswordMode);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: !_isNavigationBlocked,
      child: Scaffold(
        backgroundColor: AppColor.surface(context),
        appBar: AppBar(
        title: Text(
          l10n.editProfile,
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
                    onEdit: _isProfileBusy
                        ? null
                        : () => _showEditNicknameDialog(l10n),
                    l10n: l10n,
                  ),
                  Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                  _buildReadOnlyField(
                    label: l10n.phone,
                    value: _phoneController.text,
                    icon: Icons.phone_outlined,
                    onEdit: _isProfileBusy
                        ? null
                        : () => _showChangePhoneDialog(l10n),
                    l10n: l10n,
                  ),
                  Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                  _buildReadOnlyField(
                    label: l10n.email,
                    value: _emailController.text,
                    icon: Icons.email_outlined,
                    onEdit: _isProfileBusy
                        ? null
                        : () => _showChangeEmailDialog(l10n),
                    l10n: l10n,
                  ),
                  Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                  _buildRegionSelector(l10n),
                  Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                  // 所有已登录用户均显示密码入口：无密码账号显示“设置密码”，有密码账号显示“修改密码”
                  _buildReadOnlyField(
                    label: _isSetPasswordMode
                        ? l10n.setPassword
                        : l10n.changePassword,
                    value: _isSetPasswordMode ? '-' : '••••••',
                    icon: Icons.lock_outline,
                    onEdit: _isProfileBusy
                        ? null
                        : () => _showChangePasswordDialog(l10n),
                    l10n: l10n,
                  ),
                ],
              ),
            ),
          ],
        ),
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
            key: const Key('edit-profile-avatar-button'),
            onTap: _isProfileBusy ? null : _pickAndUploadAvatar,
            child: Stack(
              children: [
                Container(
                  width: 80.w,
                  height: 80.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    // 圆角矩形头像（微信风格）
                    borderRadius: BorderRadius.circular(12.r),
                    image: avatarUrl.isNotEmpty
                        ? DecorationImage(
                            image: widget.avatarImageProvider?.call(avatarUrl) ??
                                NetworkImage(avatarUrl),
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
                        // 与头像圆角矩形形状保持一致
                        borderRadius: BorderRadius.circular(12.r),
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
              color: AppColor.textSecondary(context),
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
    required VoidCallback? onEdit,
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
          border: Border.all(color: AppColor.border(context)),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20.sp, color: AppColor.textSecondary(context)),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    displayValue,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: value.isNotEmpty ? AppColor.textPrimary(context) : AppColor.textHint(context),
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
                color: onEdit == null
                    ? AppColor.textHint(context)
                    : AppColors.primary,
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
          border: Border.all(color: AppColor.border(context)),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 20.sp,
              color: AppColor.textSecondary(context),
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
                      color: AppColor.textSecondary(context),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    displayText,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: country.isNotEmpty
                          ? AppColor.textPrimary(context)
                          : AppColor.textHint(context),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed:
                  _isProfileBusy ? null : () => _showRegionPicker(l10n),
              icon: Icon(
                Icons.edit_outlined,
                size: 20.sp,
                color: _isProfileBusy
                    ? AppColor.textHint(context)
                    : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
