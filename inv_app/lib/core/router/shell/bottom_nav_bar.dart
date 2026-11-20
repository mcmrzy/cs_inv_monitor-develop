import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:inv_app/core/services/role_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 底部导航栏：按角色/权限动态渲染导航项。
/// 自 app_router.dart 拆分而来。
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;

    final isSystemAdmin =
        authState is AuthAuthenticated ? authState.isSystemAdmin : false;
    final permissions =
        authState is AuthAuthenticated ? authState.permissions : <String>[];

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
    final activeColor = AppColor.primary(context);
    final muted = AppColor.textSecondary(context);

    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColor.divider(context))),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) => context.go(navItems[index].path),
        destinations: [
          for (final item in navItems)
            _destination(
              item,
              inactive: muted,
              active: activeColor,
            ),
        ],
        height: 68,
        backgroundColor: AppColor.surfaceContainer(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AppColor.primarySoft(context),
        labelPadding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? activeColor : muted,
            fontSize: 11,
            height: 1.15,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
      ),
    );
  }

  NavigationDestination _destination(
    NavItem item, {
    required Color inactive,
    required Color active,
  }) {
    final (outline, selected) = switch (item.path) {
      '/statistics' => (Icons.bar_chart_outlined, Icons.bar_chart_rounded),
      '/devices' => (
          Icons.developer_board_outlined,
          Icons.developer_board_rounded
        ),
      '/alarms' => (
          Icons.notifications_none_rounded,
          Icons.notifications_rounded,
        ),
      '/profile' => (Icons.person_outline_rounded, Icons.person_rounded),
      _ => (Icons.home_outlined, Icons.home_rounded),
    };
    return NavigationDestination(
      label: item.label,
      icon: Icon(outline, size: 24, color: inactive),
      selectedIcon: Icon(selected, size: 24, color: active),
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
}
