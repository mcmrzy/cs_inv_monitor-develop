import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/router/shell/bottom_nav_bar.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/profile/presentation/widgets/profile_setup_dialog.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 主框架 Shell：承载底部导航 + 页面切换动画，
/// 并负责进入主页后的一次性副作用（完善资料提示、App 更新检查）。
/// 自 app_router.dart 拆分而来，路由文件仅保留路由表。
class MainShell extends StatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static bool _hasCheckedUpdate = false;

  // 完善个人信息弹窗：本次启动仅提示一次（跳过或已设置后不再弹）
  static bool _hasShownProfilePrompt = false;

  // 等待 profile 刷新完成后再判断是否弹出完善资料弹窗的订阅
  StreamSubscription<AuthState>? _profileSetupSubscription;

  bool _downloading = false;

  double _downloadProgress = 0;

  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();

    // 未设置昵称的一键登录新用户：进入主框架后弹出完善个人信息弹窗
    if (!_hasShownProfilePrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeShowProfileSetup();
      });
    }

    if (!_hasCheckedUpdate) {
      _hasCheckedUpdate = true;

      // 延迟检查更新，避免阻塞页面加载
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _autoCheckUpdate();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _profileSetupSubscription?.cancel();
    _cancelToken?.cancel();

    super.dispose();
  }

  /// 一键登录自动注册用户（昵称为空）首次进入时弹出完善个人信息弹窗
  void _maybeShowProfileSetup() {
    if (_hasShownProfilePrompt) return;
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    // 乐观进入时 user 尚未加载（后台刷新中），等待刷新完成后再判断，
    // 避免资料已存在却因未加载完成而重复弹出完善资料弹窗
    if (authState.user == null) {
      _profileSetupSubscription?.cancel();
      _profileSetupSubscription =
          context.read<AuthBloc>().stream.listen((state) {
        if (state is AuthAuthenticated && state.user != null) {
          _profileSetupSubscription?.cancel();
          _profileSetupSubscription = null;
          if (mounted) _maybeShowProfileSetup();
        }
      });
      return;
    }

    final nickname = authState.nickname?.trim() ?? '';
    if (nickname.isNotEmpty) return;
    _hasShownProfilePrompt = true;
    ProfileSetupDialog.show(context);
  }

  Future<void> _autoCheckUpdate() async {
    try {
      final updateService = getIt<AppUpdateService>();

      final info = await updateService.checkUpdate(AppConfig.versionCode);

      if (!mounted || !info.hasUpdate) return;

      _showUpdateDialog(info);
    } catch (_) {}
  }

  void _showUpdateDialog(AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: !info.shouldForceUpdate,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;

        return PopScope(
          canPop: !info.shouldForceUpdate,
          child: StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
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
                          TextStyle(fontSize: 13.sp, color: AppColor.textHint(context)),
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
                          color: AppColor.textSecondary(context),
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

                            Navigator.pop(ctx);
                          },
                    child: Text(l10n.updateLater),
                  ),
                FilledButton(
                  onPressed: _downloading
                      ? null
                      : () => _handleUpdate(info, ctx, setDialogState),
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

  Future<void> _handleUpdate(
    AppUpdateInfo info,
    BuildContext ctx,
    void Function(void Function()) setDialogState,
  ) async {
    if (Platform.isIOS) {
      if (info.downloadUrl.isNotEmpty) {
        final uri = Uri.parse(info.downloadUrl);

        if (await canLaunchUrl(uri)) {
          if (!mounted) return;

          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      return;
    }

    setState(() => _downloading = true);

    setDialogState(() {});

    _cancelToken = CancelToken();

    try {
      final updateService = getIt<AppUpdateService>();

      final fileName = 'app-${info.latestVersionName}.apk';

      await updateService.downloadAndInstall(
        info.downloadUrl,
        fileName,
        expectedSha256: info.fileSha256,
        expectedMd5: info.fileMd5,
        cancelToken: _cancelToken,
        onProgress: (progress) {
          setState(() => _downloadProgress = progress);

          setDialogState(() {});
        },
      );

      if (ctx.mounted) Navigator.pop(ctx);
    } catch (e) {
      if (ctx.mounted) {
        if (e is WebPageUrlException) {
          Navigator.pop(ctx);

          _showBrowserDownloadDialog(info);
        } else if (e is! DioException) {
          AppToast.show(
            ctx,
            AppLocalizations.of(ctx)!
                .str('download_failed', {'error': e.toString()}),
            type: ToastType.error,
          );
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

  void _showBrowserDownloadDialog(AppUpdateInfo info) {
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
              style: TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);

              final uri = Uri.parse(info.downloadUrl);

              canLaunchUrl(uri).then((ok) {
                if (ok) launchUrl(uri, mode: LaunchMode.externalApplication);
              });
            },
            child: Text(l10n.str('open_in_browser', {})),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        layoutBuilder: (currentChild, previousChildren) {
          // 完全丢弃 previousChildren，避免新旧页面同时存在于 widget 树导致 GlobalKey 冲突

          // 注意：不能通过 allChildren 列表包含 previousChildren，否则它们仍会被构建

          return currentChild ?? const SizedBox.shrink();
        },
        child: KeyedSubtree(
          key: ValueKey(currentPath),
          child: widget.child,
        ),
      ),
      bottomNavigationBar: const BottomNavBar(),
    );
  }
}
