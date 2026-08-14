import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool _checkingUpdate = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  CancelToken? _cancelToken;

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppToast.show(context, l10n.cannotOpenLink(url), type: ToastType.info);
      }
    }
  }

  void _showUserAgreement() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.userAgreement),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.userAgreementTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.sp,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  l10n.userAgreementContent,
                  style: TextStyle(fontSize: 12.sp, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.gotIt),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.privacyPolicy),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.privacyPolicyTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.sp,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  l10n.privacyPolicyContent,
                  style: TextStyle(fontSize: 12.sp, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.gotIt),
          ),
        ],
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdate = true);

    try {
      final updateService = getIt<AppUpdateService>();
      final info = await updateService.checkUpdate(AppConfig.versionCode);

      if (!mounted) return;

      if (info.hasUpdate) {
        _showUpdateDialog(info);
      } else {
        _showNoUpdateDialog();
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, AppLocalizations.of(context)!.checkUpdateFailed, type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  void _showNoUpdateDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.versionCheck),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 小烁成功动作插画：已是最新版本（美术路由 C2/success）
            Image.asset(
              CsergyAssets.xiaoshuoSuccess,
              width: 72.w,
              height: 72.w,
              fit: BoxFit.contain,
            ),
            SizedBox(height: 12.h),
            Text(
              l10n.alreadyLatestVersion,
              style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4.h),
            Text(
              '${l10n.versionNumber}: ${AppConfig.version}',
              style: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog(AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: !info.shouldForceUpdate,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return PopScope(
          canPop: !info.shouldForceUpdate,
          child: StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.system_update, color: AppColors.primary),
                  SizedBox(width: 8.w),
                  Text(l10n.newVersionFound),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.str(
                        'latest_version_label',
                        {'version': info.latestVersionName},
                      ),
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      l10n.str(
                        'current_version_label',
                        {'version': AppConfig.version},
                      ),
                      style:
                          TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                    ),
                    if (info.changelog.isNotEmpty) ...[
                      SizedBox(height: 12.h),
                      Text(
                        l10n.updateContent,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        info.changelog,
                        style: TextStyle(
                          fontSize: 12.sp,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (_downloading) ...[
                      SizedBox(height: 16.h),
                      LinearProgressIndicator(value: _downloadProgress),
                      SizedBox(height: 4.h),
                      Text(
                        '${l10n.downloadProgress} ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (!info.shouldForceUpdate)
                  TextButton(
                    onPressed: _downloading
                        ? null
                        : () {
                            _cancelToken?.cancel();
                            Navigator.pop(context);
                          },
                    child: Text(l10n.updateLater),
                  ),
                FilledButton(
                  onPressed: _downloading
                      ? null
                      : () => _handleUpdate(info, setDialogState),
                  child: Text(
                    Platform.isIOS
                        ? l10n.goToUpdate
                        : (_downloading
                            ? l10n.downloadProgress
                            : l10n.updateNow),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBrowserDownloadDialog(AppUpdateInfo info) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.open_in_browser, color: AppColors.primary),
            SizedBox(width: 8.w),
            Text(l10n.str('browser_download_title', {})),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.str(
                'browser_download_desc',
                {'version': info.latestVersionName},
              ),
              style: TextStyle(fontSize: 14.sp, height: 1.5),
            ),
            SizedBox(height: 8.h),
            Text(
              info.downloadUrl,
              style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _openUrl(info.downloadUrl);
            },
            child: Text(l10n.str('open_in_browser', {})),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUpdate(
    AppUpdateInfo info,
    void Function(void Function()) setDialogState,
  ) async {
    if (Platform.isIOS) {
      // iOS: 跳转到 App Store
      if (info.downloadUrl.isNotEmpty) {
        await _openUrl(info.downloadUrl);
      }
      return;
    }

    // Android: 下载APK并安装
    setState(() => _downloading = true);
    setDialogState(() {});
    _cancelToken = CancelToken();

    try {
      final updateService = getIt<AppUpdateService>();
      final fileName = 'app-${info.latestVersionName}.apk';

      await updateService.downloadAndInstall(
        info.downloadUrl,
        fileName,
        cancelToken: _cancelToken,
        onProgress: (progress) {
          setState(() => _downloadProgress = progress);
          setDialogState(() {});
        },
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        if (e is WebPageUrlException) {
          // 下载链接是网页而非直接APK，关闭更新弹窗，提示用户用浏览器打开
          Navigator.pop(context);
          _showBrowserDownloadDialog(info);
        } else if (e is! DioException) {
          AppToast.show(context, AppLocalizations.of(context)!.str('download_failed', {'error': e.toString()}), type: ToastType.error);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = 0;
        });
      }
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutUs)),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // 品牌区：渐变背景 + 小烁吉祥物 + 品牌名 + slogan + 版本号卡片
          // （美术路由 P2/brand-hero，替换原逆变器产品卡）
          Container(
            margin: EdgeInsets.symmetric(horizontal: 20.w),
            padding: EdgeInsets.fromLTRB(20.w, 26.h, 20.w, 24.h),
            decoration: AppColor.heroCard(context),
            child: Column(
              children: [
                // 吉祥物小烁（欢迎姿态，透明底 WebP）
                Image.asset(
                  CsergyAssets.xiaoshuoWelcome,
                  width: 128.w,
                  height: 128.w,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.bolt,
                    size: 72.w,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                SizedBox(height: 12.h),
                // 品牌名：辰烁科技
                Text(
                  l10n.brandName,
                  style: TextStyle(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 6.h),
                // slogan
                Text(
                  l10n.aboutSlogan,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 16.h),
                // 版本号卡片式排版
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 7.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 14.w, color: Colors.white),
                      SizedBox(width: 6.w),
                      Text(
                        'V${AppConfig.version}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24.h),
          // 法律与隐私分组：卡片化菜单
          SettingsSectionTitle(
            icon: Icons.verified_user_outlined,
            title: l10n.aboutLegalGroup,
            accent: AppColors.blue,
          ),
          SettingsCard([
            SettingsValueRow(
              icon: Icons.description_outlined,
              accent: AppColors.blue,
              title: l10n.userAgreement,
              onTap: _showUserAgreement,
            ),
            SettingsValueRow(
              icon: Icons.privacy_tip_outlined,
              accent: AppColors.blue,
              title: l10n.privacyPolicy,
              onTap: _showPrivacyPolicy,
            ),
          ]),
          // 更多信息分组：检查更新
          SettingsSectionTitle(
            icon: Icons.info_outline,
            title: l10n.aboutMoreGroup,
            accent: AppColors.teal,
          ),
          SettingsCard([
            SettingsValueRow(
              icon: Icons.system_update_outlined,
              accent: AppColors.teal,
              title: l10n.checkUpdate,
              onTap: _checkingUpdate ? null : _checkForUpdates,
              trailing: _checkingUpdate
                  ? SizedBox(
                      width: 20.w,
                      height: 20.w,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
          ]),
          SizedBox(height: 40.h),
          Center(
            child: Text(
              l10n.copyright,
              style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
            ),
          ),
        ],
      ),
    );
  }
}
