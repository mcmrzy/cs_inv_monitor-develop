import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/auth/permission_codes.dart';
import 'package:inv_app/core/components/permission_gate.dart';
import 'package:inv_app/core/entities/organization.dart';
import 'package:inv_app/core/stores/organization_context_store.dart';
import 'package:inv_app/core/widgets/create_organization_dialog.dart';
import 'package:inv_app/core/widgets/org_selector_dialog.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:intl/intl.dart';

/// 组织浏览器屏幕
/// 以树形视图展示所有组织，支持切换上下文
class OrganizationBrowserScreen extends StatelessWidget {
  const OrganizationBrowserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _OrganizationBrowserScreenState();
  }
}

class _OrganizationBrowserScreenState extends StatefulWidget {
  const _OrganizationBrowserScreenState();

  @override
  State<_OrganizationBrowserScreenState> createState() =>
      _OrganizationBrowserScreenStateState();
}

class _OrganizationBrowserScreenStateState
    extends State<_OrganizationBrowserScreenState> {
  late OrganizationContextStore _orgStore;

  @override
  void initState() {
    super.initState();
    _orgStore = context.read<OrganizationContextStore>();

    // 初始化时加载组织列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _orgStore.loadAvailableOrganizations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.business),
            SizedBox(width: 8),
            Text('组织切换'),
          ],
        ),
        actions: [
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _orgStore.loadAvailableOrganizations(),
            tooltip: '刷新',
          ),

          // 后端仅允许系统管理员创建组织。
          RoleGuard(
            requireSystemAdmin: true,
            child: IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: _showCreateOrgDialog,
              tooltip: '创建组织',
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _orgStore,
        builder: (context, _) {
          final orgs = _orgStore.availableOrgs;

          // 错误提示
          if (_orgStore.error != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('错误：${_orgStore.error}'),
                ),
              );
            });
          }

          if (_orgStore.isLoading && orgs.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (orgs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.business_outlined,
                    size: 80.w,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    '暂无组织',
                    style: TextStyle(
                      fontSize: 18.sp,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    '联系管理员为您添加组织或创建新组织',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.8),
                    ),
                  ),
                  SizedBox(height: 24.h),
                  RoleGuard(
                    requireSystemAdmin: true,
                    child: FilledButton.icon(
                      onPressed: _showCreateOrgDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('创建组织'),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => _orgStore.loadAvailableOrganizations(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: orgs.length,
              itemBuilder: (context, index) {
                final org = orgs[index];
                return _OrganizationCard(
                  organization: org,
                  isActive: _orgStore.activeOrgId == org.id,
                  onTap: () => _selectOrganization(org),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoleGuard(
              requireSystemAdmin: true,
              child: FloatingActionButton.extended(
                onPressed: _showCreateOrgDialog,
                icon: const Icon(Icons.add),
                label: const Text('新建组织'),
              ),
            ),
            const SizedBox(height: 16),
            FloatingActionButton(
              heroTag: 'orgSwitch',
              onPressed: () async {
                final result = await showOrgSelectorDialog(context);
                if (result == true) {
                  // 用户切换了组织，可以刷新当前页面
                }
              },
              tooltip: '切换组织',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_horiz),
                  const SizedBox(width: 8),
                  if (_orgStore.activeOrgName != null)
                    Text(
                      _orgStore.activeOrgName!.substring(
                        0,
                        _orgStore.activeOrgName!.length > 6
                            ? 6
                            : _orgStore.activeOrgName!.length,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectOrganization(Organization org) async {
    try {
      await _orgStore.switchContextToOrganization(
        org.id,
        org.name,
        context.read<AuthBloc>(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换到 "${org.name}"'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换失败：$error')),
      );
    }
  }

  Future<void> _showCreateOrgDialog() async {
    final newOrg = await showDialog<Organization>(
      context: context,
      builder: (context) => CreateOrganizationDialog(
        onSubmit: ({required String name, String? description}) =>
            _orgStore.apiService.createOrganization(
          name: name,
          description: description,
        ),
      ),
    );

    if (!mounted || newOrg == null) return;
    _orgStore.addOrganization(newOrg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已创建组织 "${newOrg.name}"'),
      ),
    );
  }
}

/// 组织卡片组件
class _OrganizationCard extends StatelessWidget {
  final Organization organization;
  final bool isActive;
  final VoidCallback? onTap;

  const _OrganizationCard({
    required this.organization,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
        side: BorderSide(
          color: isActive ? theme.colorScheme.primary : Colors.transparent,
          width: isActive ? 2 : 0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(
            children: [
              // 图标区域
              Container(
                width: 56.w,
                height: 56.w,
                decoration: BoxDecoration(
                  gradient: isActive
                      ? LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.primaryContainer,
                          ],
                        )
                      : LinearGradient(
                          colors: [
                            theme.colorScheme.surfaceContainerHighest,
                            theme.colorScheme.surfaceContainerHighest,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  Icons.business,
                  color: Colors.white,
                  size: 32.sp,
                ),
              ),

              SizedBox(width: 16.w),

              // 组织信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          organization.name,
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        if (isActive) ...[
                          SizedBox(width: 8.w),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.w,
                              vertical: 2.h,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Text(
                              '当前',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    if (organization.description != null &&
                        organization.description!.isNotEmpty) ...[
                      SizedBox(height: 4.h),
                      Text(
                        organization.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],

                    SizedBox(height: 8.h),

                    // 统计信息
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        _StatChip(
                          icon: Icons.people,
                          label: '${organization.memberCount} 成员',
                        ),
                        _StatChip(
                          icon: Icons.devices,
                          label: '${organization.deviceCount} 设备',
                        ),
                        if (organization.createdAt != null)
                          _StatChip(
                            icon: Icons.calendar_today,
                            label:
                                '创建于 ${DateFormat('yyyy-MM-dd').format(DateTime.parse(organization.createdAt!))}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // 操作按钮
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  // TODO: 实现具体操作
                },
                itemBuilder: (context) {
                  final canManageMembers = PermChecker.hasCode(
                    context,
                    PermissionCodes.organizationsManageMembers,
                    requiredOrgId: organization.id,
                  );
                  final canManageDevice = PermChecker.hasCode(
                    context,
                    PermissionCodes.devicesManage,
                    requiredOrgId: organization.id,
                  );
                  return [
                    const PopupMenuItem(
                      value: 'view',
                      child: Row(
                        children: [
                          Icon(Icons.visibility),
                          SizedBox(width: 8),
                          Text('查看详情'),
                        ],
                      ),
                    ),
                    if (canManageMembers)
                      const PopupMenuItem(
                        value: 'members',
                        child: Row(
                          children: [
                            Icon(Icons.people),
                            SizedBox(width: 8),
                            Text('管理成员'),
                          ],
                        ),
                      ),
                    if (canManageDevice)
                      const PopupMenuItem(
                        value: 'devices',
                        child: Row(
                          children: [
                            Icon(Icons.devices),
                            SizedBox(width: 8),
                            Text('管理设备'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'settings',
                      child: Row(
                        children: [
                          Icon(Icons.settings),
                          SizedBox(width: 8),
                          Text('设置'),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 统计 Chip 组件
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14.sp,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          SizedBox(width: 4.w),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
