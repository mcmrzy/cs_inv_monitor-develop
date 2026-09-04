import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 离线状态横幅
///
/// 当设备处于离线状态时显示，提示用户当前无网络连接
/// 可以放置在页面顶部或AppBar下方
class OfflineBanner extends StatefulWidget {
  /// 是否显示详细信息
  final bool showDetails;

  const OfflineBanner({
    super.key,
    this.showDetails = true,
  });

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  late final NetworkStatusService _networkService;
  StreamSubscription<bool>? _statusSubscription;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _networkService = getIt<NetworkStatusService>();
    _isOffline = _networkService.isOffline;

    // 监听网络状态变化
    _statusSubscription = _networkService.statusStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOffline = !isOnline;
        });
      }
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOffline) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 16.w,
        vertical: 8.h,
      ),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.wifi_off,
            size: 16.sp,
            color: theme.colorScheme.onErrorContainer,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.offlineStatus,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.showDetails) ...[
                  SizedBox(height: 2.h),
                  Text(
                    l10n.offlineHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer
                          .withValues(alpha: 0.8),
                      fontSize: 10.sp,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 简化版离线指示器（小圆点）
class OfflineIndicator extends StatefulWidget {
  final double size;

  const OfflineIndicator({
    super.key,
    this.size = 8,
  });

  @override
  State<OfflineIndicator> createState() => _OfflineIndicatorState();
}

class _OfflineIndicatorState extends State<OfflineIndicator> {
  late final NetworkStatusService _networkService;
  StreamSubscription<bool>? _statusSubscription;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _networkService = getIt<NetworkStatusService>();
    _isOffline = _networkService.isOffline;

    _statusSubscription = _networkService.statusStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOffline = !isOnline;
        });
      }
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOffline) return const SizedBox.shrink();

    return Container(
      width: widget.size.w,
      height: widget.size.w,
      decoration: const BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
      ),
    );
  }
}
