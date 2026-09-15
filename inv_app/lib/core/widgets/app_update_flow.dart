import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// App 自更新流程：启动静默检查、更新弹窗（含下载进度）、APK 下载安装。
/// main_shell 启动时走 [autoCheck]；关于页走 [checkAndPrompt]。
class AppUpdateFlow {
  static bool _autoChecked = false;
  static bool _promptShowing = false;

  AppUpdateFlow._();

  /// 启动后静默检查一次（每次应用启动最多一次）；发现新版本弹更新弹窗。
  static Future<void> autoCheck(BuildContext context) async {
    if (_autoChecked || _promptShowing) return;
    _autoChecked = true;
    try {
      final updateService = getIt<AppUpdateService>();
      final info = await updateService.checkUpdate(
        await updateService.resolveCurrentVersionCode(),
      );
      if (!info.hasUpdate) return;
      if (!context.mounted || _promptShowing) return;
      _showUpdateDialog(context, info);
    } catch (_) {
      // 静默检查失败不打扰用户；关于页可手动再次检查
    }
  }

  /// 手动检查（关于页入口）：有更新弹更新弹窗，无更新弹「已是最新」提示。
  static Future<bool> checkAndPrompt(BuildContext context) async {
    final updateService = getIt<AppUpdateService>();
    final info = await updateService.checkUpdate(
      await updateService.resolveCurrentVersionCode(),
    );
    if (!info.hasUpdate) {
      final l10n = AppLocalizations.of(context)!;
      showDialog<void>(
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
      return false;
    }
    _showUpdateDialog(context, info);
    return true;
  }

  static void _showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    if (_promptShowing) return;
    _promptShowing = true;

    final progress = ValueNotifier<double>(0);
    final receivedBytes = ValueNotifier<int>(0);
    final downloading = ValueNotifier<bool>(false);
    var cancelToken = CancelToken();

    void disposeNotifiers() {
      progress.dispose();
      receivedBytes.dispose();
      downloading.dispose();
    }

    showDialog(
      context: context,
      barrierDismissible: !info.shouldForceUpdate,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return PopScope(
          canPop: !info.shouldForceUpdate,
          child: AlertDialog(
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
                    l10n.str('browser_download_desc', {'version': info.latestVersionName}),
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
                  SizedBox(height: 16.h),
                  ValueListenableBuilder<bool>(
                    valueListenable: downloading,
                    builder: (context, isDownloading, _) {
                      if (!isDownloading) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ValueListenableBuilder<double>(
                            valueListenable: progress,
                            builder: (context, value, _) {
                              if (value < 0) {
                                return const LinearProgressIndicator();
                              }
                              return LinearProgressIndicator(
                                value: value.clamp(0.0, 1.0),
                              );
                            },
                          ),
                          SizedBox(height: 4.h),
                          ValueListenableBuilder<int>(
                            valueListenable: receivedBytes,
                            builder: (context, bytes, _) => Text(
                              progress.value < 0
                                  ? '${l10n.str('download_progress')} ${(bytes / 1048576).toStringAsFixed(1)} MB'
                                  : '${l10n.str('download_progress')} ${(progress.value * 100).clamp(0, 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: AppColor.textHint(context),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              if (!info.shouldForceUpdate)
                ValueListenableBuilder<bool>(
                  valueListenable: downloading,
                  builder: (context, isDownloading, _) => TextButton(
                    onPressed: isDownloading
                        ? null
                        : () {
                            cancelToken.cancel();
                            Navigator.pop(dialogContext);
                          },
                    child: Text(l10n.str('update_later')),
                  ),
                ),
              ValueListenableBuilder<bool>(
                valueListenable: downloading,
                builder: (context, isDownloading, _) => FilledButton(
                  onPressed: isDownloading
                      ? null
                      : () => _handleInstall(
                          dialogContext,
                          info,
                          progress,
                          receivedBytes,
                          downloading,
                          (token) => cancelToken = token,
                        ),
                  child: Text(
                    Platform.isIOS
                        ? l10n.str('go_to_update')
                        : (isDownloading
                            ? l10n.str('download_progress')
                            : l10n.str('update_now')),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      cancelToken.cancel();
      disposeNotifiers();
      _promptShowing = false;
    });
  }

  static Future<void> _handleInstall(
    BuildContext dialogContext,
    AppUpdateInfo info,
    ValueNotifier<double> progress,
    ValueNotifier<int> receivedBytes,
    ValueNotifier<bool> downloading,
    void Function(CancelToken token) onNewToken,
  ) async {
    if (Platform.isIOS) {
      // iOS: 跳转到 App Store / 分发链接
      final uri = Uri.tryParse(info.downloadUrl);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    downloading.value = true;
    final token = CancelToken();
    onNewToken(token);

    try {
      final updateService = getIt<AppUpdateService>();
      final fileName = 'app-${info.latestVersionName}_b${info.latestVersionCode}.apk';

      await updateService.downloadAndInstall(
        info.downloadUrl,
        fileName,
        expectedSha256: info.fileSha256,
        expectedMd5: info.fileMd5,
        expectedSize: info.fileSize,
        cancelToken: token,
        onProgress: (value, bytes) {
          progress.value = value;
          receivedBytes.value = bytes;
        },
      );

      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }
    } catch (e) {
      if (dialogContext.mounted) {
        if (e is WebPageUrlException) {
          // 下载链接是网页而非直接APK：关闭弹窗，用浏览器打开
          Navigator.pop(dialogContext);
          final uri = Uri.tryParse(info.downloadUrl);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } else if (e is! DioException) {
          final l10n = AppLocalizations.of(dialogContext)!;
          AppToast.show(
            dialogContext,
            l10n.str('download_failed', {'error': e.toString()}),
            type: ToastType.error,
          );
        }
      }
    } finally {
      downloading.value = false;
    }
  }
}
