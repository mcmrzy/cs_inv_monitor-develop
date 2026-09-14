import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
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
  /// 展示用版本名：来自安装包元数据（pubspec 注入），
  /// 与编译产物始终一致；读取失败回退编译期常量。
  String _displayVersion = AppConfig.version;
  bool _checkingUpdate = false;
  bool _downloading = false;
  /// 下载进度：0.0~1.0；< 0 表示总大小未知（CDN 分块传输且服务端未给文件大小）
  double _downloadProgress = 0;
  int _downloadedBytes = 0;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _loadDisplayVersion();
  }

  Future<void> _loadDisplayVersion() async {
    final updateService = getIt<AppUpdateService>();
    final version = await updateService.resolveCurrentVersionName();
    if (mounted && version != _displayVersion) {
      setState(() => _displayVersion = version);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdate = true);

    try {
      final updateService = getIt<AppUpdateService>();
      final info = await updateService.checkUpdate(
        await updateService.resolveCurrentVersionCode(),
      );

      if (!mounted) return;

      if (info.hasUpdate) {
        _showUpdateDialog(info);
      } else {
        _showNoUpdateDialog();
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppToast.show(context, l10n.str('check_update_failed'), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  void _showNoUpdateDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.str('version_check')),
        content: Text(l10n.str('already_latest')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
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
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return PopScope(
          canPop: !info.shouldForceUpdate,
          child: StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.system_update_rounded, color: AppColors.blue),
                  SizedBox(width: 8.w),
                  Expanded(child: Text(l10n.str('new_version_found'))),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.str('latest_version_label', {'version': info.latestVersionName}),
                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      l10n.str('current_version_label', {'version': _displayVersion}),
                      style: TextStyle(fontSize: 13.sp, color: AppColor.textHint(context)),
                    ),
                    if (info.changelog.isNotEmpty) ...[
                      SizedBox(height: 12.h),
                      Text(
                        l10n.str('update_content'),
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        info.changelog,
                        style: TextStyle(
                          fontSize: 12.sp,
                          height: 1.5,
                          color: AppColor.textSecondary(context),
                        ),
                      ),
                    ],
                    if (_downloading) ...[
                      SizedBox(height: 16.h),
                      if (_downloadProgress < 0)
                        const LinearProgressIndicator()
                      else
                        LinearProgressIndicator(value: _downloadProgress.clamp(0.0, 1.0)),
                      SizedBox(height: 4.h),
                      Text(
                        _downloadProgress < 0
                            ? '${l10n.str('download_progress')} ${(_downloadedBytes / 1048576).toStringAsFixed(1)} MB'
                            : '${l10n.str('download_progress')} ${(_downloadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColor.textHint(context),
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
                            Navigator.pop(dialogContext);
                          },
                    child: Text(l10n.str('update_later')),
                  ),
                FilledButton(
                  onPressed: _downloading
                      ? null
                      : () => _handleUpdate(info, dialogContext, setDialogState),
                  child: Text(
                    Platform.isIOS
                        ? l10n.str('go_to_update')
                        : (_downloading
                            ? l10n.str('download_progress')
                            : l10n.str('update_now')),
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
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.str('browser_download_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.str('browser_download_desc', {'version': info.latestVersionName}),
              style: TextStyle(fontSize: 14.sp, height: 1.5),
            ),
            SizedBox(height: 8.h),
            Text(
              info.downloadUrl,
              style: TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openUrl(info.downloadUrl);
            },
            child: Text(l10n.str('open_in_browser')),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUpdate(
    AppUpdateInfo info,
    BuildContext dialogContext,
    void Function(void Function()) setDialogState,
  ) async {
    if (Platform.isIOS) {
      // iOS: 跳转到 App Store / 分发链接
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
      final fileName = 'app-${info.latestVersionName}_b${info.latestVersionCode}.apk';

      await updateService.downloadAndInstall(
        info.downloadUrl,
        fileName,
        expectedSha256: info.fileSha256,
        expectedMd5: info.fileMd5,
        expectedSize: info.fileSize,
        cancelToken: _cancelToken,
        onProgress: (progress, receivedBytes) {
          setState(() {
            _downloadProgress = progress;
            _downloadedBytes = receivedBytes;
          });
          setDialogState(() {});
        },
      );

      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }
    } catch (e) {
      if (mounted) {
        if (e is WebPageUrlException) {
          // 下载链接是网页而非直接APK，关闭更新弹窗，提示用户用浏览器打开
          if (dialogContext.mounted) Navigator.pop(dialogContext);
          _showBrowserDownloadDialog(info);
        } else if (e is! DioException) {
          final l10n = AppLocalizations.of(context)!;
          AppToast.show(
            context,
            l10n.str('download_failed', {'error': e.toString()}),
            type: ToastType.error,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = 0;
          _downloadedBytes = 0;
        });
      }
    }
  }

  void _showLegalDialog(
    BuildContext context, {
    required String title,
    required String documentTitle,
    required String content,
  }) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  documentTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.sp,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(content, style: TextStyle(fontSize: 12.sp, height: 1.5)),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.gotIt),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutUs)),
      body: ListView(
        padding: EdgeInsets.only(bottom: 40.h),
        children: [
          SizedBox(height: 8.h),
          _AboutEnergyHero(l10n: l10n, version: _displayVersion),
          SizedBox(height: 24.h),
          SettingsSectionTitle(
            icon: Icons.system_update_rounded,
            title: l10n.str('check_update'),
            accent: AppColors.blue,
          ),
          SettingsCard([
            SettingsValueRow(
              icon: Icons.system_update_rounded,
              accent: AppColors.blue,
              title: l10n.str('check_update'),
              subtitle: '${l10n.str('current_version')}: V$_displayVersion',
              trailing: _checkingUpdate
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _checkingUpdate ? null : _checkForUpdates,
            ),
          ]),
          SizedBox(height: 24.h),
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
              onTap: () => _showLegalDialog(
                context,
                title: l10n.userAgreement,
                documentTitle: l10n.userAgreementTitle,
                content: l10n.userAgreementContent,
              ),
            ),
            SettingsValueRow(
              icon: Icons.privacy_tip_outlined,
              accent: AppColors.blue,
              title: l10n.privacyPolicy,
              onTap: () => _showLegalDialog(
                context,
                title: l10n.privacyPolicy,
                documentTitle: l10n.privacyPolicyTitle,
                content: l10n.privacyPolicyContent,
              ),
            ),
          ]),
          SizedBox(height: 28.h),
          Center(
            child: Text(
              l10n.copyright,
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColor.textHint(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutEnergyHero extends StatelessWidget {
  final AppLocalizations l10n;
  final String version;

  const _AboutEnergyHero({required this.l10n, required this.version});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w),
      decoration: AppColor.heroCard(context),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        key: const Key('about-energy-hero'),
        painter: const _QuietEnergyPainter(),
        child: Padding(
          padding: EdgeInsets.fromLTRB(24.w, 28.h, 24.w, 24.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: const Icon(
                  Icons.solar_power_rounded,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 28.h),
              Text(
                l10n.brandName,
                style: TextStyle(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 6.h),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 230.w),
                child: Text(
                  l10n.aboutSlogan,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.4,
                  ),
                ),
              ),
              SizedBox(height: 14.h),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 12.w,
                  vertical: 6.h,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18.r),
                ),
                child: Text(
                  'V$version',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 纯代码绘制的静谧能源意象：日光、能量轨迹与光伏阵列。
class _QuietEnergyPainter extends CustomPainter {
  const _QuietEnergyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.83, size.height * 0.25),
          radius: size.width * 0.32,
        ),
      );
    canvas.drawCircle(
      Offset(size.width * 0.83, size.height * 0.25),
      size.width * 0.32,
      glow,
    );

    final orbit = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 3; i++) {
      final inset = i * 18.0;
      canvas.drawArc(
        Rect.fromLTWH(
          size.width * 0.50 + inset,
          -size.height * 0.10 + inset,
          size.width * 0.54 - inset,
          size.height * 0.70 - inset,
        ),
        math.pi * 0.18,
        math.pi * 1.15,
        false,
        orbit,
      );
    }

    final panelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.66,
        size.height * 0.55,
        size.width * 0.26,
        size.height * 0.23,
      ),
      const Radius.circular(6),
    );
    final panel = Paint()
      ..color = Colors.white.withValues(alpha: 0.13)
      ..style = PaintingStyle.fill;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final panelCenter = Offset(size.width * 0.79, size.height * 0.66);
    canvas.save();
    canvas.translate(panelCenter.dx, panelCenter.dy);
    canvas.rotate(-0.10);
    canvas.translate(-panelCenter.dx, -panelCenter.dy);
    canvas.drawRRect(panelRect, panel);
    canvas.drawRRect(panelRect, grid);
    for (var i = 1; i < 4; i++) {
      final x = panelRect.left + panelRect.width * i / 4;
      canvas.drawLine(
        Offset(x, panelRect.top),
        Offset(x, panelRect.bottom),
        grid,
      );
    }
    for (var i = 1; i < 3; i++) {
      final y = panelRect.top + panelRect.height * i / 3;
      canvas.drawLine(
        Offset(panelRect.left, y),
        Offset(panelRect.right, y),
        grid,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
