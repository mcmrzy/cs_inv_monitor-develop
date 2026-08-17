import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:inv_app/core/services/role_service.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 底部导航栏：按角色/权限动态渲染导航项。
/// 自 app_router.dart 拆分而来。
class BottomNavBar extends StatefulWidget {
  const BottomNavBar({super.key});

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  bool _assetsPreloaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_assetsPreloaded) {
      _assetsPreloaded = true;
      // 预加载全部导航图标资产：切换 tab 时资产校验命中缓存同步完成，避免闪现 fallback 图标
      _CsergyNavigationIconState.preloadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;

    final isSystemAdmin = authState is AuthAuthenticated
        ? authState.isSystemAdmin
        : false;
    final permissions = authState is AuthAuthenticated
        ? authState.permissions
        : <String>[];

    final l10n = AppLocalizations.of(context)!;

    final navItems = RoleService.getNavItems(
      isSystemAdmin,
      permissions: permissions,
      labels: [
        l10n.navHome,
        l10n.navOverview,
        l10n.navDevice,
        l10n.navAlarm,
        l10n.navProfile,
      ],
    );

    final currentPath = GoRouterState.of(context).matchedLocation;

    final currentIndex = _selectedNavIndex(currentPath, navItems);
    final colorScheme = Theme.of(context).colorScheme;
    final selectedColor =
        Theme.of(context).bottomNavigationBarTheme.selectedItemColor ??
            colorScheme.primary;
    final unselectedColor = colorScheme.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) {
            if (index >= 0 && index < navItems.length) {
              context.go(navItems[index].path);
            }
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: colorScheme.surface,
          selectedItemColor: selectedColor,
          unselectedItemColor: unselectedColor,
          selectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w400, fontSize: 11),
          elevation: 0,
          items: navItems.map((item) {
            final label = _translateNavLabel(context, item.label);
            return BottomNavigationBarItem(
              icon: _CsergyNavigationIcon(
                item: item,
                label: label,
                selected: false,
                color: unselectedColor,
              ),
              activeIcon: _CsergyNavigationIcon(
                item: item,
                label: label,
                selected: true,
                color: selectedColor,
              ),
              label: label,
              tooltip: label,
            );
          }).toList(),
        ),
      ),
    );
  }

  int _selectedNavIndex(String currentPath, List<NavItem> navItems) {
    for (int i = 0; i < navItems.length; i++) {
      final path = navItems[i].path;
      if (currentPath == path || currentPath.startsWith('$path/')) {
        return i;
      }
    }

    return 0;
  }

  String _translateNavLabel(BuildContext context, String label) {
    final l10n = AppLocalizations.of(context);

    if (l10n == null) return label;

    switch (label) {
      case 'Home':
        return l10n.navHome;

      case 'Overview':
        return l10n.navOverview;

      case 'Device':
        return l10n.navDevice;

      case 'Alarm':
        return l10n.navAlarm;

      case 'Profile':
        return l10n.navProfile;

      default:
        return label;
    }
  }
}

class _CsergyNavigationIcon extends StatefulWidget {
  final NavItem item;
  final String label;
  final bool selected;
  final Color color;

  const _CsergyNavigationIcon({
    required this.item,
    required this.label,
    required this.selected,
    required this.color,
  });

  String get asset => selected ? item.activeIconAsset : item.iconAsset;

  IconData get fallbackIcon =>
      selected ? item.activeFallbackIcon : item.fallbackIcon;

  @override
  State<_CsergyNavigationIcon> createState() => _CsergyNavigationIconState();
}

class _CsergyNavigationIconState extends State<_CsergyNavigationIcon> {
  /// 全局 SVG 解析缓存：asset → PictureInfo。
  /// 命中缓存后 build 走同步绘制路径，切换 tab（normal/active 资产互换）时
  /// 不再经过 FutureBuilder 等待帧，彻底消除 fallback 图标闪现。
  static final Map<String, PictureInfo> _pictureCache =
      <String, PictureInfo>{};

  /// 预加载全部导航图标资产并解析为 Picture（fire-and-forget）。
  /// 解析失败的资产不缓存，由 FutureBuilder 回退 fallback 图标兜底。
  static Future<void> preloadAll() async {
    for (final nav in CsergyAssets.navAssets) {
      await _loadPicture(nav.normalAsset);
      await _loadPicture(nav.activeAsset);
    }
  }

  static Future<PictureInfo> _loadPicture(String asset) async {
    final cached = _pictureCache[asset];
    if (cached != null) return cached;
    final info = await vg.loadPicture(SvgAssetLoader(asset), null);
    _pictureCache[asset] = info;
    return info;
  }

  @override
  Widget build(BuildContext context) {
    final cached = _pictureCache[widget.asset];
    if (cached != null) {
      // 缓存命中：同步绘制，无异步等待帧
      return _buildAccessibleIcon(_buildPicture(cached));
    }
    // 首次加载（或预加载失败）：FutureBuilder 兜底，完成后同样走同步绘制
    return FutureBuilder<PictureInfo>(
      future: _loadPicture(widget.asset),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return _buildAccessibleIcon(_buildPicture(snapshot.data!));
        }
        return _buildAccessibleIcon(_buildFallbackIcon());
      },
    );
  }

  Widget _buildPicture(PictureInfo info) {
    return CustomPaint(
      size: const Size.square(CsergyAssets.navigationIconSize),
      painter: _NavSvgPainter(info, widget.color),
    );
  }

  Widget _buildAccessibleIcon(Widget child) {
    return Semantics(
      label: widget.label,
      image: true,
      child: child,
    );
  }

  Widget _buildFallbackIcon() {
    return Icon(
      widget.fallbackIcon,
      size: CsergyAssets.navigationIconSize,
      color: widget.color,
      semanticLabel: widget.label,
    );
  }
}

/// 同步绘制缓存 SVG Picture 的 painter（ColorFilter.srcIn 统一着色）。
/// 替代 SvgPicture.asset 的异步解析路径，避免导航切换时闪现 fallback 图标。
class _NavSvgPainter extends CustomPainter {
  _NavSvgPainter(this.info, this.color);

  final PictureInfo info;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final srcSize = info.size;
    if (srcSize.isEmpty || size.isEmpty) return;

    canvas.save();
    // 图层 + srcIn 着色，与 SvgPicture.colorFilter 效果一致
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
    );
    // 等比缩放居中（保持 SvgPicture fit: contain 的行为）
    final scale =
        math.min(size.width / srcSize.width, size.height / srcSize.height);
    canvas.translate(
      (size.width - srcSize.width * scale) / 2,
      (size.height - srcSize.height * scale) / 2,
    );
    canvas.scale(scale, scale);
    canvas.drawPicture(info.picture);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NavSvgPainter oldDelegate) =>
      oldDelegate.info != info || oldDelegate.color != color;
}
