import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:inv_app/core/router/shell/bottom_nav_bar.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/profile/data/profile_setup_storage.dart';
import 'package:inv_app/features/profile/presentation/widgets/profile_setup_dialog.dart';

/// 主框架 Shell：承载底部导航 + 页面切换动画，
/// 并负责进入主页后的一次性副作用（完善资料提示）。
/// 自 app_router.dart 拆分而来，路由文件仅保留路由表。
class MainShell extends StatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // 完善个人信息弹窗：本次启动仅提示一次（跳过或已设置后不再弹）
  static bool _hasShownProfilePrompt = false;

  // 等待 profile 刷新完成后再判断是否弹出完善资料弹窗的订阅
  StreamSubscription<AuthState>? _profileSetupSubscription;

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
  }

  @override
  void dispose() {
    _profileSetupSubscription?.cancel();
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
    unawaited(_showProfileSetupIfNotDismissed(authState.userId));
  }

  /// 用户此前跳过过、或保存过资料，就不再弹（标记按用户 id 持久化）
  Future<void> _showProfileSetupIfNotDismissed(int userId) async {
    if (await ProfileSetupStorage().isDone(userId)) return;
    if (!mounted) return;
    ProfileSetupDialog.show(context);
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
