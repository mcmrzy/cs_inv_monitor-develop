import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    final state = context.read<AuthBloc>().state;
    if (state is! AuthAuthenticated && state is! AuthLoading) {
      context.read<AuthBloc>().add(AuthCheckRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('我的', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: AppColors.textPrimary)),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: Colors.white,
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthUnauthenticated) context.go('/login');
        },
        builder: (context, state) {
          String phone = '';
          int role = 5;
          if (state is AuthAuthenticated) {
            phone = state.phone;
            role = state.role;
          }
          final isLoading = state is AuthLoading || state is AuthInitial;

          return ListView(
            children: [
              _buildHeader(phone, role, isLoading),
              _buildMenuSection(context),
              _buildLogoutButton(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(String phone, int role, bool isLoading) {
    String roleText = '用户';
    switch (role) {
      case 1: roleText = '原厂';
      case 2: roleText = '总代理';
      case 3: roleText = '经销商';
      case 4: roleText = '安装商';
    }

    final displayName = phone.isNotEmpty ? phone : '已登录';

    return Container(
      padding: EdgeInsets.all(20.w),
      margin: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          Container(
            width: 56.w, height: 56.w,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Icon(Icons.person_rounded, size: 28.sp, color: AppColors.primary),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isLoading)
                  Container(
                    width: 100.w, height: 16.h,
                    decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(4.r)),
                  )
                else
                  Text(displayName,
                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                SizedBox(height: 4.h),
                if (isLoading)
                  Container(
                    width: 60.w, height: 12.h,
                    decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(4.r)),
                  )
                else
                  Text('角色: $roleText',
                      style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 20.sp, color: AppColors.textHint),
        ],
      ),
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    final items = [
      (Icons.solar_power_rounded, '我的电站', () => context.go('/home')),
      (Icons.devices_rounded, '我的设备', () => context.go('/devices')),
      (Icons.notifications_outlined, '消息通知设置', () => context.push('/notify-settings')),
      (Icons.settings_outlined, '系统设置', () => context.push('/settings')),
      (Icons.lock_outlined, '修改密码', () => context.push('/change-password')),
      (Icons.info_outline, '关于我们', () => context.push('/about')),
    ];

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      padding: EdgeInsets.symmetric(vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        children: items.map((item) => ListTile(
          leading: Icon(item.$1, size: 22.sp, color: AppColors.textSecondary),
          title: Text(item.$2, style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary)),
          trailing: Icon(Icons.chevron_right_rounded, size: 18.sp, color: AppColors.textHint),
          onTap: item.$3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
        )).toList(),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: OutlinedButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('退出登录'),
              content: const Text('确定要退出登录吗？'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.read<AuthBloc>().add(AuthLogoutRequested());
                  },
                  style: FilledButton.styleFrom(backgroundColor: AppColors.errorLight),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.errorLight,
          side: BorderSide(color: AppColors.errorLight.withValues(alpha: 0.2)),
          padding: EdgeInsets.symmetric(vertical: 14.h),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
        ),
        child: const Text('退出登录'),
      ),
    );
  }
}
